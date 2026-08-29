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
    Write-Host "ENEMY_REPAIR_PIPELINE=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_REGENERATE_OR_DELETE_UMAP" -ForegroundColor Yellow
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
$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\PIE"

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

# Confirm real Unreal package header.
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
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\FixBackups\EnemyPopulation_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
Copy-Item -LiteralPath $MapFile -Destination (Join-Path $BackupRoot "Jeddah_RedSea_Assault.umap") -Force

$ExternalPaths = @(
    (Join-Path $ProjectRoot "Content\__ExternalActors__\Maps\Jeddah_RedSea_Assault"),
    (Join-Path $ProjectRoot "Content\__ExternalObjects__\Maps\Jeddah_RedSea_Assault")
)

foreach ($Path in $ExternalPaths) {
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $ParentName = Split-Path (Split-Path $Path -Parent) -Leaf
        $Leaf = Split-Path $Path -Leaf
        $Dest = Join-Path $BackupRoot "$ParentName\$Leaf"
        New-Item -ItemType Directory -Force -Path (Split-Path $Dest -Parent) | Out-Null
        Copy-Item -LiteralPath $Path -Destination $Dest -Recurse -Force
    }
}

Write-Host "BACKUP=$BackupRoot" -ForegroundColor Green

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$RepairPy = Join-Path $EvidenceRoot "repair_exact_three_enemies_$Stamp.py"
$RepairLog = Join-Path $EvidenceRoot "repair_exact_three_enemies_$Stamp.log"
$VerifyPy = Join-Path $EvidenceRoot "verify_exact_three_enemies_$Stamp.py"
$VerifyLog = Join-Path $EvidenceRoot "verify_exact_three_enemies_$Stamp.log"

$RepairPython = @'
import unreal

MAP = "/Game/Maps/Jeddah_RedSea_Assault"
SOLDIER_CLASS_PATH = "/Script/ArabiaStrikeWorldWar.ASSoldierCharacter"

def require(value, message):
    if not value:
        raise RuntimeError(message)

def save_all(level_subsystem):
    saved_level = False
    try:
        saved_level = bool(level_subsystem.save_current_level())
    except Exception as exc:
        unreal.log_warning(f"ASWW_SAVE_CURRENT_LEVEL_EXCEPTION={exc}")

    saved_dirty = False
    try:
        result = unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True, True)
        saved_dirty = True if result is None else bool(result)
    except Exception as exc:
        unreal.log_warning(f"ASWW_SAVE_DIRTY_PACKAGES_EXCEPTION={exc}")

    unreal.log(f"ASWW_SAVE_CURRENT_LEVEL={saved_level}")
    unreal.log(f"ASWW_SAVE_DIRTY_PACKAGES={saved_dirty}")

