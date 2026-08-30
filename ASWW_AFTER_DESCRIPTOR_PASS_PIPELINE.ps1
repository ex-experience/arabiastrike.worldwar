[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [switch]$LaunchEditorForManualQA
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Banner([string]$Text) {
    Write-Host ""
    Write-Host ("=" * 76) -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ("=" * 76) -ForegroundColor Cyan
}

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "POST_DESCRIPTOR_PIPELINE=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Save-Checkpoint([string]$Label) {
    $Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $Root = Join-Path $ProjectRoot "Saved\OfflineCheckpoint\${Label}_$Stamp"
    $FilesRoot = Join-Path $Root "files"
    New-Item -ItemType Directory -Force -Path $FilesRoot | Out-Null

    $Branch = (& git -C $ProjectRoot branch --show-current).Trim()
    $Head = (& git -C $ProjectRoot rev-parse HEAD).Trim()

    @(
        "LABEL=$Label"
        "TIME=$(Get-Date -Format o)"
        "BRANCH=$Branch"
        "HEAD=$Head"
        "PROJECT_ROOT=$ProjectRoot"
    ) | Set-Content -LiteralPath (Join-Path $Root "CHECKPOINT.txt") -Encoding UTF8

    & git -C $ProjectRoot status --porcelain=v1 | Set-Content -LiteralPath (Join-Path $Root "git_status.txt") -Encoding UTF8
    & git -c core.safecrlf=false -C $ProjectRoot diff --binary | Set-Content -LiteralPath (Join-Path $Root "working_tree.patch") -Encoding UTF8
    & git -c core.safecrlf=false -C $ProjectRoot diff --cached --binary | Set-Content -LiteralPath (Join-Path $Root "index.patch") -Encoding UTF8
    & git -C $ProjectRoot ls-files --others --exclude-standard | Set-Content -LiteralPath (Join-Path $Root "untracked.txt") -Encoding UTF8

    $Changed = @()
    $Changed += @(& git -c core.safecrlf=false -C $ProjectRoot diff --name-only)
    $Changed += @(& git -c core.safecrlf=false -C $ProjectRoot diff --cached --name-only)
    $Changed += @(& git -C $ProjectRoot ls-files --others --exclude-standard)
    $Changed = $Changed | Where-Object { $_ } | Sort-Object -Unique

    foreach ($Rel in $Changed) {
        $Src = Join-Path $ProjectRoot $Rel
        if (Test-Path -LiteralPath $Src -PathType Leaf) {
            $Dst = Join-Path $FilesRoot $Rel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dst) | Out-Null
            Copy-Item -LiteralPath $Src -Destination $Dst -Force
        }
    }

    Write-Host "CHECKPOINT=$Root" -ForegroundColor Green
    return $Root
}

Set-Location $ProjectRoot

Banner "ASWW — CONTINUE AFTER DESCRIPTOR VALIDATION PASS"

$Branch = (& git branch --show-current).Trim()
$Head = (& git rev-parse HEAD).Trim()
Write-Host "BRANCH=$Branch"
Write-Host "LOCAL_HEAD=$Head"

if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

$Project = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$Map = Join-Path $ProjectRoot "Content\Maps\Jeddah_RedSea_Assault.umap"
$Editor = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor.exe"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$RunUAT = Join-Path $UERoot "Engine\Build\BatchFiles\RunUAT.bat"
$BuildVersion = Join-Path $UERoot "Engine\Build\Build.version"

foreach ($Required in @($Project,$Map,$Editor,$EditorCmd,$RunUAT,$BuildVersion)) {
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

Banner "GATE 0 — VERIFY THE DESCRIPTOR PASS EVIDENCE"

$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\JeddahMap"
$DescLog = Get-ChildItem -LiteralPath $EvidenceRoot -File -Filter "validate_jeddah_actor_descriptors_*.log" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $DescLog) {
    Stop-Gate "DESCRIPTOR_VALIDATION_LOG_NOT_FOUND" 20
}

$DescText = Get-Content -Raw -LiteralPath $DescLog.FullName
$DescPass = $DescText -match "ASWW_DESCRIPTOR_VALIDATION=PASS"
$MissingNone = $DescText -match "ASWW_MISSING_DESCRIPTOR_ACTORS=NONE"
$WPPass = $DescText -match "ASWW_WORLD_PARTITION=PASS"
$MapPass = $DescText -match "ASWW_MAP_LOAD_RESULT=PASS"

