[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\ThirdPersonTemplateV3"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "THIRDPERSON_TEMPLATE_SOURCE_V3=STOPPED" -ForegroundColor Red
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

$UnrealPak = Join-Path $UERoot "Engine\Binaries\Win64\UnrealPak.exe"
if (-not (Test-Path -LiteralPath $UnrealPak -PathType Leaf)) {
    Stop-Gate "UNREALPAK_NOT_FOUND" 11
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " THIRD PERSON TEMPLATE PROJECTS / DIRECTORIES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$TemplateRoot = Join-Path $UERoot "Templates"
$TemplateProjects = @()
if (Test-Path -LiteralPath $TemplateRoot -PathType Container) {
    $TemplateProjects = @(Get-ChildItem -LiteralPath $TemplateRoot -File -Recurse -Filter "*.uproject" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '(?i)ThirdPerson|TP_' } |
        Sort-Object FullName -Unique)
}

Write-Host "THIRDPERSON_TEMPLATE_UPROJECT_COUNT=$($TemplateProjects.Count)"
foreach ($Proj in $TemplateProjects) {
    Write-Host "THIRDPERSON_TEMPLATE_UPROJECT=$($Proj.FullName)"
}

$ThirdPersonDirs = @()
if (Test-Path -LiteralPath $TemplateRoot -PathType Container) {
    $ThirdPersonDirs = @(Get-ChildItem -LiteralPath $TemplateRoot -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)ThirdPerson|TP_ThirdPerson' } |
        Sort-Object FullName -Unique |
        Select-Object -First 120)
}