def main():
    level_subsystem = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    editor_subsystem = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
    actor_subsystem = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

    require(level_subsystem is not None, "LevelEditorSubsystem unavailable")
    require(editor_subsystem is not None, "UnrealEditorSubsystem unavailable")
    require(actor_subsystem is not None, "EditorActorSubsystem unavailable")
    require(level_subsystem.load_level(MAP), "Failed to load Jeddah")

    descs = list(unreal.WorldPartitionBlueprintLibrary.get_actor_descs())
    enemy_descs = [d for d in descs if str(d.label).startswith("ASWW_Enemy_")]

    unreal.log(f"ASWW_ENEMY_DESC_BEFORE={len(enemy_descs)}")
    for d in enemy_descs:
        unreal.log(
            f"ASWW_ENEMY_BEFORE=label={d.label}|actor_path={d.actor_path}|package={d.actor_package}"
        )

    # This repair is intentionally narrow. Stop if the map is no longer in the
    # exact state that was diagnosed.
    require(len(enemy_descs) == 2, f"Expected exactly 2 diagnosed enemy descriptors, found {len(enemy_descs)}")
    require(all(str(d.label) == "ASWW_Enemy_01" for d in enemy_descs),
            "Expected both diagnosed enemy descriptors to be labeled ASWW_Enemy_01")
    require(all("ASSoldierCharacter" in str(d.actor_path) for d in enemy_descs),
            "Diagnosed enemy descriptors are not ASSoldierCharacter actors")

    unreal.WorldPartitionBlueprintLibrary.load_actors([d.guid for d in enemy_descs])

    actors = [
        a for a in actor_subsystem.get_all_level_actors()
        if a.get_actor_label().startswith("ASWW_Enemy_")
    ]
    require(len(actors) == 2, f"Expected exactly 2 loaded enemy actors, found {len(actors)}")
    require(all(a.get_class().get_name() == "ASSoldierCharacter" for a in actors),
            "Loaded enemy actors are not ASSoldierCharacter")

    # Deterministic ordering; keep one as Enemy_01 and repurpose the duplicate as Enemy_02.
    actors.sort(key=lambda a: a.get_path_name())
    enemy1, enemy2 = actors

    base = enemy1.get_actor_location()
    base_rot = enemy1.get_actor_rotation()

    spatial = True
    try:
        spatial = bool(enemy1.get_editor_property("is_spatially_loaded"))
    except Exception:
        pass

    enemy1.set_actor_label("ASWW_Enemy_01", mark_dirty=True)
    enemy1.set_actor_location(unreal.Vector(base.x, base.y, base.z), False, False)

    enemy2.set_actor_label("ASWW_Enemy_02", mark_dirty=True)
    enemy2.set_actor_location(unreal.Vector(base.x, base.y + 600.0, base.z), False, False)
    try:
        enemy2.set_editor_property("is_spatially_loaded", spatial)
    except Exception:
        pass

    soldier_class = unreal.load_class(None, SOLDIER_CLASS_PATH)
    require(soldier_class is not None, "ASSoldierCharacter class failed to load")

    enemy3 = actor_subsystem.spawn_actor_from_class(
        soldier_class,
        unreal.Vector(base.x, base.y + 1200.0, base.z),
        base_rot
    )
    require(enemy3 is not None, "Failed to spawn ASWW_Enemy_03")
    enemy3.set_actor_label("ASWW_Enemy_03", mark_dirty=True)
    try:
        enemy3.set_editor_property("is_spatially_loaded", spatial)
    except Exception:
        pass

    save_all(level_subsystem)

    unreal.log(
        f"ASWW_ENEMY_REPAIR_POSITIONS="
        f"01=({base.x:.1f},{base.y:.1f},{base.z:.1f})|"
        f"02=({base.x:.1f},{base.y + 600.0:.1f},{base.z:.1f})|"
        f"03=({base.x:.1f},{base.y + 1200.0:.1f},{base.z:.1f})"
    )
    unreal.log(f"ASWW_ENEMY_SPATIAL={spatial}")
    unreal.log("ASWW_ENEMY_REPAIR=PASS")

if __name__ == "__main__":
    main()
'@

$VerifyPython = @'
import unreal

MAP = "/Game/Maps/Jeddah_RedSea_Assault"

def require(value, message):
    if not value:
        raise RuntimeError(message)

