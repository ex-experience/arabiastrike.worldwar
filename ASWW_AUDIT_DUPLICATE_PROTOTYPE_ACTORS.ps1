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
    Write-Host "DUPLICATE_AUDIT=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_MAP_CHANGES_WERE_MADE" -ForegroundColor Green
    Write-Host "DO_NOT_PACKAGE_YET" -ForegroundColor Yellow
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
$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\JeddahMap"

foreach ($Required in @($ProjectFile,$MapFile,$EditorCmd)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_$Required" 11
    }
}

$RunningEditors = @(Get-Process UnrealEditor,UnrealEditor-Cmd -ErrorAction SilentlyContinue)
if ($RunningEditors.Count -gt 0) {
    $RunningEditors | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ALL_UNREAL_EDITOR_PROCESSES_FIRST" 12
}

# Verify map package header.
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

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Py = Join-Path $EvidenceRoot "audit_duplicate_prototypes_$Stamp.py"
$Log = Join-Path $EvidenceRoot "audit_duplicate_prototypes_$Stamp.log"

$Python = @'
import unreal
from collections import defaultdict

MAP = "/Game/Maps/Jeddah_RedSea_Assault"

WATCHED_LABELS = {
    "ASWW_Ground",
    "ASWW_SpawnApron",
    "ASWW_PlayerStart_Primary",
    "ASWW_Sun",
    "ASWW_SkyLight",
    "ASWW_SkyAtmosphere",
    "ASWW_HeightFog",
    "ASWW_NavMeshBounds",
    "ASWW_MissionDirector",
    "ASWW_WorldBootstrap",
    "ASWW_Enemy_01",
    "ASWW_Enemy_02",
    "ASWW_Enemy_03",
    "ASWW_Hummer_Test",
    "ASWW_Helicopter_Encounter",
    "ASWW_CommandMech_Encounter",
    "ASWW_Extraction_Prototype",
}

def require(value, message):
    if not value:
        raise RuntimeError(message)

def safe_attr(obj, name):
    try:
        value = getattr(obj, name)
        return value() if callable(value) else value
    except Exception:
        return "<unavailable>"

def main():
    level_subsystem = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    actor_subsystem = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    editor_subsystem = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)

    require(level_subsystem is not None, "LevelEditorSubsystem unavailable")
    require(actor_subsystem is not None, "EditorActorSubsystem unavailable")
    require(editor_subsystem is not None, "UnrealEditorSubsystem unavailable")
    require(level_subsystem.load_level(MAP), "Failed to load Jeddah")

    world = editor_subsystem.get_editor_world()
    require(world is not None, "Editor world unavailable")
    wp = world.get_world_settings().get_editor_property("world_partition")
    require(wp is not None, "World Partition unavailable")

    descs = list(unreal.WorldPartitionBlueprintLibrary.get_actor_descs())
    watched = defaultdict(list)

    for desc in descs:
        label = str(safe_attr(desc, "label"))
        if label in WATCHED_LABELS:
            watched[label].append(desc)

    unreal.log(f"ASWW_AUDIT_DESC_TOTAL={len(descs)}")

    duplicate_labels = []
    missing_labels = []
    descriptor_guids = []

    for label in sorted(WATCHED_LABELS):
        items = watched.get(label, [])
        count = len(items)
        unreal.log(f"ASWW_AUDIT_COUNT={label}|count={count}")

        if count == 0:
            missing_labels.append(label)
        if count > 1:
            duplicate_labels.append(label)

        for desc in items:
            guid = safe_attr(desc, "guid")
            descriptor_guids.append(guid)
            unreal.log(
                "ASWW_AUDIT_DESC="
                f"label={label}|guid={guid}|"
                f"spatial={safe_attr(desc,'is_spatially_loaded')}|"
                f"runtime_grid={safe_attr(desc,'runtime_grid')}|"
                f"actor_path={safe_attr(desc,'actor_path')}|"
                f"package={safe_attr(desc,'actor_package')}"
            )

    if descriptor_guids:
        unreal.WorldPartitionBlueprintLibrary.load_actors(descriptor_guids)

    actors_by_label = defaultdict(list)
    for actor in actor_subsystem.get_all_level_actors():
        label = actor.get_actor_label()
        if label in WATCHED_LABELS:
            actors_by_label[label].append(actor)

    for label in sorted(WATCHED_LABELS):
        actors = actors_by_label.get(label, [])
        for actor in actors:
            loc = actor.get_actor_location()
            rot = actor.get_actor_rotation()
            cls = actor.get_class().get_name()
            spatial = "<unavailable>"
            try:
                spatial = actor.get_editor_property("is_spatially_loaded")
            except Exception:
                pass
            unreal.log(
                "ASWW_AUDIT_ACTOR="
                f"label={label}|class={cls}|"
                f"location=({loc.x:.1f},{loc.y:.1f},{loc.z:.1f})|"
                f"rotation=({rot.pitch:.1f},{rot.yaw:.1f},{rot.roll:.1f})|"
                f"spatial={spatial}|path={actor.get_path_name()}"
            )

    unreal.log(
        "ASWW_AUDIT_DUPLICATE_LABELS=" +
        ("NONE" if not duplicate_labels else ",".join(sorted(duplicate_labels)))
    )
    unreal.log(
        "ASWW_AUDIT_MISSING_LABELS=" +
        ("NONE" if not missing_labels else ",".join(sorted(missing_labels)))
    )

    # We do not mutate anything. Audit only.
    unreal.log("ASWW_DUPLICATE_AUDIT=PASS")

