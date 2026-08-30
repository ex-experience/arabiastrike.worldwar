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
    Write-Host "SMART_REPAIR=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_DELETE_OR_REGENERATE_UMAP" -ForegroundColor Yellow
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
$BuildVersion = Join-Path $UERoot "Engine\Build\Build.version"

foreach ($Required in @($Project,$Map,$Editor,$BuildVersion)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_$Required" 11
    }
}

$V = Get-Content -Raw -LiteralPath $BuildVersion | ConvertFrom-Json
$UEVersion = "$($V.MajorVersion).$($V.MinorVersion).$($V.PatchVersion)"
Write-Host "UE_VERSION=$UEVersion"
if ($V.MajorVersion -ne 5 -or $V.MinorVersion -ne 8) {
    Stop-Gate "UE_5_8_REQUIRED_FOUND_$UEVersion" 12
}

$RunningEditors = @(Get-Process UnrealEditor,UnrealEditor-Cmd -ErrorAction SilentlyContinue)
if ($RunningEditors.Count -gt 0) {
    $RunningEditors | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ALL_UNREAL_EDITOR_PROCESSES_FIRST" 13
}

# Validate binary package header before any mutation.
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
    Stop-Gate "INVALID_UNREAL_PACKAGE_HEADER" 14
}
Write-Host "REAL_UNREAL_PACKAGE_HEADER=True" -ForegroundColor Green

$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\JeddahMap"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

# Inspect the latest corrected validation log first. Do not modify the map unless the
# failure is one of the explicitly supported content-invariant cases.
$LatestCorrected = Get-ChildItem -LiteralPath $EvidenceRoot -File -Filter "validate_wp_corrected_*.log" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $LatestCorrected) {
    Stop-Gate "NO_CORRECTED_VALIDATION_LOG_FOUND" 20
}

Write-Host ""
Write-Host "LATEST_CORRECTED_LOG=$($LatestCorrected.FullName)" -ForegroundColor Cyan

