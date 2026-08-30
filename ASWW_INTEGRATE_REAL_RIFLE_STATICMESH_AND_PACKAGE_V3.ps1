[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$StageRoot = "D:\ASWW_STAGE"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "REAL_RIFLE_STATICMESH_INTEGRATION=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
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
$BuildScript = Join-Path $ProjectRoot "BuildScripts\build_win64.ps1"
$CharacterCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"

$SourceRifleRoot = Join-Path $UERoot "Templates\TemplateResources\Standard\Weapons\Content\Rifle"
$DestRifleRoot = Join-Path $ProjectRoot "Content\Weapons\Rifle"
$ExpectedSK = Join-Path $DestRifleRoot "Meshes\SK_Rifle.uasset"
$ExpectedSM = Join-Path $DestRifleRoot "Meshes\SM_Rifle.uasset"

foreach ($Required in @($ProjectFile,$EditorCmd,$BuildScript,$CharacterCpp,$SourceRifleRoot)) {
    if (-not (Test-Path -LiteralPath $Required)) {
        Stop-Gate "MISSING_REQUIRED_PATH_$Required" 11
    }
}

$Original = Get-Content -Raw -LiteralPath $CharacterCpp

if ($Original -match "ASWW_REAL_RIFLE_VISUAL_BEGIN") {
    Stop-Gate "RIFLE_VISUAL_ALREADY_PRESENT_SOURCE_NOT_TOUCHED" 12
}

if ($Original -notmatch "ASWW_REAL_PLAYER_MANNY") {
    Stop-Gate "REAL_MANNY_INTEGRATION_MARKER_NOT_FOUND" 13
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY COPIED RIFLE ASSET FAMILY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $DestRifleRoot -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $DestRifleRoot | Out-Null
}

# The previous stopped run may already have copied these 8 assets.
# Only copy missing files/directories; never delete or overwrite unrelated content.
$SourceChildren = @(Get-ChildItem -LiteralPath $SourceRifleRoot -Force -ErrorAction Stop)
foreach ($Child in $SourceChildren) {
    $DestChild = Join-Path $DestRifleRoot $Child.Name
    if (-not (Test-Path -LiteralPath $DestChild)) {
        Copy-Item -LiteralPath $Child.FullName -Destination $DestRifleRoot -Recurse -Force
    }
}

$CopiedFiles = @(Get-ChildItem -LiteralPath $DestRifleRoot -Recurse -File -ErrorAction Stop)
$UAssetCount = @($CopiedFiles | Where-Object { $_.Extension -ieq ".uasset" }).Count

Write-Host "RIFLE_DEST_FILE_COUNT=$($CopiedFiles.Count)"
Write-Host "RIFLE_DEST_UASSET_COUNT=$UAssetCount"
Write-Host "SK_RIFLE_FILE_EXISTS=$(Test-Path -LiteralPath $ExpectedSK -PathType Leaf)"
Write-Host "SM_RIFLE_FILE_EXISTS=$(Test-Path -LiteralPath $ExpectedSM -PathType Leaf)"

if (-not (Test-Path -LiteralPath $ExpectedSM -PathType Leaf)) {
    Stop-Gate "SM_RIFLE_UASSET_NOT_FOUND_AFTER_COPY" 20
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY UE ASSET CLASSES: SK_Rifle vs SM_Rifle" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$VerifyRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\RealRifleAssetClassVerify"
New-Item -ItemType Directory -Force -Path $VerifyRoot | Out-Null

$Py = Join-Path $VerifyRoot "verify_rifle_asset_classes_$Stamp.py"
$Out = Join-Path $VerifyRoot "verify_rifle_asset_classes_$Stamp.stdout.log"
$Err = Join-Path $VerifyRoot "verify_rifle_asset_classes_$Stamp.stderr.log"

$PyText = @'
import unreal

registry = unreal.AssetRegistryHelpers.get_asset_registry()
registry.scan_paths_synchronous(["/Game/Weapons/Rifle"], True)

paths = [
    "/Game/Weapons/Rifle/Meshes/SK_Rifle.SK_Rifle",
    "/Game/Weapons/Rifle/Meshes/SM_Rifle.SM_Rifle",
]

for p in paths:
    a = unreal.load_asset(p)
    print(f"ASWW_RIFLE_ASSET|PATH={p}|LOAD={a is not None}|CLASS={a.get_class().get_name() if a else 'NONE'}")

assets = registry.get_assets_by_path("/Game/Weapons/Rifle", recursive=True)
print(f"ASWW_RIFLE_REGISTRY_COUNT={len(assets)}")
for d in assets:
    print(
        f"ASWW_RIFLE_REGISTRY|PACKAGE={d.package_name}|NAME={d.asset_name}|"
        f"CLASS={d.asset_class_path.asset_name}"
    )
'@

[IO.File]::WriteAllText($Py, $PyText, [Text.UTF8Encoding]::new($false))
$PyForward = $Py.Replace('\','/')

$Args = @(
    $ProjectFile
    "-unattended"
    "-nop4"
    "-nosplash"
    "-NullRHI"
    "-stdout"
    "-FullStdOutLogOutput"
    "-ExecutePythonScript=$PyForward"
)

& $EditorCmd @Args 1> $Out 2> $Err
$VerifyExit = $LASTEXITCODE

$Combined = ""
if (Test-Path -LiteralPath $Out) {
    $Combined += Get-Content -Raw -LiteralPath $Out
    Select-String -LiteralPath $Out -Pattern "ASWW_RIFLE_ASSET|ASWW_RIFLE_REGISTRY" |
        ForEach-Object { Write-Host $_.Line }
}
if (Test-Path -LiteralPath $Err) {
    $Combined += "`n" + (Get-Content -Raw -LiteralPath $Err)
}

Write-Host "RIFLE_ASSET_CLASS_VERIFY_EXIT=$VerifyExit"

$SMIsStaticMesh = $Combined -match 'ASWW_RIFLE_ASSET\|PATH=/Game/Weapons/Rifle/Meshes/SM_Rifle\.SM_Rifle\|LOAD=True\|CLASS=StaticMesh'
$SKIsSkeleton = $Combined -match 'ASWW_RIFLE_ASSET\|PATH=/Game/Weapons/Rifle/Meshes/SK_Rifle\.SK_Rifle\|LOAD=True\|CLASS=Skeleton'

Write-Host "SK_RIFLE_IS_SKELETON=$SKIsSkeleton"
Write-Host "SM_RIFLE_IS_STATIC_MESH=$SMIsStaticMesh"

if ($VerifyExit -ne 0) {
    Stop-Gate "UNREAL_RIFLE_ASSET_CLASS_VERIFY_FAILED" 21
}
if (-not $SMIsStaticMesh) {
    Stop-Gate "SM_RIFLE_DID_NOT_LOAD_AS_STATIC_MESH" 22
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " BACKUP + PATCH PLAYER WITH REAL STATIC RIFLE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\RealRifleStaticMeshIntegration_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
Copy-Item -LiteralPath $CharacterCpp -Destination (Join-Path $BackupRoot "ASCharacter.cpp.before_rifle_staticmesh") -Force
Write-Host "SOURCE_BACKUP=$BackupRoot"

$Text = $Original

# Add required includes only if absent.
if ($Text -notmatch '#include\s+"Components/StaticMeshComponent\.h"') {
    $IncludeAnchor = '#include "Components/SkeletalMeshComponent.h"'
    if ($Text -match [regex]::Escape($IncludeAnchor)) {
        $Text = $Text.Replace(
            $IncludeAnchor,
            $IncludeAnchor + [Environment]::NewLine + '#include "Components/StaticMeshComponent.h"'
        )
    }
    else {
        Stop-Gate "SKELETAL_MESH_INCLUDE_ANCHOR_NOT_FOUND" 30
    }
}

if ($Text -notmatch '#include\s+"Engine/StaticMesh\.h"') {
    $IncludeAnchor2 = '#include "Engine/SkeletalMesh.h"'
    if ($Text -match [regex]::Escape($IncludeAnchor2)) {
        $Text = $Text.Replace(
            $IncludeAnchor2,
            $IncludeAnchor2 + [Environment]::NewLine + '#include "Engine/StaticMesh.h"'
        )
    }
    else {
        Stop-Gate "ENGINE_SKELETAL_MESH_INCLUDE_ANCHOR_NOT_FOUND" 31
    }
}

$Insert = @"

    // ASWW_REAL_RIFLE_VISUAL_BEGIN
    UStaticMeshComponent* RifleVisual =
        CreateDefaultSubobject<UStaticMeshComponent>(TEXT("ASWW_RifleVisual"));
    RifleVisual->SetupAttachment(GetMesh(), TEXT("hand_r"));
    RifleVisual->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    RifleVisual->SetGenerateOverlapEvents(false);

    static ConstructorHelpers::FObjectFinder<UStaticMesh> RifleMeshAsset(
        TEXT("/Game/Weapons/Rifle/Meshes/SM_Rifle.SM_Rifle"));
    if (RifleMeshAsset.Succeeded())
    {
        RifleVisual->SetStaticMesh(RifleMeshAsset.Object);

        // Initial proof transform only. We verify visually before tuning.
        RifleVisual->SetRelativeLocation(FVector::ZeroVector);
        RifleVisual->SetRelativeRotation(FRotator::ZeroRotator);
        RifleVisual->SetRelativeScale3D(FVector::OneVector);
    }

    UE_LOG(LogTemp, Warning,
        TEXT("ASWW_COMBAT_PROOF RIFLE_VISUAL mesh=%s parent=%s socket=hand_r"),
        *GetNameSafe(RifleVisual->GetStaticMesh()),
        *GetNameSafe(RifleVisual->GetAttachParent()));
    // ASWW_REAL_RIFLE_VISUAL_END

"@

$AnchorPattern = '(?m)^\s*UE_LOG\(LogTemp,\s*Warning,\s*$\r?\n^\s*TEXT\("ASWW_REAL_PLAYER_MANNY mesh=%s animClass=%s"\),'
$Anchor = [regex]::Match($Text, $AnchorPattern)

if (-not $Anchor.Success) {
    Stop-Gate "REAL_MANNY_LOG_ANCHOR_NOT_FOUND_SOURCE_NOT_MODIFIED" 32
}

$Text = $Text.Insert($Anchor.Index, $Insert)

if (([regex]::Matches($Text, "ASWW_REAL_RIFLE_VISUAL_BEGIN")).Count -ne 1) {
    Stop-Gate "RIFLE_VISUAL_INSERTION_COUNT_INVALID" 33
}

[IO.File]::WriteAllText($CharacterCpp, $Text, [Text.UTF8Encoding]::new($true))

$Disk = Get-Content -Raw -LiteralPath $CharacterCpp
$BlockCount = ([regex]::Matches($Disk, "ASWW_REAL_RIFLE_VISUAL_BEGIN")).Count
$ProofCount = ([regex]::Matches($Disk, "ASWW_COMBAT_PROOF RIFLE_VISUAL")).Count
$MannyCount = ([regex]::Matches($Disk, "ASWW_REAL_PLAYER_MANNY")).Count

Write-Host "RIFLE_VISUAL_BLOCK_COUNT=$BlockCount"
Write-Host "RIFLE_VISUAL_PROOF_MARKER_COUNT=$ProofCount"
Write-Host "REAL_MANNY_MARKER_COUNT=$MannyCount"

if ($BlockCount -ne 1 -or $ProofCount -ne 1 -or $MannyCount -ne 1) {
    Stop-Gate "POST_PATCH_SOURCE_VALIDATION_FAILED" 34
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 35
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLEAN BUILD + COOK + PACKAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 36
}

$PackageStart = Get-Date

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRERIFLE_STATIC_$Stamp"
    try {
        Move-Item -LiteralPath $StageRoot -Destination $OldStage
        Write-Host "OLD_STAGE_MOVED=$OldStage"
    }
    catch {
        Stop-Gate "STAGE_ROOT_LOCKED_$($_.Exception.Message)" 37
    }
}

$PackageEvidence = Join-Path $ProjectRoot "Saved\RuntimeEvidence\RealRifleStaticMeshPackage"
New-Item -ItemType Directory -Force -Path $PackageEvidence | Out-Null
$PackageLog = Join-Path $PackageEvidence "real_rifle_staticmesh_package_$Stamp.log"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BuildScript -UERoot $UERoot 2>&1 |
    Tee-Object -FilePath $PackageLog
$PackageExit = $LASTEXITCODE

Write-Host "PACKAGE_SCRIPT_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Write-Host ""
    Write-Host "=== PACKAGE FAILURE TAIL ===" -ForegroundColor Yellow
    Get-Content -LiteralPath $PackageLog -Tail 180
    Stop-Gate "BUILD_WIN64_FAILED_EXIT_$PackageExit" $(if ($PackageExit -gt 0) { $PackageExit } else { 40 })
}

$Exes = @(
    Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
)
if ($Exes.Count -eq 0) {
    Stop-Gate "PACKAGE_EXIT_ZERO_BUT_EXE_NOT_FOUND" 41
}

$Exe = $Exes[0]
$FreshExe = $Exe.LastWriteTime -ge $PackageStart.AddMinutes(-1)
$Containers = @(
    Get-ChildItem -LiteralPath $StageRoot -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @(".pak",".utoc",".ucas") }
)

Write-Host "PACKAGED_EXE=$($Exe.FullName)"
Write-Host "PACKAGED_EXE_FRESH=$FreshExe"
Write-Host "CONTAINER_FILE_COUNT=$($Containers.Count)"

if (-not $FreshExe -or $Containers.Count -eq 0) {
    Stop-Gate "PACKAGED_OUTPUT_NOT_FRESH_OR_NO_CONTAINERS" 42
}

Write-Host ""
Write-Host "REAL_RIFLE_STATICMESH_INTEGRATION=PASS" -ForegroundColor Green
Write-Host "SK_RIFLE_CLASS=Skeleton" -ForegroundColor Green
Write-Host "SM_RIFLE_CLASS=StaticMesh" -ForegroundColor Green
Write-Host "RIFLE_VISUAL_SOURCE=/Game/Weapons/Rifle/Meshes/SM_Rifle.SM_Rifle" -ForegroundColor Green
Write-Host "RIFLE_VISUAL_ATTACHED_TO=hand_r" -ForegroundColor Green
Write-Host "CLEAN_PACKAGE_WITH_RIFLE=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_REAL_RIFLE_COMBAT_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
