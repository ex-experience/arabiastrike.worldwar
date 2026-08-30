[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "DUPLICATE_CLEANUP_PIPELINE=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

Set-Location $ProjectRoot

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$MapFile = Join-Path $ProjectRoot "Content\Maps\Jeddah_RedSea_Assault.umap"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$ExactPieRunner = Join-Path $ProjectRoot "ASWW_RUN_EXACT_PIE_TEST.ps1"
$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\JeddahMap"

foreach ($Required in @($ProjectFile,$MapFile,$EditorCmd,$ExactPieRunner)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_$Required" 11
    }
}

$RunningEditors = @(Get-Process UnrealEditor,UnrealEditor-Cmd -ErrorAction SilentlyContinue)
if ($RunningEditors.Count -gt 0) {
    $RunningEditors | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ALL_UNREAL_EDITOR_PROCESSES_FIRST" 12
}

# Verify the real Unreal package header before touching anything.
$Stream = [IO.File]::OpenRead($MapFile)
try {
    $Reader = [IO.BinaryReader]::new($Stream)
    try { $Magic = $Reader.ReadUInt32() }
    finally { $Reader.Dispose() }
}
finally { $Stream.Dispose() }

$Expected = [Convert]::ToUInt32("9E2A83C1",16)
Write-Host ("MAP_MAGIC=0x{0:X8}" -f $Magic)
if ($Magic -ne $Expected) {
    Stop-Gate "INVALID_UNREAL_PACKAGE_HEADER" 13
}
Write-Host "REAL_UNREAL_PACKAGE_HEADER=True" -ForegroundColor Green

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\FixBackups\DuplicatePrototypeCleanup_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

Copy-Item -LiteralPath $MapFile -Destination (Join-Path $BackupRoot "Jeddah_RedSea_Assault.umap") -Force

$ExternalActorRoot = Join-Path $ProjectRoot "Content\__ExternalActors__\Maps\Jeddah_RedSea_Assault"
$ExternalObjectRoot = Join-Path $ProjectRoot "Content\__ExternalObjects__\Maps\Jeddah_RedSea_Assault"

if (Test-Path -LiteralPath $ExternalActorRoot -PathType Container) {
    Copy-Item -LiteralPath $ExternalActorRoot -Destination (Join-Path $BackupRoot "__ExternalActors__") -Recurse -Force
}
if (Test-Path -LiteralPath $ExternalObjectRoot -PathType Container) {
    Copy-Item -LiteralPath $ExternalObjectRoot -Destination (Join-Path $BackupRoot "__ExternalObjects__") -Recurse -Force
}

Write-Host "BACKUP=$BackupRoot" -ForegroundColor Green

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$RepairPy = Join-Path $EvidenceRoot "cleanup_duplicate_prototypes_$Stamp.py"
$RepairLog = Join-Path $EvidenceRoot "cleanup_duplicate_prototypes_$Stamp.log"
$VerifyPy = Join-Path $EvidenceRoot "verify_duplicate_cleanup_$Stamp.py"
$VerifyLog = Join-Path $EvidenceRoot "verify_duplicate_cleanup_$Stamp.log"

$RepairPython = @'
import unreal
from collections import defaultdict

MAP = "/Game/Maps/Jeddah_RedSea_Assault"

DUPLICATE_LABELS = [
    "ASWW_CommandMech_Encounter",
    "ASWW_Extraction_Prototype",
    "ASWW_Ground",
    "ASWW_Helicopter_Encounter",
    "ASWW_Hummer_Test",
    "ASWW_MissionDirector",
    "ASWW_SpawnApron",
    "ASWW_WorldBootstrap",
]

def require(v, msg):
    if not v:
        raise RuntimeError(msg)

def save_all(level_subsystem):
    result_level = False
    try:
        result_level = bool(level_subsystem.save_current_level())
    except Exception as exc:
        unreal.log_warning(f"ASWW_SAVE_CURRENT_LEVEL_EXCEPTION={exc}")

    result_dirty = False
    try:
        result = unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True, True)
        result_dirty = True if result is None else bool(result)
    except Exception as exc:
        unreal.log_warning(f"ASWW_SAVE_DIRTY_PACKAGES_EXCEPTION={exc}")

    unreal.log(f"ASWW_SAVE_CURRENT_LEVEL={result_level}")
    unreal.log(f"ASWW_SAVE_DIRTY_PACKAGES={result_dirty}")

