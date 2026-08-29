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
    Write-Host "PIE_ENEMY_DIAGNOSTIC=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_MAP_CHANGES_WERE_MADE" -ForegroundColor Green
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
$TestFile = Join-Path $ProjectRoot "Content\Python\test_asww_jeddah_pie.py"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\PIE"

foreach ($Required in @($ProjectFile,$MapFile,$TestFile,$EditorCmd)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_$Required" 11
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CURRENT PIE TEST — ENEMY ASSERTION CONTEXT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Lines = Get-Content -LiteralPath $TestFile
for ($i=0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match "enemy_count|Enemy|PIE did not load the prototype enemy encounter|ASWW_PIE_SMOKE") {
        $Start = [Math]::Max(0, $i - 8)
        $End = [Math]::Min($Lines.Count - 1, $i + 12)
        for ($j=$Start; $j -le $End; $j++) {
            "{0,4}: {1}" -f ($j + 1), $Lines[$j]
        }
        Write-Host "----"
    }
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Py = Join-Path $EvidenceRoot "inspect_jeddah_enemy_descriptors_$Stamp.py"
$Log = Join-Path $EvidenceRoot "inspect_jeddah_enemy_descriptors_$Stamp.log"

$Python = @'
import unreal

MAP = "/Game/Maps/Jeddah_RedSea_Assault"

def safe_attr(obj, name):
    try:
        value = getattr(obj, name)
        return value() if callable(value) else value
    except Exception:
        return "<unavailable>"

def main():
    level_subsystem = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    editor_subsystem = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
    actor_subsystem = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

    if not level_subsystem.load_level(MAP):
        raise RuntimeError("Failed to load Jeddah map")

    world = editor_subsystem.get_editor_world()
    if world is None:
        raise RuntimeError("Editor world unavailable")

    descs = list(unreal.WorldPartitionBlueprintLibrary.get_actor_descs())
    unreal.log(f"ASWW_DESC_TOTAL={len(descs)}")

    enemy_descs = []
    key_descs = []

    for desc in descs:
        label = str(safe_attr(desc, "label"))
        actor_path = str(safe_attr(desc, "actor_path"))
        actor_package = str(safe_attr(desc, "actor_package"))
        guid = safe_attr(desc, "guid")
        spatial = safe_attr(desc, "is_spatially_loaded")
        runtime_grid = safe_attr(desc, "runtime_grid")

        if "ASWW_Enemy_" in label:
            enemy_descs.append(desc)
            unreal.log(
                "ASWW_ENEMY_DESC="
                f"label={label}|guid={guid}|spatial={spatial}|runtime_grid={runtime_grid}|"
                f"actor_path={actor_path}|package={actor_package}"
            )

        if label in (
            "ASWW_PlayerStart_Primary",
            "ASWW_MissionDirector",
            "ASWW_WorldBootstrap",
            "ASWW_Hummer_Test",
            "ASWW_Helicopter_Encounter",
            "ASWW_CommandMech_Encounter",
            "ASWW_Extraction_Prototype",
        ):
            key_descs.append(desc)
            unreal.log(
                "ASWW_KEY_DESC="
                f"label={label}|guid={guid}|spatial={spatial}|runtime_grid={runtime_grid}|"
                f"actor_path={actor_path}|package={actor_package}"
            )

    unreal.log(f"ASWW_ENEMY_DESCRIPTOR_COUNT={len(enemy_descs)}")

    # Explicitly load descriptor actors in editor world only so we can inspect class/location.
    guids = [d.guid for d in enemy_descs + key_descs]
    if guids:
        unreal.WorldPartitionBlueprintLibrary.load_actors(guids)

    actors = list(actor_subsystem.get_all_level_actors())

    for actor in actors:
        label = actor.get_actor_label()
        if "ASWW_Enemy_" in label or label in (
            "ASWW_PlayerStart_Primary",
            "ASWW_MissionDirector",
            "ASWW_WorldBootstrap",
            "ASWW_Hummer_Test",
            "ASWW_Helicopter_Encounter",
            "ASWW_CommandMech_Encounter",
            "ASWW_Extraction_Prototype",
        ):
            loc = actor.get_actor_location()
            cls = actor.get_class().get_name()
            spatial_value = "<unavailable>"
            try:
                spatial_value = actor.get_editor_property("is_spatially_loaded")
            except Exception:
                pass
            unreal.log(
                "ASWW_LOADED_EDITOR_ACTOR="
                f"label={label}|class={cls}|location=({loc.x:.1f},{loc.y:.1f},{loc.z:.1f})|"
                f"is_spatially_loaded={spatial_value}"
            )

    unreal.log("ASWW_ENEMY_DESCRIPTOR_DIAGNOSTIC=PASS")

if __name__ == "__main__":
    main()
'@

[IO.File]::WriteAllText($Py, $Python, [Text.UTF8Encoding]::new($false))

$ProjectForUE = $ProjectFile.Replace('\','/')
$PyForUE = $Py.Replace('\','/')

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " READ-ONLY WORLD PARTITION ENEMY DESCRIPTOR INSPECTION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "DIAGNOSTIC_LOG=$Log"

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
Write-Host "=== ENEMY DESCRIPTOR EVIDENCE ===" -ForegroundColor Yellow
Select-String -LiteralPath $Log `
    -Pattern "ASWW_ENEMY_DESCRIPTOR_COUNT=|ASWW_ENEMY_DESC=|ASWW_KEY_DESC=|ASWW_LOADED_EDITOR_ACTOR=|ASWW_ENEMY_DESCRIPTOR_DIAGNOSTIC=|LogPython:\s*Error|Traceback|RuntimeError:" `
    -Context 0,2 |
    Select-Object -First 160

if ($Exit -ne 0) {
    Stop-Gate "EDITOR_DIAGNOSTIC_EXIT_$Exit" $Exit
}

$Text = Get-Content -Raw -LiteralPath $Log
if ($Text -notmatch "ASWW_ENEMY_DESCRIPTOR_DIAGNOSTIC=PASS") {
    Stop-Gate "DIAGNOSTIC_SUCCESS_MARKER_MISSING" 20
}

Write-Host ""
Write-Host "PIE_ENEMY_DIAGNOSTIC=PASS" -ForegroundColor Green
Write-Host "NEXT=CLASSIFY_MISSING_ENEMIES_AS_STREAMING_CONFIGURATION_OR_CLASS_FILTER_ISSUE" -ForegroundColor Cyan
Write-Host "NO_MAP_CHANGES_WERE_MADE" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
