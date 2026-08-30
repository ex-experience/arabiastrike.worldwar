[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\MannyMountPinpoint"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "MANNY_MOUNT_PINPOINT=STOPPED" -ForegroundColor Red
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
Write-Host " PHYSICAL MANNY FILE LOCATIONS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$TargetNames = @(
    "SKM_Manny.uasset",
    "SKM_Manny_Simple.uasset",
    "ABP_Manny.uasset",
    "BP_ThirdPerson_Manny.uasset"
)

$Physical = @()
foreach ($Name in $TargetNames) {
    $Hits = @(Get-ChildItem -LiteralPath $UERoot -File -Recurse -Filter $Name -ErrorAction SilentlyContinue)
    if ($Hits.Count -eq 0) {
        Write-Host "PHYSICAL_$($Name.Replace('.uasset','').ToUpperInvariant())=NOT_FOUND"
        continue
    }

    foreach ($Hit in $Hits) {
        Write-Host "PHYSICAL_ASSET=$($Hit.FullName)"
        $Physical += $Hit
    }
}

function Find-NearestPluginDescriptor {
    param([System.IO.FileInfo]$Asset)

    $Dir = $Asset.Directory
    while ($Dir -and $Dir.FullName.StartsWith($UERoot, [StringComparison]::OrdinalIgnoreCase)) {
        $Plugin = @(Get-ChildItem -LiteralPath $Dir.FullName -File -Filter "*.uplugin" -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($Plugin.Count -gt 0) {
            return $Plugin[0]
        }
        $Dir = $Dir.Parent
    }
    return $null
}

$PluginDescriptors = @{}
foreach ($Asset in $Physical) {
    $Plugin = Find-NearestPluginDescriptor $Asset
    if ($null -ne $Plugin) {
        $PluginDescriptors[$Plugin.FullName] = $Plugin
        Write-Host "ASSET_PLUGIN=$($Asset.Name) => $($Plugin.FullName)"
    }
    else {
        Write-Host "ASSET_PLUGIN=$($Asset.Name) => NONE"
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PROJECT PLUGIN ENABLEMENT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$ProjectJson = Get-Content -Raw -LiteralPath $ProjectFile | ConvertFrom-Json
$EnabledPlugins = @{}
if ($ProjectJson.PSObject.Properties.Name -contains "Plugins") {
    foreach ($P in $ProjectJson.Plugins) {
        $EnabledPlugins[$P.Name] = [bool]$P.Enabled
        Write-Host "PROJECT_PLUGIN=$($P.Name) ENABLED=$($P.Enabled)"
    }
}

foreach ($Entry in $PluginDescriptors.GetEnumerator()) {
    $Descriptor = Get-Content -Raw -LiteralPath $Entry.Key | ConvertFrom-Json
    $PluginName = [IO.Path]::GetFileNameWithoutExtension($Entry.Key)
    $Enabled = if ($EnabledPlugins.ContainsKey($PluginName)) { $EnabledPlugins[$PluginName] } else { $false }
    $Type = if ($Descriptor.PSObject.Properties.Name -contains "Category") { $Descriptor.Category } else { "" }
    $CanContain = if ($Descriptor.PSObject.Properties.Name -contains "CanContainContent") { $Descriptor.CanContainContent } else { "" }
    Write-Host "OWNER_PLUGIN=$PluginName PROJECT_ENABLED=$Enabled CAN_CONTAIN_CONTENT=$CanContain CATEGORY=$Type DESCRIPTOR=$($Entry.Key)"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TEMPLATE / FEATUREPACK SOURCES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$TemplateCandidates = @()
$TemplateRoots = @(
    (Join-Path $UERoot "Templates"),
    (Join-Path $UERoot "FeaturePacks"),
    (Join-Path $UERoot "Samples")
)

foreach ($Root in $TemplateRoots) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { continue }

    $Dirs = @(Get-ChildItem -LiteralPath $Root -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq "Mannequins" -or
            $_.FullName -match '(?i)ThirdPerson.*Characters\\Mannequins|Characters\\Mannequins'
        } |
        Select-Object -First 80)

    foreach ($D in $Dirs) {
        if ($TemplateCandidates.FullName -notcontains $D.FullName) {
            $TemplateCandidates += $D
            Write-Host "TEMPLATE_MANNEQUIN_DIR=$($D.FullName)"
        }
    }

    $Packs = @(Get-ChildItem -LiteralPath $Root -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)ThirdPerson.*\.(upack|zip)$' } |
        Select-Object -First 40)
    foreach ($Pack in $Packs) {
        Write-Host "THIRDPERSON_FEATUREPACK=$($Pack.FullName)"
    }
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$PyFile = Join-Path $EvidenceRoot "pinpoint_manny_mount_$Stamp.py"
$StdOut = Join-Path $EvidenceRoot "pinpoint_manny_mount_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "pinpoint_manny_mount_$Stamp.stderr.log"

$Python = @'
import unreal

print("=== ASWW MANNY MOUNT CHECK ===")

registry = unreal.AssetRegistryHelpers.get_asset_registry()

mounts = [
    "/MoverTests",
    "/MoverExamples",
    "/Game",
    "/Engine",
]

for mount in mounts:
    try:
        assets = registry.get_assets_by_path(mount, recursive=True)
        print(f"MOUNT_ASSET_COUNT|{mount}|{len(assets)}")
    except Exception as exc:
        print(f"MOUNT_ERROR|{mount}|{exc}")

paths = [
    "/MoverTests/Characters/Mannequins/Meshes/SKM_Manny",
    "/MoverTests/Characters/Mannequins/Meshes/SKM_Manny_Simple",
    "/MoverTests/Characters/Mannequins/Animations/ABP_Manny",
    "/MoverExamples/Characters/Mannequins/Meshes/SKM_Manny_Simple",
    "/MoverExamples/Characters/Mannequins/Animations/ABP_Manny",
    "/Engine/BasicShapes/Cube",
]

for path in paths:
    exists = unreal.EditorAssetLibrary.does_asset_exist(path)
    obj = unreal.EditorAssetLibrary.load_asset(path) if exists else None
    cls = obj.get_class().get_name() if obj else "NONE"
    print(f"ASSET_CHECK|{path}|EXISTS={exists}|LOAD={obj is not None}|CLASS={cls}")

print("NO_ASSETS_WERE_MODIFIED|TRUE")
'@

[IO.File]::WriteAllText($PyFile, $Python, [Text.UTF8Encoding]::new($false))
$PyForward = $PyFile.Replace('\','/')

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " UNREAL MOUNT CHECK" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

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
    $_ -match 'MOUNT_ASSET_COUNT\||MOUNT_ERROR\||ASSET_CHECK\||NO_ASSETS_WERE_MODIFIED\|'
})
foreach ($Line in $Interesting) {
    $Clean = $Line
    if ($Clean -match 'LogPython:\s*(.*)$') {
        $Clean = $Matches[1]
    }
    Write-Host $Clean
}

$MoverTestsCount = 0
$MoverExamplesCount = 0

$MT = [regex]::Match($Text, 'MOUNT_ASSET_COUNT\|/MoverTests\|(\d+)')
if ($MT.Success) { $MoverTestsCount = [int]$MT.Groups[1].Value }

$ME = [regex]::Match($Text, 'MOUNT_ASSET_COUNT\|/MoverExamples\|(\d+)')
if ($ME.Success) { $MoverExamplesCount = [int]$ME.Groups[1].Value }

$MannyTestExists = $Text -match 'ASSET_CHECK\|/MoverTests/Characters/Mannequins/Meshes/SKM_Manny\|EXISTS=True'
$MannyExampleExists = $Text -match 'ASSET_CHECK\|/MoverExamples/Characters/Mannequins/Meshes/SKM_Manny_Simple\|EXISTS=True'
$EngineCubeExists = $Text -match 'ASSET_CHECK\|/Engine/BasicShapes/Cube\|EXISTS=True'
$PythonError = $Text -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PINPOINT CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "MOVER_TESTS_MOUNT_ASSET_COUNT=$MoverTestsCount"
Write-Host "MOVER_EXAMPLES_MOUNT_ASSET_COUNT=$MoverExamplesCount"
Write-Host "MOVER_TESTS_MANNY_EXISTS=$MannyTestExists"
Write-Host "MOVER_EXAMPLES_MANNY_EXISTS=$MannyExampleExists"
Write-Host "ENGINE_CUBE_EXISTS=$EngineCubeExists"
Write-Host "TEMPLATE_MANNEQUIN_DIR_COUNT=$($TemplateCandidates.Count)"
Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "FATAL_ERROR_SEEN=$Fatal"

if ($Exit -ne 0 -or $PythonError -or $Fatal) {
    Write-Host "MANNY_MOUNT_CLASSIFICATION=UNREAL_DIAGNOSTIC_FAILURE" -ForegroundColor Red
    Stop-Gate "UNREAL_MOUNT_CHECK_FAILED" $(if ($Exit -gt 0) { $Exit } else { 20 })
}
elseif ($EngineCubeExists -and
        $MoverTestsCount -eq 0 -and
        $MoverExamplesCount -eq 0 -and
        ($Physical.Count -gt 0)) {

    Write-Host "MANNY_MOUNT_CLASSIFICATION=MOVER_ASSETS_EXIST_ON_DISK_BUT_ARE_NOT_MOUNTED_IN_PROJECT" -ForegroundColor Yellow

    if ($TemplateCandidates.Count -gt 0) {
        Write-Host "NEXT_GATE=IMPORT_STANDARD_THIRDPERSON_MANNEQUIN_CONTENT_INTO_GAME_MOUNT" -ForegroundColor Green
    }
    else {
        Write-Host "NEXT_GATE=ENABLE_CORRECT_MOVER_CONTENT_PLUGIN_OR_IMPORT_MANNEQUIN_FEATUREPACK" -ForegroundColor Yellow
    }
}
elseif ($MannyTestExists -or $MannyExampleExists) {
    Write-Host "MANNY_MOUNT_CLASSIFICATION=MOVER_MANNY_IS_MOUNTED" -ForegroundColor Green
    Write-Host "NEXT_GATE=FIX_SKELETON_COMPATIBILITY_INTROSPECTION_AND_SELECT_PAIR" -ForegroundColor Green
}
else {
    Write-Host "MANNY_MOUNT_CLASSIFICATION=NO_USABLE_MANNY_MOUNT_FOUND" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=IMPORT_STANDARD_THIRDPERSON_MANNEQUIN_CONTENT_INTO_GAME_MOUNT" -ForegroundColor Yellow
}

Write-Host "MANNY_MOUNT_PINPOINT=PASS" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "KEEP_TEMP_VISUAL_PROOF_UNTIL_REAL_CHARACTER_PACKAGE_PASSES" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_VISUAL_PROOF_OR_TELEMETRY" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