Write-Host "DESCRIPTOR_LOG=$($DescLog.FullName)"
Write-Host "DESCRIPTOR_PASS=$DescPass"
Write-Host "MISSING_DESCRIPTOR_ACTORS_NONE=$MissingNone"
Write-Host "WORLD_PARTITION_PASS=$WPPass"
Write-Host "MAP_LOAD_PASS=$MapPass"

if (-not ($DescPass -and $MissingNone -and $WPPass -and $MapPass)) {
    Stop-Gate "DESCRIPTOR_PASS_EVIDENCE_INCOMPLETE" 21
}

Write-Host "JEDDAH_DESCRIPTOR_VALIDATION=PASS" -ForegroundColor Green

$BeforePatch = Save-Checkpoint "BEFORE_PERMANENT_VALIDATOR_PATCH"

Banner "GATE 1 — PATCH PERMANENT REPOSITORY VALIDATOR"

$ValidatorPy = Join-Path $ProjectRoot "Content\Python\asww_validate_jeddah_map.py"
$ValidatePS = Join-Path $ProjectRoot "BuildScripts\validate_jeddah_map.ps1"

foreach ($Required in @($ValidatorPy,$ValidatePS)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_$Required" 30
    }
}

$PatchBackup = Join-Path $ProjectRoot "Saved\Verification\FixBackups\ValidatorPatch_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Force -Path $PatchBackup | Out-Null
Copy-Item -LiteralPath $ValidatorPy -Destination (Join-Path $PatchBackup "asww_validate_jeddah_map.py") -Force
Copy-Item -LiteralPath $ValidatePS -Destination (Join-Path $PatchBackup "validate_jeddah_map.ps1") -Force
Write-Host "VALIDATOR_BACKUP=$PatchBackup" -ForegroundColor Green

$PermanentValidator = @'
"""Load and structurally validate the real Jeddah World Partition map inside Unreal Editor."""

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

    world_partition = world_settings.get_editor_property("world_partition")
    require(world_partition is not None, "Jeddah WorldSettings has no World Partition object")

    descs = list(unreal.WorldPartitionBlueprintLibrary.get_actor_descs())
    descriptor_labels = {str(desc.label) for desc in descs}
    missing_descriptor_labels = sorted(REQUIRED_LABELS - descriptor_labels)

    unreal.log(f"ASWW_ACTOR_DESCRIPTOR_COUNT={len(descs)}")
    unreal.log(
        "ASWW_MISSING_DESCRIPTOR_ACTORS=" +
        ("NONE" if not missing_descriptor_labels else ",".join(missing_descriptor_labels))
    )

    require(
        not missing_descriptor_labels,
        "Jeddah actor descriptors missing: " + ", ".join(missing_descriptor_labels),
    )

    # Explicitly load descriptor actors so type-based checks are deterministic.
    guids = [desc.guid for desc in descs]
    if guids:
        unreal.WorldPartitionBlueprintLibrary.load_actors(guids)

    actors = list(actor_subsystem.get_all_level_actors())

    player_starts = [actor for actor in actors if isinstance(actor, unreal.PlayerStart)]
    require(player_starts, "Jeddah map has no PlayerStart after explicit World Partition actor load")

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

[IO.File]::WriteAllText($ValidatorPy, $PermanentValidator, [Text.UTF8Encoding]::new($false))

# Patch only the ExecutePythonScript path handling in the PowerShell wrapper.
$PSContent = [IO.File]::ReadAllText($ValidatePS)