def choose_keep(actors):
    # The surviving non-duplicate foundation actors (PlayerStart, lighting, nav)
    # are from the _171... generation. Prefer that cohort when exactly one
    # candidate belongs to it. Otherwise fall back to deterministic path order.
    cohort_171 = [a for a in actors if "_171" in a.get_path_name()]
    if len(cohort_171) == 1:
        return cohort_171[0], "FOUNDATION_171_COHORT"
    ordered = sorted(actors, key=lambda a: a.get_path_name())
    return ordered[0], "LEXICAL_FALLBACK"

def main():
    level_subsystem = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    actor_subsystem = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

    require(level_subsystem is not None, "LevelEditorSubsystem unavailable")
    require(actor_subsystem is not None, "EditorActorSubsystem unavailable")
    require(level_subsystem.load_level(MAP), "Failed to load Jeddah")

    descs = list(unreal.WorldPartitionBlueprintLibrary.get_actor_descs())
    by_label = defaultdict(list)

    for d in descs:
        label = str(d.label)
        if label in DUPLICATE_LABELS:
            by_label[label].append(d)

    # Refuse to mutate if the diagnosed state has changed.
    for label in DUPLICATE_LABELS:
        count = len(by_label.get(label, []))
        unreal.log(f"ASWW_CLEANUP_PRECOUNT={label}|count={count}")
        require(count == 2, f"{label} expected exactly 2 descriptors before cleanup, found {count}")

    guids = [d.guid for label in DUPLICATE_LABELS for d in by_label[label]]
    unreal.WorldPartitionBlueprintLibrary.load_actors(guids)

    loaded = defaultdict(list)
    for actor in actor_subsystem.get_all_level_actors():
        label = actor.get_actor_label()
        if label in DUPLICATE_LABELS:
            loaded[label].append(actor)

    for label in DUPLICATE_LABELS:
        actors = loaded[label]
        require(len(actors) == 2, f"{label} expected exactly 2 loaded actors, found {len(actors)}")

        # Deep read-only compare already established equivalence on audited runtime fields.
        keep, reason = choose_keep(actors)
        delete = actors[0] if actors[1] is keep else actors[1]

        unreal.log(f"ASWW_CLEANUP_KEEP={label}|reason={reason}|path={keep.get_path_name()}")
        unreal.log(f"ASWW_CLEANUP_DELETE={label}|path={delete.get_path_name()}")

        ok = actor_subsystem.destroy_actor(delete)
        require(bool(ok), f"Failed to destroy duplicate actor for {label}")

    save_all(level_subsystem)
    unreal.log("ASWW_DUPLICATE_CLEANUP=PASS")

if __name__ == "__main__":
    main()
'@

$VerifyPython = @'
import unreal
from collections import defaultdict

MAP = "/Game/Maps/Jeddah_RedSea_Assault"

EXPECTED_ONE = [
    "ASWW_CommandMech_Encounter",
    "ASWW_Extraction_Prototype",
    "ASWW_Ground",
    "ASWW_Helicopter_Encounter",
    "ASWW_Hummer_Test",
    "ASWW_MissionDirector",
    "ASWW_SpawnApron",
    "ASWW_WorldBootstrap",
    "ASWW_Enemy_01",
    "ASWW_Enemy_02",
    "ASWW_Enemy_03",
    "ASWW_PlayerStart_Primary",
]

def require(v, msg):
    if not v:
        raise RuntimeError(msg)

def main():
    level_subsystem = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    require(level_subsystem.load_level(MAP), "Failed to reload Jeddah")

    descs = list(unreal.WorldPartitionBlueprintLibrary.get_actor_descs())
    counts = defaultdict(int)
    for d in descs:
        counts[str(d.label)] += 1

    bad = []
    for label in EXPECTED_ONE:
        count = counts.get(label, 0)
        unreal.log(f"ASWW_POSTCLEAN_COUNT={label}|count={count}")
        if count != 1:
            bad.append(f"{label}:{count}")

    require(not bad, "Post-cleanup label counts invalid: " + ",".join(bad))
    unreal.log("ASWW_DUPLICATE_CLEANUP_VERIFY=PASS")

if __name__ == "__main__":
    main()
'@

