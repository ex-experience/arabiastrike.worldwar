[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\StandardMannequinPinpoint"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "STANDARD_MANNEQUIN_PINPOINT_V2=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

Set-Location $ProjectRoot
$env:GIT_PAGER = "cat"

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"

if (-not (Test-Path -LiteralPath $ProjectFile -PathType Leaf)) {
    Stop-Gate "UPROJECT_NOT_FOUND" 11
}
if (-not (Test-Path -LiteralPath $EditorCmd -PathType Leaf)) {
    Stop-Gate "UNREALEDITOR_CMD_NOT_FOUND" 12
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " MOVER PLUGIN STATE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$ProjectJson = Get-Content -Raw -LiteralPath $ProjectFile | ConvertFrom-Json
$PluginState = @{}
if ($ProjectJson.PSObject.Properties.Name -contains "Plugins") {
    foreach ($P in $ProjectJson.Plugins) {
        $PluginState[$P.Name] = [bool]$P.Enabled
    }
}

$MoverExamplesEnabled = $PluginState.ContainsKey("MoverExamples") -and $PluginState["MoverExamples"]
$MoverTestsEnabled = $PluginState.ContainsKey("MoverTests") -and $PluginState["MoverTests"]

Write-Host "MOVER_EXAMPLES_PROJECT_ENABLED=$MoverExamplesEnabled"
Write-Host "MOVER_TESTS_PROJECT_ENABLED=$MoverTestsEnabled"

$MoverExamplesMesh = Join-Path $UERoot "Engine\Plugins\Experimental\MoverExamples\Content\Characters\Mannequins\Meshes\SKM_Manny_Simple.uasset"
$MoverExamplesABP  = Join-Path $UERoot "Engine\Plugins\Experimental\MoverExamples\Content\Characters\Mannequins\Animations\ABP_Manny.uasset"
$MoverTestsMesh    = Join-Path $UERoot "Engine\Plugins\Experimental\MoverTests\Content\Characters\Mannequins\Meshes\SKM_Manny.uasset"
$MoverTestsABP     = Join-Path $UERoot "Engine\Plugins\Experimental\MoverTests\Content\Characters\Mannequins\Animations\ABP_Manny.uasset"

Write-Host "MOVER_EXAMPLES_MESH_ON_DISK=$(Test-Path -LiteralPath $MoverExamplesMesh -PathType Leaf)"
Write-Host "MOVER_EXAMPLES_ABP_ON_DISK=$(Test-Path -LiteralPath $MoverExamplesABP -PathType Leaf)"
Write-Host "MOVER_TESTS_MESH_ON_DISK=$(Test-Path -LiteralPath $MoverTestsMesh -PathType Leaf)"
Write-Host "MOVER_TESTS_ABP_ON_DISK=$(Test-Path -LiteralPath $MoverTestsABP -PathType Leaf)"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " STANDARD TEMPLATE RESOURCES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$TemplateResourceRoot = Join-Path $UERoot "Templates\TemplateResources"

$TemplateFiles = @()
if (Test-Path -LiteralPath $TemplateResourceRoot -PathType Container) {
    $TemplateFiles = @(Get-ChildItem -LiteralPath $TemplateResourceRoot -File -Recurse -Filter "*.uasset" -ErrorAction SilentlyContinue)
}

$MannequinFiles = @($TemplateFiles | Where-Object {
    $_.FullName -match '(?i)\\Mannequins\\|Manny|Quinn|ThirdPerson'
})

$TemplateMannyMesh = @($MannequinFiles | Where-Object { $_.Name -eq "SKM_Manny_Simple.uasset" })
$TemplateMannyFull = @($MannequinFiles | Where-Object { $_.Name -eq "SKM_Manny.uasset" })
$TemplateABPManny = @($MannequinFiles | Where-Object { $_.Name -eq "ABP_Manny.uasset" })
$TemplateABPQuinn = @($MannequinFiles | Where-Object { $_.Name -eq "ABP_Quinn.uasset" })
$TemplateThirdPersonBP = @($MannequinFiles | Where-Object { $_.Name -match '(?i)BP_ThirdPerson_(Manny|Quinn)\.uasset' })

Write-Host "TEMPLATE_TOTAL_UASSET_COUNT=$($TemplateFiles.Count)"
Write-Host "TEMPLATE_MANNEQUIN_RELATED_COUNT=$($MannequinFiles.Count)"
Write-Host "TEMPLATE_SKM_MANNY_SIMPLE_COUNT=$($TemplateMannyMesh.Count)"
Write-Host "TEMPLATE_SKM_MANNY_COUNT=$($TemplateMannyFull.Count)"
Write-Host "TEMPLATE_ABP_MANNY_COUNT=$($TemplateABPManny.Count)"
Write-Host "TEMPLATE_ABP_QUINN_COUNT=$($TemplateABPQuinn.Count)"
Write-Host "TEMPLATE_THIRDPERSON_BP_COUNT=$($TemplateThirdPersonBP.Count)"

Write-Host ""
Write-Host "=== TEMPLATE MANNY / QUINN FILES ===" -ForegroundColor Yellow
@(
    $TemplateMannyMesh
    $TemplateMannyFull
    $TemplateABPManny
    $TemplateABPQuinn
    $TemplateThirdPersonBP
) | Sort-Object FullName -Unique | ForEach-Object {
    Write-Host "TEMPLATE_ASSET=$($_.FullName)"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TEMPLATE MANNEQUIN DIRECTORY INVENTORY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$MannequinDirs = @()
if (Test-Path -LiteralPath $TemplateResourceRoot -PathType Container) {
    $MannequinDirs = @(Get-ChildItem -LiteralPath $TemplateResourceRoot -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq "Mannequins" } |
        Sort-Object FullName -Unique)
}

Write-Host "TEMPLATE_MANNEQUIN_DIR_COUNT=$($MannequinDirs.Count)"
foreach ($Dir in $MannequinDirs) {
    $Count = @(Get-ChildItem -LiteralPath $Dir.FullName -File -Recurse -Filter "*.uasset" -ErrorAction SilentlyContinue).Count
    Write-Host "TEMPLATE_MANNEQUIN_DIR=$($Dir.FullName) UASSET_COUNT=$Count"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FEATURE PACK / THIRD PERSON SOURCES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$FeaturePacksRoot = Join-Path $UERoot "FeaturePacks"
$ThirdPersonPacks = @()
if (Test-Path -LiteralPath $FeaturePacksRoot -PathType Container) {
    $ThirdPersonPacks = @(Get-ChildItem -LiteralPath $FeaturePacksRoot -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)ThirdPerson|TP_ThirdPerson|StarterContent' } |
        Sort-Object FullName -Unique)
}

Write-Host "THIRDPERSON_FEATUREPACK_SOURCE_COUNT=$($ThirdPersonPacks.Count)"
foreach ($Pack in $ThirdPersonPacks) {
    Write-Host "FEATUREPACK_SOURCE=$($Pack.FullName)"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " UNREAL MOUNT CHECK" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$PyFile = Join-Path $EvidenceRoot "mount_check_$Stamp.py"
$StdOut = Join-Path $EvidenceRoot "mount_check_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "mount_check_$Stamp.stderr.log"

$Python = @'
import unreal

registry = unreal.AssetRegistryHelpers.get_asset_registry()

for mount in ("/MoverExamples", "/MoverTests", "/Game", "/Engine"):
    try:
        assets = registry.get_assets_by_path(mount, recursive=True)
        print(f"ASWW_MOUNT_COUNT|{mount}|{len(assets)}")
    except Exception as exc:
        print(f"ASWW_MOUNT_ERROR|{mount}|{exc}")

checks = [
    "/MoverExamples/Characters/Mannequins/Meshes/SKM_Manny_Simple",
    "/MoverExamples/Characters/Mannequins/Animations/ABP_Manny",
    "/MoverTests/Characters/Mannequins/Meshes/SKM_Manny",
    "/MoverTests/Characters/Mannequins/Animations/ABP_Manny",
    "/Engine/BasicShapes/Cube",
]

for path in checks:
    exists = unreal.EditorAssetLibrary.does_asset_exist(path)
    obj = unreal.EditorAssetLibrary.load_asset(path) if exists else None
    cls = obj.get_class().get_name() if obj else "NONE"
    print(f"ASWW_ASSET_CHECK|{path}|EXISTS={exists}|LOAD={obj is not None}|CLASS={cls}")

print("ASWW_NO_ASSETS_MODIFIED|TRUE")
'@

[IO.File]::WriteAllText($PyFile, $Python, [Text.UTF8Encoding]::new($false))
$PyForward = $PyFile.Replace('\','/')

$Args = @(
    $ProjectFile,
    "-unattended",
    "-nop4",
    "-nosplash",
    "-NullRHI",
    "-stdout",
    "-FullStdOutLogOutput",
    "-ExecutePythonScript=$PyForward"
)

$Proc = Start-Process `
    -FilePath $EditorCmd `
    -ArgumentList $Args `
    -WorkingDirectory $ProjectRoot `
    -PassThru `
    -Wait `
    -RedirectStandardOutput $StdOut `
    -RedirectStandardError $StdErr

$Exit = $Proc.ExitCode
Write-Host "UNREAL_EDITOR_CMD_EXIT=$Exit"

$Out = if (Test-Path -LiteralPath $StdOut) { Get-Content -Raw -LiteralPath $StdOut } else { "" }
$Err = if (Test-Path -LiteralPath $StdErr) { Get-Content -Raw -LiteralPath $StdErr } else { "" }
$Text = $Out + "`n" + $Err

$Interesting = @($Text -split "`r?`n" | Where-Object {
    $_ -match 'ASWW_MOUNT_COUNT\||ASWW_MOUNT_ERROR\||ASWW_ASSET_CHECK\||ASWW_NO_ASSETS_MODIFIED\|'
})
foreach ($Line in $Interesting) {
    if ($Line -match 'LogPython:\s*(.*)$') {
        Write-Host $Matches[1]
    } else {
        Write-Host $Line
    }
}

function Read-MountCount([string]$Mount) {
    $Esc = [regex]::Escape($Mount)
    $M = [regex]::Match($Text, "ASWW_MOUNT_COUNT\|$Esc\|(\d+)")
    if ($M.Success) { return [int]$M.Groups[1].Value }
    return 0
}

$MoverExamplesMountCount = Read-MountCount "/MoverExamples"
$MoverTestsMountCount = Read-MountCount "/MoverTests"
$EngineCubeExists = $Text -match 'ASWW_ASSET_CHECK\|/Engine/BasicShapes/Cube\|EXISTS=True'

$PythonError = $Text -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PINPOINT CLASSIFICATION V2" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "MOVER_EXAMPLES_MOUNT_ASSET_COUNT=$MoverExamplesMountCount"
Write-Host "MOVER_TESTS_MOUNT_ASSET_COUNT=$MoverTestsMountCount"
Write-Host "ENGINE_CUBE_EXISTS=$EngineCubeExists"
Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "FATAL_ERROR_SEEN=$Fatal"

if ($Exit -ne 0 -or $PythonError -or $Fatal) {
    Write-Host "STANDARD_MANNEQUIN_CLASSIFICATION=UNREAL_MOUNT_DIAGNOSTIC_FAILED" -ForegroundColor Red
    Stop-Gate "UNREAL_MOUNT_CHECK_FAILED" $(if ($Exit -gt 0) { $Exit } else { 20 })
}

if (-not $MoverExamplesEnabled -and
    -not $MoverTestsEnabled -and
    $MoverExamplesMountCount -eq 0 -and
    $MoverTestsMountCount -eq 0) {

    Write-Host "MOVER_PLUGIN_MOUNT_STATUS=CONFIRMED_NOT_MOUNTED" -ForegroundColor Green

    if ($TemplateABPManny.Count -gt 0 -and $TemplateMannyMesh.Count -gt 0) {
        Write-Host "STANDARD_MANNEQUIN_CLASSIFICATION=COMPLETE_LOOSE_TEMPLATE_MANNY_SET_AVAILABLE" -ForegroundColor Green
        Write-Host "NEXT_GATE=SAFE_COPY_TEMPLATE_MANNEQUIN_SET_TO_GAME_AND_VERIFY_LOAD" -ForegroundColor Green
    }
    elseif ($ThirdPersonPacks.Count -gt 0) {
        Write-Host "STANDARD_MANNEQUIN_CLASSIFICATION=THIRDPERSON_FEATUREPACK_AVAILABLE" -ForegroundColor Green
        Write-Host "NEXT_GATE=IMPORT_THIRDPERSON_FEATUREPACK_INTO_GAME_WITHOUT_ENABLING_MOVER" -ForegroundColor Green
    }
    elseif ($TemplateMannyMesh.Count -gt 0) {
        Write-Host "STANDARD_MANNEQUIN_CLASSIFICATION=TEMPLATE_MANNY_MESH_ONLY_NO_LOOSE_ABP_FOUND" -ForegroundColor Yellow
        Write-Host "NEXT_GATE=USE_TEMPLATE_MANNY_FOR_SKELETAL_VISUAL_PROOF_OR_IMPORT_ANIMATION_SET_SEPARATELY" -ForegroundColor Yellow
    }
    else {
        Write-Host "STANDARD_MANNEQUIN_CLASSIFICATION=NO_CLEAN_STANDARD_MANNY_SOURCE_FOUND" -ForegroundColor Yellow
        Write-Host "NEXT_GATE=CHOOSE_TEMP_MOVER_ENABLE_OR_EXTERNAL_CHARACTER_IMPORT" -ForegroundColor Yellow
    }
}
else {
    Write-Host "MOVER_PLUGIN_MOUNT_STATUS=UNEXPECTED_OR_MOUNTED" -ForegroundColor Yellow
    Write-Host "STANDARD_MANNEQUIN_CLASSIFICATION=REVIEW_MOUNT_STATE_BEFORE_IMPORT" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=VERIFY_MOUNTED_MANNY_ASSET_CLASS_AND_SKELETON" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "STANDARD_MANNEQUIN_PINPOINT_V2=PASS" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "KEEP_TEMP_VISUAL_PROOF_UNTIL_REAL_CHARACTER_PACKAGE_PASSES" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_VISUAL_PROOF_OR_TELEMETRY" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