$RootCauseLines = @(
    Select-String -LiteralPath $LatestCorrected.FullName `
        -Pattern "ASWW_MISSING_ACTORS=|RuntimeError:|PlayerStart|ASGameMode|Jeddah actors missing" `
        -Context 2,5 `
        -ErrorAction SilentlyContinue
)

Write-Host ""
Write-Host "=== LAST CORRECTED VALIDATION ROOT CAUSE ===" -ForegroundColor Yellow
if ($RootCauseLines.Count -gt 0) {
    $RootCauseLines | Select-Object -First 40
} else {
    Write-Host "NO_SUPPORTED_CONTENT_ROOT_CAUSE_FOUND" -ForegroundColor Red
}

$LogText = Get-Content -Raw -LiteralPath $LatestCorrected.FullName
$SupportedIssue =
    ($LogText -match "ASWW_MISSING_ACTORS=(?!NONE)") -or
    ($LogText -match "Jeddah actors missing:") -or
    ($LogText -match "Jeddah map has no PlayerStart") -or
    ($LogText -match "Jeddah map does not override ASGameMode")

if (-not $SupportedIssue) {
    Stop-Gate "CORRECTED_VALIDATION_FAILED_FOR_UNSUPPORTED_REASON_REVIEW_LOG_ABOVE" 21
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\FixBackups\Jeddah_ContentRepair_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

Copy-Item -LiteralPath $Map -Destination (Join-Path $BackupRoot "Jeddah_RedSea_Assault.umap") -Force

$ExternalPaths = @(
    (Join-Path $ProjectRoot "Content\__ExternalActors__\Maps\Jeddah_RedSea_Assault"),
    (Join-Path $ProjectRoot "Content\__ExternalObjects__\Maps\Jeddah_RedSea_Assault")
)
foreach ($Path in $ExternalPaths) {
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $Parent = Split-Path (Split-Path $Path -Parent) -Leaf
        $Leaf = Split-Path $Path -Leaf
        $Dest = Join-Path $BackupRoot "$Parent\$Leaf"
        New-Item -ItemType Directory -Force -Path (Split-Path $Dest -Parent) | Out-Null
        Copy-Item -LiteralPath $Path -Destination $Dest -Recurse -Force
    }
}
Write-Host "BACKUP=$BackupRoot" -ForegroundColor Green

$RepairPy = Join-Path $EvidenceRoot "repair_jeddah_content_$Stamp.py"
$RepairLog = Join-Path $EvidenceRoot "repair_jeddah_content_$Stamp.log"
$ValidatePy = Join-Path $EvidenceRoot "validate_jeddah_after_content_repair_$Stamp.py"
$ValidateLog = Join-Path $EvidenceRoot "validate_jeddah_after_content_repair_$Stamp.log"

$RepairPython = @'
import unreal

MAP_ASSET_PATH = "/Game/Maps/Jeddah_RedSea_Assault"
PROJECT_MODULE = "/Script/ArabiaStrikeWorldWar."

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def load_project_class(name):
    cls = unreal.load_class(None, PROJECT_MODULE + name)
    require(cls is not None, f"Project class failed to load: {name}")
    return cls

def spawn_actor(actor_subsystem, actor_class, label, location, rotation=None, scale=None):
    actor = actor_subsystem.spawn_actor_from_class(
        actor_class,
        location,
        rotation or unreal.Rotator(0.0, 0.0, 0.0),
        False,
    )
    require(actor is not None, f"Failed to spawn actor: {label}")
    actor.set_actor_label(label)
    if scale is not None:
        actor.set_actor_scale3d(scale)
    unreal.log(f"ASWW_REPAIR_ADDED={label}")
    return actor

def spawn_cube(actor_subsystem, cube_mesh, label, location, scale):
    actor = spawn_actor(actor_subsystem, unreal.StaticMeshActor, label, location, scale=scale)
    comp = actor.get_editor_property("static_mesh_component")
    require(comp is not None, f"Static mesh component missing: {label}")
    comp.set_editor_property("static_mesh", cube_mesh)
    return actor

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

    wp = world_settings.get_editor_property("world_partition")
    require(wp is not None, "Jeddah WorldSettings has no World Partition object")

    actors = list(actor_subsystem.get_all_level_actors())
    by_label = {a.get_actor_label(): a for a in actors}

    cube_mesh = unreal.load_asset("/Engine/BasicShapes/Cube.Cube")
    require(cube_mesh is not None, "Engine basic cube mesh is unavailable")

    def missing(label):
        return label not in by_label

    if missing("ASWW_Ground"):
        by_label["ASWW_Ground"] = spawn_cube(
            actor_subsystem, cube_mesh, "ASWW_Ground",
            unreal.Vector(0.0, 0.0, -100.0),
            unreal.Vector(100.0, 100.0, 1.0)
        )

    if missing("ASWW_SpawnApron"):
        by_label["ASWW_SpawnApron"] = spawn_cube(
            actor_subsystem, cube_mesh, "ASWW_SpawnApron",
            unreal.Vector(-3500.0, 0.0, 0.0),
            unreal.Vector(16.0, 16.0, 1.0)
        )

    if missing("ASWW_PlayerStart_Primary"):
        by_label["ASWW_PlayerStart_Primary"] = spawn_actor(
            actor_subsystem, unreal.PlayerStart, "ASWW_PlayerStart_Primary",
            unreal.Vector(-3500.0, 0.0, 220.0)
        )

    if missing("ASWW_Sun"):
        by_label["ASWW_Sun"] = spawn_actor(
            actor_subsystem, unreal.DirectionalLight, "ASWW_Sun",
            unreal.Vector(0.0, 0.0, 2000.0),
            unreal.Rotator(-45.0, -35.0, 0.0)
        )

    if missing("ASWW_SkyLight"):
        by_label["ASWW_SkyLight"] = spawn_actor(
            actor_subsystem, unreal.SkyLight, "ASWW_SkyLight",
            unreal.Vector(0.0, 0.0, 1000.0)
        )

    if missing("ASWW_SkyAtmosphere"):
        by_label["ASWW_SkyAtmosphere"] = spawn_actor(
            actor_subsystem, unreal.SkyAtmosphere, "ASWW_SkyAtmosphere",
            unreal.Vector(0.0, 0.0, 0.0)
        )

    if missing("ASWW_HeightFog"):
        by_label["ASWW_HeightFog"] = spawn_actor(
            actor_subsystem, unreal.ExponentialHeightFog, "ASWW_HeightFog",
            unreal.Vector(0.0, 0.0, 0.0)
        )

    if missing("ASWW_NavMeshBounds"):
        by_label["ASWW_NavMeshBounds"] = spawn_actor(
            actor_subsystem, unreal.NavMeshBoundsVolume, "ASWW_NavMeshBounds",
            unreal.Vector(0.0, 0.0, 400.0),
            scale=unreal.Vector(80.0, 80.0, 10.0)
        )

    if missing("ASWW_MissionDirector"):
        by_label["ASWW_MissionDirector"] = spawn_actor(
            actor_subsystem, load_project_class("ASMissionDirector"), "ASWW_MissionDirector",
            unreal.Vector(0.0, 0.0, 100.0)
        )

    if missing("ASWW_WorldBootstrap"):
        by_label["ASWW_WorldBootstrap"] = spawn_actor(
            actor_subsystem, load_project_class("ASWorldBootstrap"), "ASWW_WorldBootstrap",
            unreal.Vector(0.0, 0.0, 150.0)
        )

    if missing("ASWW_Enemy_01"):
        by_label["ASWW_Enemy_01"] = spawn_actor(
            actor_subsystem, load_project_class("ASSoldierCharacter"), "ASWW_Enemy_01",
            unreal.Vector(500.0, -600.0, 120.0)
        )

    if missing("ASWW_Hummer_Test"):
        by_label["ASWW_Hummer_Test"] = spawn_actor(
            actor_subsystem, load_project_class("ASChaosHummerPawn"), "ASWW_Hummer_Test",
            unreal.Vector(-1000.0, 2200.0, 150.0)
        )

    if missing("ASWW_Helicopter_Encounter"):
        by_label["ASWW_Helicopter_Encounter"] = spawn_actor(
            actor_subsystem, load_project_class("ASHelicopterPawn"), "ASWW_Helicopter_Encounter",
            unreal.Vector(3000.0, 0.0, 1800.0)
        )

    if missing("ASWW_CommandMech_Encounter"):
        by_label["ASWW_CommandMech_Encounter"] = spawn_actor(
            actor_subsystem, load_project_class("ASBossCharacter"), "ASWW_CommandMech_Encounter",
            unreal.Vector(3800.0, 0.0, 180.0)
        )

    if missing("ASWW_Extraction_Prototype"):
        by_label["ASWW_Extraction_Prototype"] = spawn_actor(
            actor_subsystem, load_project_class("ASObjectiveVolume"), "ASWW_Extraction_Prototype",
            unreal.Vector(0.0, 3800.0, 200.0),
            scale=unreal.Vector(3.0, 3.0, 2.0)
        )

    # Ensure at least one PlayerStart exists even if a differently labeled one was present.
    actors = list(actor_subsystem.get_all_level_actors())
    player_starts = [a for a in actors if isinstance(a, unreal.PlayerStart)]
    if not player_starts:
        spawn_actor(
            actor_subsystem, unreal.PlayerStart, "ASWW_PlayerStart_Primary",
            unreal.Vector(-3500.0, 0.0, 220.0)
        )

    game_mode = load_project_class("ASGameMode")
    configured = world_settings.get_editor_property("default_game_mode")
    if configured != game_mode:
        world_settings.set_editor_property("default_game_mode", game_mode)
        unreal.log("ASWW_REPAIR_SET_GAMEMODE=ASGameMode")

    # Re-bind extraction director only when both actors exist.
    actors = list(actor_subsystem.get_all_level_actors())
    by_label = {a.get_actor_label(): a for a in actors}
    extraction = by_label.get("ASWW_Extraction_Prototype")
    director = by_label.get("ASWW_MissionDirector")
    if extraction is not None and director is not None:
        try:
            extraction.set_editor_property("director", director)
            unreal.log("ASWW_REPAIR_BOUND_EXTRACTION_DIRECTOR=YES")
        except Exception as exc:
            unreal.log_warning(f"ASWW_REPAIR_BOUND_EXTRACTION_DIRECTOR=DEFERRED:{exc}")

    require(level_subsystem.save_current_level(), "Failed to save repaired Jeddah level")

    # Save external actor/object packages created or changed by a World Partition map.
    try:
        unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True, True)
    except Exception as exc:
        unreal.log_warning(f"ASWW_SAVE_DIRTY_PACKAGES_WARNING={exc}")

    unreal.log("ASWW_CONTENT_REPAIR_RESULT=PASS")

if __name__ == "__main__":
    main()
'@

$ValidatePython = @'
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

    wp = world_settings.get_editor_property("world_partition")
    require(wp is not None, "Jeddah WorldSettings has no World Partition object")

    actors = list(actor_subsystem.get_all_level_actors())
    labels = {a.get_actor_label() for a in actors}

    required = {
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

    missing = sorted(required - labels)
    unreal.log(f"ASWW_ACTOR_COUNT={len(actors)}")
    unreal.log("ASWW_MISSING_ACTORS=" + ("NONE" if not missing else ",".join(missing)))
    require(not missing, "Jeddah actors missing: " + ", ".join(missing))

    player_starts = [a for a in actors if isinstance(a, unreal.PlayerStart)]
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

[IO.File]::WriteAllText($RepairPy, $RepairPython, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($ValidatePy, $ValidatePython, [Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SMART JEDDAH CONTENT REPAIR — ONLY MISSING INVARIANTS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

& $Editor @(
    $Project,
    "-ExecutePythonScript=$RepairPy",
    "-Unattended",
    "-NoSplash",
    "-NoSound",
    "-NullRHI",
    "-NoSourceControl",
    "-stdout",
    "-FullStdOutLogOutput"
) 2>&1 | Tee-Object -FilePath $RepairLog

$RepairExit = $LASTEXITCODE
$RepairPass = Select-String -LiteralPath $RepairLog -SimpleMatch "ASWW_CONTENT_REPAIR_RESULT=PASS" -Quiet

Write-Host ""
Write-Host "REPAIR_EXIT=$RepairExit"
Write-Host "REPAIR_MARKER=$RepairPass"
Write-Host "REPAIR_LOG=$RepairLog"

if ($RepairExit -ne 0 -or -not $RepairPass) {
    Write-Host ""
    Write-Host "=== REPAIR ROOT CAUSE ===" -ForegroundColor Yellow
    Select-String -LiteralPath $RepairLog `
        -Pattern "LogPython:\s*Error|Traceback|RuntimeError:|AttributeError:|TypeError:|Failed to spawn|Failed to save|Project class failed to load" `
        -Context 4,12 |
        Select-Object -First 60
    Stop-Gate "CONTENT_REPAIR_FAILED" 30
}

Write-Host "CONTENT_REPAIR=PASS" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FRESH DISK-RELOAD VALIDATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

& $Editor @(
    $Project,
    "-ExecutePythonScript=$ValidatePy",
    "-Unattended",
    "-NoSplash",
    "-NoSound",
    "-NullRHI",
    "-NoSourceControl",
    "-stdout",
    "-FullStdOutLogOutput"
) 2>&1 | Tee-Object -FilePath $ValidateLog

$ValidateExit = $LASTEXITCODE
$WP = Select-String -LiteralPath $ValidateLog -SimpleMatch "ASWW_WORLD_PARTITION=PASS" -Quiet
$MapPass = Select-String -LiteralPath $ValidateLog -SimpleMatch "ASWW_MAP_LOAD_RESULT=PASS" -Quiet
$Missing = Select-String -LiteralPath $ValidateLog -SimpleMatch "ASWW_MISSING_ACTORS=" | Select-Object -Last 1

Write-Host ""
Write-Host "VALIDATION_EXIT=$ValidateExit"
Write-Host "WORLD_PARTITION_MARKER=$WP"
Write-Host "MAP_LOAD_MARKER=$MapPass"
if ($Missing) { Write-Host $Missing.Line }
Write-Host "VALIDATION_LOG=$ValidateLog"

if ($ValidateExit -eq 0 -and $WP -and $MapPass) {
    Write-Host ""
    Write-Host "JEDDAH_CONTENT_VALIDATION=PASS" -ForegroundColor Green
    Write-Host "NEXT_GATE=PATCH_REPO_VALIDATOR_AND_PROMOTE_DEFAULT_MAP" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "=== FRESH VALIDATION ROOT CAUSE ===" -ForegroundColor Yellow
Select-String -LiteralPath $ValidateLog `
    -Pattern "LogPython:\s*Error|Traceback|RuntimeError:|AttributeError:|TypeError:|ASWW_MISSING_ACTORS=|PlayerStart|ASGameMode|World Partition|failed to load" `
    -Context 4,12 |
    Select-Object -First 60

Stop-Gate "FRESH_VALIDATION_FAILED_AFTER_TARGETED_REPAIR" 40