def main():
    level_subsystem = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    actor_subsystem = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

    require(level_subsystem.load_level(MAP), "Failed to reload Jeddah")

    descs = list(unreal.WorldPartitionBlueprintLibrary.get_actor_descs())
    enemy_descs = [d for d in descs if str(d.label).startswith("ASWW_Enemy_")]

    labels = sorted(str(d.label) for d in enemy_descs)
    unreal.log(f"ASWW_ENEMY_DESC_AFTER={len(enemy_descs)}")
    unreal.log("ASWW_ENEMY_LABELS_AFTER=" + ",".join(labels))

    require(len(enemy_descs) == 3, f"Expected exactly 3 enemy descriptors after repair, found {len(enemy_descs)}")
    require(labels == ["ASWW_Enemy_01","ASWW_Enemy_02","ASWW_Enemy_03"],
            "Enemy labels are not exactly ASWW_Enemy_01/02/03")
    require(all("ASSoldierCharacter" in str(d.actor_path) for d in enemy_descs),
            "One or more repaired enemies are not ASSoldierCharacter")

    unreal.WorldPartitionBlueprintLibrary.load_actors([d.guid for d in enemy_descs])
    actors = [
        a for a in actor_subsystem.get_all_level_actors()
        if a.get_actor_label().startswith("ASWW_Enemy_")
    ]

    for a in sorted(actors, key=lambda x: x.get_actor_label()):
        loc = a.get_actor_location()
        unreal.log(
            f"ASWW_ENEMY_ACTOR_AFTER=label={a.get_actor_label()}|class={a.get_class().get_name()}|"
            f"location=({loc.x:.1f},{loc.y:.1f},{loc.z:.1f})"
        )

    require(len(actors) == 3, f"Expected 3 loaded repaired enemy actors, found {len(actors)}")
    unreal.log("ASWW_ENEMY_VERIFY=PASS")

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
Write-Host " TARGETED ENEMY POPULATION REPAIR" -ForegroundColor Cyan
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
$RepairPass = $RepairText -match "ASWW_ENEMY_REPAIR=PASS"

Write-Host ""
Write-Host "REPAIR_EDITOR_EXIT=$RepairExit"
Write-Host "REPAIR_PASS_MARKER=$RepairPass"
Write-Host "REPAIR_LOG=$RepairLog"

if ($RepairExit -ne 0 -or -not $RepairPass) {
    Write-Host ""
    Write-Host "=== ENEMY REPAIR ROOT CAUSE ===" -ForegroundColor Yellow
    Select-String -LiteralPath $RepairLog `
        -Pattern "ASWW_|LogPython:\s*Error|Traceback|RuntimeError:|AttributeError:|TypeError:|Failed" `
        -Context 5,16 |
        Select-Object -First 120
    Stop-Gate "TARGETED_ENEMY_REPAIR_FAILED" $(if ($RepairExit -ne 0) { $RepairExit } else { 30 })
}

Write-Host "TARGETED_ENEMY_REPAIR=PASS" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FRESH ENEMY DESCRIPTOR VERIFICATION" -ForegroundColor Cyan
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
$VerifyPass = $VerifyText -match "ASWW_ENEMY_VERIFY=PASS"

Write-Host ""
Write-Host "VERIFY_EDITOR_EXIT=$VerifyExit"
Write-Host "VERIFY_PASS_MARKER=$VerifyPass"
Write-Host "VERIFY_LOG=$VerifyLog"

Select-String -LiteralPath $VerifyLog `
    -Pattern "ASWW_ENEMY_DESC_AFTER=|ASWW_ENEMY_LABELS_AFTER=|ASWW_ENEMY_ACTOR_AFTER=|ASWW_ENEMY_VERIFY=" |
    Select-Object -First 40

if ($VerifyExit -ne 0 -or -not $VerifyPass) {
    Stop-Gate "FRESH_ENEMY_VERIFICATION_FAILED" $(if ($VerifyExit -ne 0) { $VerifyExit } else { 40 })
}

Write-Host "ENEMY_POPULATION=EXACTLY_3_VERIFIED" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RERUN EXACT PIE TEST" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ExactPieRunner -ProjectRoot $ProjectRoot -UERoot $UERoot
$PieExit = $LASTEXITCODE

Write-Host ""
Write-Host "EXACT_PIE_RERUN_EXIT=$PieExit"

if ($PieExit -ne 0) {
    Stop-Gate "EXACT_PIE_STILL_FAILS_AFTER_3_ENEMY_REPAIR" $PieExit
}

Write-Host "PIE_STARTUP_SMOKE=PASS_STARTUP_ONLY" -ForegroundColor Green
Write-Host "NEXT_GATE=AUDIT_DUPLICATE_PROTOTYPE_ACTORS_BEFORE_PACKAGE" -ForegroundColor Green
Write-Host "DO_NOT_PACKAGE_YET_UNTIL_DUPLICATE_AUDIT" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