if ($PSContent -notmatch '\$ValidationScriptForUE') {
    $Anchor = '$RunId = Get-Date -Format "yyyyMMdd_HHmmss"'
    if (-not $PSContent.Contains($Anchor)) {
        Stop-Gate "VALIDATE_PS_PATCH_ANCHOR_NOT_FOUND" 31
    }
    $Replacement = @'
$ValidationScriptForUE = $ValidationScript.Replace('\','/')
$ProjectFileForUE = $ProjectFile.Replace('\','/')
$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
'@
    $PSContent = $PSContent.Replace($Anchor, $Replacement.TrimEnd())
}

$PSContent = $PSContent.Replace(
    '    $ProjectFile,',
    '    $ProjectFileForUE,'
)
$PSContent = $PSContent.Replace(
    '    "-ExecutePythonScript=$ValidationScript",',
    '    "-ExecutePythonScript=$ValidationScriptForUE",'
)

[IO.File]::WriteAllText($ValidatePS, $PSContent, [Text.UTF8Encoding]::new($false))

Write-Host "PERMANENT_VALIDATOR_PATCH=APPLIED" -ForegroundColor Green

Banner "GATE 2 — RUN THE PERMANENT VALIDATOR"

$ValidationCapture = Join-Path $ProjectRoot "Saved\Verification\Local\permanent_jeddah_validation_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ValidationCapture) | Out-Null

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ValidatePS -UERoot $UERoot 2>&1 |
    Tee-Object -FilePath $ValidationCapture

$ValidateExit = $LASTEXITCODE
Write-Host "PERMANENT_VALIDATOR_EXIT=$ValidateExit"

if ($ValidateExit -ne 0) {
    Stop-Gate "PERMANENT_VALIDATOR_FAIL_EXIT_$ValidateExit" $ValidateExit
}

$ValidationLine = Get-Content -LiteralPath $ValidationCapture |
    Where-Object { $_ -like "MAP_VALIDATION_LOG=*" } |
    Select-Object -Last 1

if (-not $ValidationLine) {
    Stop-Gate "MAP_VALIDATION_LOG_NOT_REPORTED" 32
}

$ValidationLog = $ValidationLine.Substring("MAP_VALIDATION_LOG=".Length)
Write-Host "MAP_VALIDATION_LOG=$ValidationLog" -ForegroundColor Green

$VText = Get-Content -Raw -LiteralPath $ValidationLog
if ($VText -notmatch "ASWW_MAP_LOAD_RESULT=PASS" -or $VText -notmatch "ASWW_WORLD_PARTITION=PASS") {
    Stop-Gate "PERMANENT_VALIDATOR_MISSING_SUCCESS_MARKERS" 33
}

Write-Host "PERMANENT_JEDDAH_VALIDATION=PASS" -ForegroundColor Green

Banner "GATE 3 — PROMOTE JEDDAH AS DEFAULT MAP"

$Promote = Join-Path $ProjectRoot "BuildScripts\promote_jeddah_default_map.ps1"
if (-not (Test-Path -LiteralPath $Promote -PathType Leaf)) {
    Stop-Gate "MISSING_promote_jeddah_default_map.ps1" 40
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Promote -ValidationLog $ValidationLog
$PromoteExit = $LASTEXITCODE

if ($PromoteExit -ne 0) {
    Stop-Gate "MAP_PROMOTION_FAIL_EXIT_$PromoteExit" $PromoteExit
}

Write-Host "MAP_PROMOTION=PASS" -ForegroundColor Green

$AfterPromotion = Save-Checkpoint "JEDDAH_VALIDATED_AND_PROMOTED"

Banner "GATE 4 — AUTOMATED PIE STARTUP SMOKE"

$Pie = Join-Path $ProjectRoot "BuildScripts\run_jeddah_pie_smoke.ps1"
if (-not (Test-Path -LiteralPath $Pie -PathType Leaf)) {
    Stop-Gate "MISSING_run_jeddah_pie_smoke.ps1" 50
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Pie -UERoot $UERoot -TimeoutSeconds 600
$PieExit = $LASTEXITCODE

if ($PieExit -ne 0) {
    Stop-Gate "PIE_STARTUP_SMOKE_FAIL_EXIT_$PieExit" $PieExit
}

Write-Host "PIE_STARTUP_SMOKE=PASS" -ForegroundColor Green
Write-Host "PIE_SCOPE=STARTUP_POSSESSION_ACTOR_PRESENCE_ONLY" -ForegroundColor Yellow
Write-Host "FULL_GAMEPLAY_MATRIX=NOT_PROVEN_BY_THIS_SMOKE" -ForegroundColor Yellow

Banner "GATE 5 — PACKAGE WIN64 DEVELOPMENT"

$Package = Join-Path $ProjectRoot "BuildScripts\build_win64.ps1"
if (-not (Test-Path -LiteralPath $Package -PathType Leaf)) {
    Stop-Gate "MISSING_build_win64.ps1" 60
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Package -UERoot $UERoot -Configuration Development
$PackageExit = $LASTEXITCODE

if ($PackageExit -ne 0) {
    Stop-Gate "WIN64_PACKAGE_FAIL_EXIT_$PackageExit" $PackageExit
}

$PackageRoot = Join-Path $ProjectRoot "BuildOutput\Client"
$Exe = Get-ChildItem -LiteralPath $PackageRoot -Recurse -File -Filter "ArabiaStrikeWorldWar.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch "\\Engine\\Binaries\\" } |
    Sort-Object FullName |
    Select-Object -First 1

if (-not $Exe) {
    Stop-Gate "PACKAGED_EXE_NOT_FOUND_AFTER_UAT_PASS" 61
}

Write-Host "WIN64_PACKAGE=PASS" -ForegroundColor Green
Write-Host "WIN64_EXE=$($Exe.FullName)"

Banner "GATE 6 — PACKAGED EXE STARTUP SMOKE"

$NativeEvidence = Join-Path $ProjectRoot "Saved\RuntimeEvidence\Native"
New-Item -ItemType Directory -Force -Path $NativeEvidence | Out-Null
$RuntimeLog = Join-Path $NativeEvidence "post_descriptor_packaged_startup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

$Proc = Start-Process -FilePath $Exe.FullName -ArgumentList @(
    "-windowed",
    "-ResX=1280",
    "-ResY=720",
    "-log",
    "-abslog=$RuntimeLog"
) -WorkingDirectory $Exe.DirectoryName -PassThru

Start-Sleep -Seconds 30

if ($Proc.HasExited) {
    $Proc.Refresh()
    Stop-Gate "PACKAGED_RUNTIME_EXITED_EARLY_CODE_$($Proc.ExitCode)" 62
}

Write-Host "WIN64_RUNTIME_PROCESS_START=PASS_30_SECONDS" -ForegroundColor Green
Write-Host "WIN64_RUNTIME_LOG=$RuntimeLog"
Stop-Process -Id $Proc.Id -Force -ErrorAction SilentlyContinue
$Proc.WaitForExit(5000) | Out-Null

$FinalCheckpoint = Save-Checkpoint "POST_DESCRIPTOR_AUTOMATED_PIPELINE_PASS"

Banner "AUTOMATED POST-DESCRIPTOR PIPELINE COMPLETE"

Write-Host "EDITOR_BUILD=PASS_FROM_PRIOR_CHECKPOINT" -ForegroundColor Green
Write-Host "GAME_BUILD=PASS_FROM_PRIOR_CHECKPOINT" -ForegroundColor Green
Write-Host "JEDDAH_DESCRIPTOR_VALIDATION=PASS" -ForegroundColor Green
Write-Host "PERMANENT_JEDDAH_VALIDATION=PASS" -ForegroundColor Green
Write-Host "MAP_PROMOTION=PASS" -ForegroundColor Green
Write-Host "PIE_STARTUP_SMOKE=PASS_STARTUP_ONLY" -ForegroundColor Green
Write-Host "WIN64_PACKAGE=PASS" -ForegroundColor Green
Write-Host "WIN64_RUNTIME_PROCESS_START=PASS_30_SECONDS" -ForegroundColor Green
Write-Host "SERVER_BUILD=BLOCKED_BY_EPIC_INSTALLED_ENGINE" -ForegroundColor Yellow
Write-Host "MULTIPLAYER_2P=NOT_PROVEN" -ForegroundColor Yellow
Write-Host "MULTIPLAYER_4P=NOT_PROVEN" -ForegroundColor Yellow
Write-Host "FULL_GAMEPLAY_QA=MANUAL_NOT_PROVEN" -ForegroundColor Yellow
Write-Host "FINAL_CHECKPOINT=$FinalCheckpoint" -ForegroundColor Green
Write-Host "NO_COMMIT_OR_PUSH_WAS_PERFORMED" -ForegroundColor Green

if ($LaunchEditorForManualQA) {
    Banner "OPTIONAL — LAUNCH JEDDAH IN UNREAL EDITOR"
    Start-Process -FilePath $Editor -ArgumentList @(
        $Project,
        "/Game/Maps/Jeddah_RedSea_Assault"
    ) -WorkingDirectory $ProjectRoot
    Write-Host "EDITOR_MANUAL_QA=LAUNCHED" -ForegroundColor Green
} else {
    Write-Host "NEXT_MANUAL_GATE=FULL_GAMEPLAY_QA" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
