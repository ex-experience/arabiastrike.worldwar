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
    Write-Host "CORRECTED_VALIDATION=STOPPED" -ForegroundColor Red
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

$Project = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$Map = Join-Path $ProjectRoot "Content\Maps\Jeddah_RedSea_Assault.umap"
$Editor = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"

foreach ($Required in @($Project,$Map,$Editor)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_$Required" 11
    }
}

$RunningEditors = @(Get-Process UnrealEditor,UnrealEditor-Cmd -ErrorAction SilentlyContinue)
if ($RunningEditors.Count -gt 0) {
    $RunningEditors | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ALL_UNREAL_EDITOR_PROCESSES_FIRST" 12
}

# Confirm current map is still a real Unreal package.
$Stream = [IO.File]::OpenRead($Map)
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

$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\JeddahMap"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Py = Join-Path $EvidenceRoot "validate_wp_corrected_$Stamp.py"
$Log = Join-Path $EvidenceRoot "validate_wp_corrected_$Stamp.log"

$Python = @'
import unreal

MAP_ASSET_PATH = "/Game/Maps/Jeddah_RedSea_Assault"

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def main():
    level_subsystem = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    actor_subsystem = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    editor_subsystem = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)

    require(level_subsystem is not None, "LevelEditorSubsystem is unavailable")
    require(actor_subsystem is not None, "EditorActorSubsystem is unavailable")
    require(editor_subsystem is not None, "UnrealEditorSubsystem is unavailable")
    require(unreal.EditorAssetLibrary.does_asset_exist(MAP_ASSET_PATH), "Jeddah map asset is missing")
    require(level_subsystem.load_level(MAP_ASSET_PATH), "Jeddah map failed to load")

    world = editor_subsystem.get_editor_world()
    require(world is not None, "Editor world is unavailable")

    world_settings = world.get_world_settings()
    require(world_settings is not None, "WorldSettings is unavailable")

    # UE exposes World Partition on WorldSettings. The prior validator queried World itself,
    # which can return None even for a partitioned map.
    world_partition = None
    try:
        world_partition = world_settings.get_editor_property("world_partition")
    except Exception as exc:
        unreal.log_warning(f"ASWW_WORLD_PARTITION_PROPERTY_EXCEPTION={exc}")

    require(world_partition is not None, "Jeddah WorldSettings has no World Partition object")
    unreal.log("ASWW_WORLD_PARTITION_OBJECT=FOUND_VIA_WORLD_SETTINGS")

    actors = list(actor_subsystem.get_all_level_actors())
    labels = {actor.get_actor_label() for actor in actors}
    required_labels = {
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
        "ASWW_Hummer_Test",
        "ASWW_Helicopter_Encounter",
        "ASWW_CommandMech_Encounter",
        "ASWW_Extraction_Prototype",
    }

    missing = sorted(required_labels - labels)
    unreal.log(f"ASWW_ACTOR_COUNT={len(actors)}")
    unreal.log("ASWW_MISSING_ACTORS=" + ("NONE" if not missing else ",".join(missing)))
    require(not missing, "Jeddah actors missing: " + ", ".join(missing))

    player_starts = [actor for actor in actors if isinstance(actor, unreal.PlayerStart)]
    require(player_starts, "Jeddah map has no PlayerStart")

    expected_game_mode = unreal.load_class(None, "/Script/ArabiaStrikeWorldWar.ASGameMode")
    require(expected_game_mode is not None, "ASGameMode failed to load")

    configured_game_mode = world_settings.get_editor_property("default_game_mode")
    require(configured_game_mode == expected_game_mode, "Jeddah map does not override ASGameMode")

    unreal.log(f"ASWW_MAP_ASSET={MAP_ASSET_PATH}")
    unreal.log("ASWW_WORLD_PARTITION=PASS")
    unreal.log("ASWW_MAP_LOAD_RESULT=PASS")

if __name__ == "__main__":
    main()
'@

[IO.File]::WriteAllText($Py, $Python, [Text.UTF8Encoding]::new($false))
Write-Host "TEMP_VALIDATOR=$Py" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CORRECTED REAL JEDDAH VALIDATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Args = @(
    $Project,
    "-ExecutePythonScript=$Py",
    "-Unattended",
    "-NoSplash",
    "-NoSound",
    "-NullRHI",
    "-NoSourceControl",
    "-stdout",
    "-FullStdOutLogOutput"
)

& $Editor @Args 2>&1 | Tee-Object -FilePath $Log
$Exit = $LASTEXITCODE

$WPObject = Select-String -LiteralPath $Log -SimpleMatch "ASWW_WORLD_PARTITION_OBJECT=FOUND_VIA_WORLD_SETTINGS" -Quiet
$WP = Select-String -LiteralPath $Log -SimpleMatch "ASWW_WORLD_PARTITION=PASS" -Quiet
$MapPass = Select-String -LiteralPath $Log -SimpleMatch "ASWW_MAP_LOAD_RESULT=PASS" -Quiet
$MissingLine = Select-String -LiteralPath $Log -SimpleMatch "ASWW_MISSING_ACTORS=" | Select-Object -Last 1

Write-Host ""
Write-Host "EDITOR_EXIT=$Exit"
Write-Host "WORLD_PARTITION_OBJECT_FOUND=$WPObject"
Write-Host "WORLD_PARTITION_MARKER=$WP"
Write-Host "MAP_LOAD_MARKER=$MapPass"
if ($MissingLine) { Write-Host $MissingLine.Line }
Write-Host "VALIDATION_LOG=$Log"

if ($Exit -eq 0 -and $WP -and $MapPass) {
    Write-Host ""
    Write-Host "JEDDAH_VALIDATION=PASS_CORRECTED" -ForegroundColor Green
    Write-Host "CONVERSION_REQUIRED=NO" -ForegroundColor Green
    Write-Host "NEXT_GATE=PATCH_REPO_VALIDATOR_THEN_PROMOTE_DEFAULT_MAP" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "=== CORRECTED VALIDATION ROOT CAUSE ===" -ForegroundColor Yellow
Select-String -LiteralPath $Log `
    -Pattern "LogPython:\s*Error|Traceback|RuntimeError:|AttributeError:|TypeError:|ASWW_MISSING_ACTORS=|PlayerStart|ASGameMode|World Partition|failed to load" `
    -Context 4,12 |
    Select-Object -First 60

Write-Host ""
Write-Host "CONVERSION_REQUIRED=NO_ALREADY_PARTITIONED" -ForegroundColor Yellow
Write-Host "NEXT_ACTION=FIX_ONLY_THE_REPORTED_VALIDATION_CONTENT_ISSUE" -ForegroundColor Yellow
Write-Host "DO_NOT_REGENERATE_OR_DELETE_UMAP" -ForegroundColor Yellow
exit 30