Write-Host "THIRDPERSON_TEMPLATE_DIR_COUNT=$($ThirdPersonDirs.Count)"
foreach ($Dir in $ThirdPersonDirs) {
    Write-Host "THIRDPERSON_TEMPLATE_DIR=$($Dir.FullName)"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ALL STANDARD TEMPLATE MANNY / ANIM SOURCES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$AllTemplateAssets = @()
if (Test-Path -LiteralPath $TemplateRoot -PathType Container) {
    $AllTemplateAssets = @(Get-ChildItem -LiteralPath $TemplateRoot -File -Recurse -Filter "*.uasset" -ErrorAction SilentlyContinue)
}

$MannyMeshes = @($AllTemplateAssets | Where-Object { $_.Name -in @("SKM_Manny.uasset","SKM_Manny_Simple.uasset") })
$MannyAnimLike = @($AllTemplateAssets | Where-Object {
    $_.Name -match '(?i)^ABP_.*Manny.*\.uasset$|^ABP_.*ThirdPerson.*\.uasset$|^ABP_Unarmed\.uasset$|^ABP_.*Locomotion.*\.uasset$'
})
$ThirdPersonBPs = @($AllTemplateAssets | Where-Object { $_.Name -match '(?i)^BP_ThirdPerson_(Manny|Quinn)\.uasset$' })

Write-Host "STANDARD_TEMPLATE_MANNY_MESH_COUNT=$($MannyMeshes.Count)"
foreach ($A in $MannyMeshes) { Write-Host "STANDARD_MANNY_MESH=$($A.FullName)" }

Write-Host "STANDARD_TEMPLATE_MANNY_ANIMLIKE_COUNT=$($MannyAnimLike.Count)"
foreach ($A in $MannyAnimLike | Select-Object -First 120) { Write-Host "STANDARD_MANNY_ANIMLIKE=$($A.FullName)" }

Write-Host "STANDARD_TEMPLATE_THIRDPERSON_BP_COUNT=$($ThirdPersonBPs.Count)"
foreach ($A in $ThirdPersonBPs) { Write-Host "STANDARD_THIRDPERSON_BP=$($A.FullName)" }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FEATURE PACK RAW INVENTORY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$PackPaths = @(
    (Join-Path $UERoot "FeaturePacks\TP_ThirdPerson.upack")
    (Join-Path $UERoot "FeaturePacks\TP_ThirdPersonBP.upack")
)

$PackSummaries = @()

foreach ($Pack in $PackPaths) {
    $Name = [IO.Path]::GetFileNameWithoutExtension($Pack)
    if (-not (Test-Path -LiteralPath $Pack -PathType Leaf)) {
        Write-Host "PACK_$Name=NOT_FOUND"
        continue
    }

    $ListFile = Join-Path $EvidenceRoot "$($Name)_list_$Stamp.txt"
    $ListOutput = & $UnrealPak $Pack -List 2>&1
    $Exit = $LASTEXITCODE
    $ListOutput | Set-Content -LiteralPath $ListFile -Encoding UTF8

    Write-Host "PACK=$Name"
    Write-Host "PACK_LIST_EXIT=$Exit"
    Write-Host "PACK_LIST_FILE=$ListFile"

    $Lines = @($ListOutput | ForEach-Object { "$_" })
    $UassetLines = @($Lines | Where-Object { $_ -match '(?i)\.uasset' })
    $MannyLines = @($Lines | Where-Object { $_ -match '(?i)Manny|Quinn|Mannequin' })
    $AnimLines = @($Lines | Where-Object { $_ -match '(?i)ABP_|AnimBlueprint|Animations/' })

    Write-Host "PACK_UASSET_LINE_COUNT=$($UassetLines.Count)"
    Write-Host "PACK_MANNY_LINE_COUNT=$($MannyLines.Count)"
    Write-Host "PACK_ANIM_LINE_COUNT=$($AnimLines.Count)"

    Write-Host "=== $Name RELEVANT LIST SAMPLE ===" -ForegroundColor Yellow
    @($Lines | Where-Object {
        $_ -match '(?i)Manny|Quinn|Mannequin|ABP_|ThirdPerson|ContentSettings|manifest'
    } | Select-Object -First 140) | ForEach-Object { Write-Host $_ }

    $PackSummaries += [PSCustomObject]@{
        Name = $Name
        Exit = $Exit
        UassetCount = $UassetLines.Count
        MannyCount = $MannyLines.Count
        AnimCount = $AnimLines.Count
        ListFile = $ListFile
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TEMPLATE RESOURCE TREE NEAR MANNY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

foreach ($Mesh in $MannyMeshes) {
    $Dir = $Mesh.Directory
    Write-Host "MANNY_MESH_DIR=$($Dir.FullName)"

    $Ancestor = $Dir
    for ($i = 0; $i -lt 4 -and $Ancestor; $i++) {
        Write-Host "ANCESTOR_$i=$($Ancestor.FullName)"
        $Ancestor = $Ancestor.Parent
    }

    $RootCandidate = $Dir.Parent
    if ($RootCandidate) {
        $Nearby = @(Get-ChildItem -LiteralPath $RootCandidate.FullName -File -Recurse -Filter "*.uasset" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)ABP_|Anim|Manny|Quinn|Skeleton|SK_' } |
            Select-Object -First 160)
        foreach ($N in $Nearby) {
            Write-Host "NEARBY_ASSET=$($N.FullName)"
        }
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLASSIFICATION V3" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$AnyPackHasManny = @($PackSummaries | Where-Object { $_.MannyCount -gt 0 }).Count -gt 0
$AnyPackHasAssets = @($PackSummaries | Where-Object { $_.UassetCount -gt 0 }).Count -gt 0
$HasLooseMannyMesh = $MannyMeshes.Count -gt 0
$HasLooseMannyAnim = $MannyAnimLike.Count -gt 0
$HasTemplateProject = $TemplateProjects.Count -gt 0

Write-Host "FEATUREPACK_CONTAINS_MANNY_REFERENCES=$AnyPackHasManny"
Write-Host "FEATUREPACK_CONTAINS_UASSET_FILES=$AnyPackHasAssets"
Write-Host "LOOSE_STANDARD_MANNY_MESH_AVAILABLE=$HasLooseMannyMesh"
Write-Host "LOOSE_STANDARD_MANNY_ANIMLIKE_AVAILABLE=$HasLooseMannyAnim"
Write-Host "THIRDPERSON_TEMPLATE_PROJECT_AVAILABLE=$HasTemplateProject"

if ($HasLooseMannyMesh -and $HasLooseMannyAnim) {
    Write-Host "THIRDPERSON_TEMPLATE_SOURCE_CLASSIFICATION=LOOSE_STANDARD_MESH_AND_ANIMATION_ASSETS_FOUND" -ForegroundColor Green
    Write-Host "NEXT_GATE=VERIFY_LOOSE_TEMPLATE_MANNY_DEPENDENCY_SET_THEN_COPY_TO_GAME" -ForegroundColor Green
}
elseif ($HasTemplateProject) {
    Write-Host "THIRDPERSON_TEMPLATE_SOURCE_CLASSIFICATION=FULL_TEMPLATE_PROJECT_FOUND" -ForegroundColor Green
    Write-Host "NEXT_GATE=READ_TEMPLATE_PROJECT_ASSET_PATHS_AND_MIGRATE_DEPENDENCIES" -ForegroundColor Green
}
elseif ($AnyPackHasAssets) {
    Write-Host "THIRDPERSON_TEMPLATE_SOURCE_CLASSIFICATION=FEATUREPACK_HAS_CONTENT_BUT_NOT_SELF_CONTAINED_MANNY_PAIR" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=RESOLVE_FEATUREPACK_REFERENCED_SHARED_TEMPLATE_RESOURCES" -ForegroundColor Yellow
}
elseif ($HasLooseMannyMesh) {
    Write-Host "THIRDPERSON_TEMPLATE_SOURCE_CLASSIFICATION=LOOSE_MANNY_MESH_ONLY_SHARED_ANIMATION_RESOURCES_NOT_FOUND_BY_NAME" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=INSPECT_TEMPLATE_BLUEPRINT_DEPENDENCIES_FOR_ANIMATION_CLASS" -ForegroundColor Yellow
}
else {
    Write-Host "THIRDPERSON_TEMPLATE_SOURCE_CLASSIFICATION=NO_CLEAN_STANDARD_SOURCE_FOUND" -ForegroundColor Red
    Write-Host "NEXT_GATE=USE_EXTERNAL_CHARACTER_IMPORT_OR_TEMP_MOVER_ENABLE_FOR_PROOF_ONLY" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "THIRDPERSON_TEMPLATE_SOURCE_V3=PASS" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