if __name__ == "__main__":
    main()
'@

[IO.File]::WriteAllText($Py, $Python, [Text.UTF8Encoding]::new($false))

$ProjectForUE = $ProjectFile.Replace('\','/')
$PyForUE = $Py.Replace('\','/')

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " JEDDAH PROTOTYPE DUPLICATE AUDIT — READ ONLY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "AUDIT_LOG=$Log"

$Args = @(
    $ProjectForUE,
    "-ExecutePythonScript=$PyForUE",
    "-Unattended",
    "-NoSplash",
    "-NoSound",
    "-NullRHI",
    "-NoSourceControl",
    "-stdout",
    "-FullStdOutLogOutput"
)

& $EditorCmd @Args 2>&1 | Tee-Object -FilePath $Log | Out-Null
$Exit = $LASTEXITCODE

Write-Host "EDITOR_EXIT_CODE=$Exit"

Write-Host ""
Write-Host "=== DUPLICATE AUDIT SUMMARY ===" -ForegroundColor Yellow
Select-String -LiteralPath $Log `
    -Pattern "ASWW_AUDIT_COUNT=|ASWW_AUDIT_DUPLICATE_LABELS=|ASWW_AUDIT_MISSING_LABELS=|ASWW_DUPLICATE_AUDIT=" |
    Select-Object -First 120

Write-Host ""
Write-Host "=== DUPLICATE ACTOR DETAILS ===" -ForegroundColor Yellow
Select-String -LiteralPath $Log `
    -Pattern "ASWW_AUDIT_DESC=|ASWW_AUDIT_ACTOR=" |
    Select-Object -First 240

if ($Exit -ne 0) {
    Stop-Gate "EDITOR_AUDIT_EXIT_$Exit" $Exit
}

$Text = Get-Content -Raw -LiteralPath $Log
if ($Text -notmatch "ASWW_DUPLICATE_AUDIT=PASS") {
    Stop-Gate "AUDIT_PASS_MARKER_MISSING" 20
}

Write-Host ""
Write-Host "DUPLICATE_AUDIT=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=CLASSIFY_DUPLICATES_BEFORE_ANY_DELETE" -ForegroundColor Green
Write-Host "NO_MAP_CHANGES_WERE_MADE" -ForegroundColor Green
Write-Host "DO_NOT_PACKAGE_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
