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
    Write-Host "DESCRIPTOR_VALIDATION=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_REPAIR_OR_REGENERATE_MAP_YET" -ForegroundColor Yellow
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

# Confirm real Unreal package header.
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
$Py = Join-Path $EvidenceRoot "validate_jeddah_actor_descriptors_$Stamp.py"
$Log = Join-Path $EvidenceRoot "validate_jeddah_actor_descriptors_$Stamp.log"

$Python = @'
import unreal

MAP_ASSET_PATH = "/Game/Maps/Jeddah_RedSea_Assault"

REQUIRED_LABELS = {
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

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def main():
    level_subsystem = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    editor_subsystem = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
    actor_subsystem = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

    require(level_subsystem is not None, "LevelEditorSubsystem is unavailable")
    require(editor_subsystem is not None, "UnrealEditorSubsystem is unavailable")
    require(actor_subsystem is not None, "EditorActorSubsystem is unavailable")

    require(unreal.EditorAssetLibrary.does_asset_exist(MAP_ASSET_PATH), "Jeddah map asset is missing")
    require(level_subsystem.load_level(MAP_ASSET_PATH), "Jeddah map failed to load")

    world = editor_subsystem.get_editor_world()
    require(world is not None, "Editor world is unavailable")

    world_settings = world.get_world_settings()
    require(world_settings is not None, "WorldSettings is unavailable")

    wp = world_settings.get_editor_property("world_partition")
    require(wp is not None, "Jeddah WorldSettings has no World Partition object")
    unreal.log("ASWW_WORLD_PARTITION_OBJECT=FOUND")

    # CRITICAL: get_all_level_actors() returns only loaded actors in a WP editor world.
    loaded_actors_before = list(actor_subsystem.get_all_level_actors())
    unreal.log(f"ASWW_LOADED_ACTOR_COUNT_BEFORE={len(loaded_actors_before)}")

    descs = unreal.WorldPartitionBlueprintLibrary.get_actor_descs()
    require(descs is not None, "WorldPartitionBlueprintLibrary.get_actor_descs returned None")
    descs = list(descs)

    descriptor_labels = {str(desc.label) for desc in descs}
    unreal.log(f"ASWW_ACTOR_DESCRIPTOR_COUNT={len(descs)}")
    unreal.log("ASWW_DESCRIPTOR_LABELS=" + ",".join(sorted(descriptor_labels)))

    missing_descriptor_labels = sorted(REQUIRED_LABELS - descriptor_labels)
    unreal.log(
        "ASWW_MISSING_DESCRIPTOR_ACTORS=" +
        ("NONE" if not missing_descriptor_labels else ",".join(missing_descriptor_labels))
    )

    # If descriptors exist, explicitly load all descriptor actors so loaded-actor checks
    # are meaningful rather than depending on the editor's initial WP streaming state.
    guids = [desc.guid for desc in descs]
    if guids:
        unreal.WorldPartitionBlueprintLibrary.load_actors(guids)

    loaded_actors_after = list(actor_subsystem.get_all_level_actors())
    loaded_labels_after = {actor.get_actor_label() for actor in loaded_actors_after}
    unreal.log(f"ASWW_LOADED_ACTOR_COUNT_AFTER={len(loaded_actors_after)}")
    unreal.log("ASWW_LOADED_LABELS_AFTER=" + ",".join(sorted(loaded_labels_after)))

    missing_loaded_after = sorted(REQUIRED_LABELS - loaded_labels_after)
    unreal.log(
        "ASWW_MISSING_LOADED_AFTER_EXPLICIT_LOAD=" +
        ("NONE" if not missing_loaded_after else ",".join(missing_loaded_after))
    )

    # Descriptor presence is the authoritative on-disk existence check for World Partition.
    require(
        not missing_descriptor_labels,
        "Jeddah actor descriptors missing: " + ", ".join(missing_descriptor_labels),
    )

    # Validate PlayerStart from the loaded set after descriptor loading.
    player_starts = [actor for actor in loaded_actors_after if isinstance(actor, unreal.PlayerStart)]
    require(player_starts, "Jeddah map has no loaded PlayerStart after explicit WP actor load")

    expected_game_mode = unreal.load_class(None, "/Script/ArabiaStrikeWorldWar.ASGameMode")
    require(expected_game_mode is not None, "ASGameMode failed to load")
    configured_game_mode = world_settings.get_editor_property("default_game_mode")
    require(configured_game_mode == expected_game_mode, "Jeddah map does not override ASGameMode")

    unreal.log(f"ASWW_MAP_ASSET={MAP_ASSET_PATH}")
    unreal.log("ASWW_WORLD_PARTITION=PASS")
    unreal.log("ASWW_MAP_LOAD_RESULT=PASS")
    unreal.log("ASWW_DESCRIPTOR_VALIDATION=PASS")

if __name__ == "__main__":
    main()
'@

[IO.File]::WriteAllText($Py, $Python, [Text.UTF8Encoding]::new($false))

# Use forward slashes for Unreal's Python command-line path.
$ProjectForUE = $Project.Replace('\','/')
$PyForUE = $Py.Replace('\','/')

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " JEDDAH WORLD PARTITION — DESCRIPTOR-BASED VALIDATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEMP_VALIDATOR=$Py"
Write-Host "VALIDATION_LOG=$Log"

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

& $Editor @Args 2>&1 | Tee-Object -FilePath $Log
$Exit = $LASTEXITCODE

$DescCountLine = Select-String -LiteralPath $Log -SimpleMatch "ASWW_ACTOR_DESCRIPTOR_COUNT=" | Select-Object -Last 1
$MissingDescLine = Select-String -LiteralPath $Log -SimpleMatch "ASWW_MISSING_DESCRIPTOR_ACTORS=" | Select-Object -Last 1
$LoadedBeforeLine = Select-String -LiteralPath $Log -SimpleMatch "ASWW_LOADED_ACTOR_COUNT_BEFORE=" | Select-Object -Last 1
$LoadedAfterLine = Select-String -LiteralPath $Log -SimpleMatch "ASWW_LOADED_ACTOR_COUNT_AFTER=" | Select-Object -Last 1
$MissingLoadedLine = Select-String -LiteralPath $Log -SimpleMatch "ASWW_MISSING_LOADED_AFTER_EXPLICIT_LOAD=" | Select-Object -Last 1
$Pass = Select-String -LiteralPath $Log -SimpleMatch "ASWW_DESCRIPTOR_VALIDATION=PASS" -Quiet

Write-Host ""
Write-Host "EDITOR_EXIT=$Exit"
if ($LoadedBeforeLine) { Write-Host $LoadedBeforeLine.Line }
if ($DescCountLine) { Write-Host $DescCountLine.Line }
if ($MissingDescLine) { Write-Host $MissingDescLine.Line }
if ($LoadedAfterLine) { Write-Host $LoadedAfterLine.Line }
if ($MissingLoadedLine) { Write-Host $MissingLoadedLine.Line }
Write-Host "DESCRIPTOR_PASS_MARKER=$Pass"

if ($Exit -eq 0 -and $Pass) {
    Write-Host ""
    Write-Host "JEDDAH_DESCRIPTOR_VALIDATION=PASS" -ForegroundColor Green
    Write-Host "MAP_CONTENT_EXISTS_ON_DISK=PASS" -ForegroundColor Green
    Write-Host "NEXT_GATE=PATCH_REPO_VALIDATOR_THEN_PROMOTE_DEFAULT_MAP" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "=== DESCRIPTOR VALIDATION ROOT CAUSE ===" -ForegroundColor Yellow
Select-String -LiteralPath $Log `
    -Pattern "ASWW_MISSING_DESCRIPTOR_ACTORS=|ASWW_MISSING_LOADED_AFTER_EXPLICIT_LOAD=|RuntimeError:|Traceback|LogPython:\s*Error|AttributeError:|TypeError:|PlayerStart|ASGameMode|World Partition" `
    -Context 4,14 |
    Select-Object -First 80

Stop-Gate "DESCRIPTOR_VALIDATION_FAILED" 30