[IO.File]::WriteAllText($RepairPy, $RepairPython, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($VerifyPy, $VerifyPython, [Text.UTF8Encoding]::new($false))

$ProjectForUE = $ProjectFile.Replace('\','/')
$RepairForUE = $RepairPy.Replace('\','/')
$VerifyForUE = $VerifyPy.Replace('\','/')

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SAFE SINGLE-COPY DUPLICATE CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$RepairArgs = @(
    $ProjectForUE,
    "-ExecutePythonScript=$RepairForUE",
    "-Unattended",
    "-NoSplash",
    "-NoSound",
    "-NullRHI",
    "-NoSourceControl",
    "-stdout",
    "-FullStdOutLogOutput"
)

& $EditorCmd @RepairArgs 2>&1 | Tee-Object -FilePath $RepairLog
$RepairExit = $LASTEXITCODE
$RepairText = if (Test-Path -LiteralPath $RepairLog) { Get-Content -Raw -LiteralPath $RepairLog } else { "" }
$RepairPass = $RepairText -match "ASWW_DUPLICATE_CLEANUP=PASS"

Write-Host ""
Write-Host "CLEANUP_EDITOR_EXIT=$RepairExit"
Write-Host "CLEANUP_PASS_MARKER=$RepairPass"
Write-Host "CLEANUP_LOG=$RepairLog"

Select-String -LiteralPath $RepairLog `
    -Pattern "ASWW_CLEANUP_KEEP=|ASWW_CLEANUP_DELETE=|ASWW_DUPLICATE_CLEANUP=" |
    Select-Object -First 80

if ($RepairExit -ne 0 -or -not $RepairPass) {
    Write-Host ""
    Write-Host "=== CLEANUP ROOT CAUSE ===" -ForegroundColor Yellow
    Select-String -LiteralPath $RepairLog `
        -Pattern "ASWW_|LogPython:\s*Error|Traceback|RuntimeError:|AttributeError:|TypeError:|Failed" `
        -Context 5,16 |
        Select-Object -First 140
    Stop-Gate "DUPLICATE_CLEANUP_FAILED" $(if ($RepairExit -ne 0) { $RepairExit } else { 30 })
}

Write-Host "TARGETED_DUPLICATE_CLEANUP=PASS" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FRESH POST-CLEANUP DESCRIPTOR VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$VerifyArgs = @(
    $ProjectForUE,
    "-ExecutePythonScript=$VerifyForUE",
    "-Unattended",
    "-NoSplash",
    "-NoSound",
    "-NullRHI",
    "-NoSourceControl",
    "-stdout",
    "-FullStdOutLogOutput"
)

& $EditorCmd @VerifyArgs 2>&1 | Tee-Object -FilePath $VerifyLog
$VerifyExit = $LASTEXITCODE
$VerifyText = if (Test-Path -LiteralPath $VerifyLog) { Get-Content -Raw -LiteralPath $VerifyLog } else { "" }
$VerifyPass = $VerifyText -match "ASWW_DUPLICATE_CLEANUP_VERIFY=PASS"

Write-Host ""
Write-Host "VERIFY_EDITOR_EXIT=$VerifyExit"
Write-Host "VERIFY_PASS_MARKER=$VerifyPass"
Write-Host "VERIFY_LOG=$VerifyLog"

Select-String -LiteralPath $VerifyLog `
    -Pattern "ASWW_POSTCLEAN_COUNT=|ASWW_DUPLICATE_CLEANUP_VERIFY=" |
    Select-Object -First 80

if ($VerifyExit -ne 0 -or -not $VerifyPass) {
    Stop-Gate "POST_CLEANUP_DESCRIPTOR_VERIFICATION_FAILED" $(if ($VerifyExit -ne 0) { $VerifyExit } else { 40 })
}

Write-Host "DUPLICATE_COUNTS=EXACTLY_ONE_EACH" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " EXACT PIE REGRESSION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ExactPieRunner -ProjectRoot $ProjectRoot -UERoot $UERoot
$PieExit = $LASTEXITCODE

Write-Host ""
Write-Host "EXACT_PIE_AFTER_CLEANUP_EXIT=$PieExit"

if ($PieExit -ne 0) {
    Stop-Gate "PIE_REGRESSION_AFTER_DUPLICATE_CLEANUP" $PieExit
}

Write-Host ""
Write-Host "DUPLICATE_CLEANUP_PIPELINE=PASS" -ForegroundColor Green
Write-Host "PIE_STARTUP_SMOKE=PASS_STARTUP_ONLY" -ForegroundColor Green
Write-Host "NEXT_GATE=WIN64_PACKAGE" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
