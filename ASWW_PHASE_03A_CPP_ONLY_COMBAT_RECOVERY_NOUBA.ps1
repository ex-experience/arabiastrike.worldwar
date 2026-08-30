[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$StageRoot = "D:\ASWW_STAGE",
    [string]$ArchiveRoot = "D:\ASWW_ARCHIVE\CombatPlayerV1",
    [string]$Phase03BackupRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar\Saved\Verification\CombatPlayerV1_20260829_024216"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_03A_CPP_ONLY_COMBAT_RECOVERY=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Write-Utf8Bom([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($true))
}

function Invoke-AndLog([string]$Exe, [string[]]$Args, [string]$LogPath) {
    Write-Host "COMMAND=$Exe $($Args -join ' ')"
    & $Exe @Args 2>&1 | Tee-Object -FilePath $LogPath
    return $LASTEXITCODE
}

Set-Location $ProjectRoot
$env:GIT_PAGER = "cat"

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$V2H = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Player\ASPlayerCharacterV2.h"
$V2Cpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASPlayerCharacterV2.cpp"
$BackupH = Join-Path $Phase03BackupRoot "ASPlayerCharacterV2.h.before_combat_v1"
$BackupCpp = Join-Path $Phase03BackupRoot "ASPlayerCharacterV2.cpp.before_combat_v1"

$BuildBat = Join-Path $UERoot "Engine\Build\BatchFiles\Build.bat"
$RunUAT = Join-Path $UERoot "Engine\Build\BatchFiles\RunUAT.bat"

foreach ($Required in @($ProjectFile,$V2H,$V2Cpp,$BackupH,$BackupCpp,$BuildBat,$RunUAT)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\CombatPlayerV1CppOnly_$Stamp"
$RecoveryBackup = Join-Path $ProjectRoot "Saved\Verification\CombatPlayerV1CppOnly_$Stamp"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
New-Item -ItemType Directory -Force -Path $RecoveryBackup | Out-Null

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " BACKUP CURRENT BROKEN V2 FILES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Copy-Item -LiteralPath $V2H -Destination (Join-Path $RecoveryBackup "ASPlayerCharacterV2.h.before_cpp_only_recovery") -Force
Copy-Item -LiteralPath $V2Cpp -Destination (Join-Path $RecoveryBackup "ASPlayerCharacterV2.cpp.before_cpp_only_recovery") -Force
Write-Host "RECOVERY_BACKUP=$RecoveryBackup"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RESTORE EXACT PRE-PHASE03 V2 HEADER + SOURCE FROM LOCAL BACKUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Copy-Item -LiteralPath $BackupH -Destination $V2H -Force
Copy-Item -LiteralPath $BackupCpp -Destination $V2Cpp -Force

$BackupHeaderHash = (Get-FileHash -LiteralPath $BackupH -Algorithm SHA256).Hash
$RestoredHeaderHash = (Get-FileHash -LiteralPath $V2H -Algorithm SHA256).Hash
$BackupSourceHash = (Get-FileHash -LiteralPath $BackupCpp -Algorithm SHA256).Hash
$RestoredSourceHash = (Get-FileHash -LiteralPath $V2Cpp -Algorithm SHA256).Hash

Write-Host "HEADER_RESTORED_EXACT=$($BackupHeaderHash -eq $RestoredHeaderHash)"
Write-Host "SOURCE_RESTORED_EXACT=$($BackupSourceHash -eq $RestoredSourceHash)"

if ($BackupHeaderHash -ne $RestoredHeaderHash -or $BackupSourceHash -ne $RestoredSourceHash) {
    Stop-Gate "LOCAL_BACKUP_RESTORE_HASH_MISMATCH" 12
}

$Header = Get-Content -Raw -LiteralPath $V2H
$Source = Get-Content -Raw -LiteralPath $V2Cpp

if ($Header -match "ASWW_COMBAT_PLAYER_V1_BEGIN") {
    Stop-Gate "PRE_PHASE03_HEADER_UNEXPECTEDLY_CONTAINS_COMBAT_MARKER" 13
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " APPLY COMBAT PLAYER V1 IN CPP ONLY — HEADER REMAINS UNTOUCHED" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Required C++ includes only.
$IncludeAnchor = '#include "Components/CapsuleComponent.h"'
if ($Source -notmatch '#include "Components/SkeletalMeshComponent.h"') {
    if ($Source -notmatch [regex]::Escape($IncludeAnchor)) {
        Stop-Gate "CAPSULE_INCLUDE_ANCHOR_NOT_FOUND" 20
    }

    $Source = $Source.Replace(
        $IncludeAnchor,
        $IncludeAnchor + "`r`n" +
        '#include "Components/SkeletalMeshComponent.h"' + "`r`n" +
        '#include "Engine/SkeletalMesh.h"' + "`r`n" +
        '#include "UObject/ConstructorHelpers.h"'
    )
}

# Use the verified third-person rifle AnimBP, but preserve Player V2's own
# movement, input, camera and gameplay methods.
$UnarmedPath = 'TEXT("/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed")'
$RifleABPPath = 'TEXT("/Game/Variant_Shooter/Anims/ABP_TP_Rifle")'

if ($Source -notmatch [regex]::Escape($UnarmedPath)) {
    Stop-Gate "PROVEN_UNARMED_BASELINE_PATH_NOT_FOUND_IN_PRE_PHASE03_SOURCE" 21
}
$Source = $Source.Replace($UnarmedPath, $RifleABPPath)

# Create the rifle as a default subobject using a local pointer.
# This deliberately adds ZERO reflected declarations to the header.
$CtorNeedle = "PrimaryActorTick.bCanEverTick = true;"
if ($Source -notmatch [regex]::Escape($CtorNeedle)) {
    Stop-Gate "V2_CONSTRUCTOR_TICK_MARKER_NOT_FOUND" 22
}

$CtorBlock = @'
PrimaryActorTick.bCanEverTick = true;

    // ASWW_COMBAT_PLAYER_V1_CPP_ONLY_BEGIN
    static ConstructorHelpers::FObjectFinder<USkeletalMesh> TacticalRifleAsset(
        TEXT("/Game/Weapons/Rifle/Meshes/SKM_Rifle.SKM_Rifle"));

    USkeletalMeshComponent* TacticalRifleMesh =
        CreateDefaultSubobject<USkeletalMeshComponent>(TEXT("ASWW_TacticalRifleMesh"));

    TacticalRifleMesh->SetupAttachment(GetMesh(), TEXT("HandGrip_R"));
    TacticalRifleMesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    TacticalRifleMesh->SetGenerateOverlapEvents(false);
    TacticalRifleMesh->SetRelativeLocation(FVector::ZeroVector);
    TacticalRifleMesh->SetRelativeRotation(FRotator::ZeroRotator);
    TacticalRifleMesh->SetRelativeScale3D(FVector(1.f));

    if (TacticalRifleAsset.Succeeded())
    {
        TacticalRifleMesh->SetSkeletalMeshAsset(TacticalRifleAsset.Object);
    }

    DefaultCameraFOV = 88.f;
    ADSCameraFOV = 68.f;
    CameraArmLength = 285.f;

    if (CameraBoom)
    {
        CameraBoom->TargetArmLength = CameraArmLength;
        CameraBoom->SocketOffset = FVector(0.f, 55.f, 52.f);
        CameraBoom->bEnableCameraLag = true;
        CameraBoom->CameraLagSpeed = 14.f;
        CameraBoom->bEnableCameraRotationLag = true;
        CameraBoom->CameraRotationLagSpeed = 18.f;
    }
    // ASWW_COMBAT_PLAYER_V1_CPP_ONLY_END
'@

$Source = $Source.Replace($CtorNeedle, $CtorBlock)

# Runtime marker does not need a component member in the header.
$BeginNeedle = "Super::BeginPlay();"
if ($Source -notmatch [regex]::Escape($BeginNeedle)) {
    Stop-Gate "V2_BEGINPLAY_SUPER_MARKER_NOT_FOUND" 23
}

$BeginBlock = @'
Super::BeginPlay();

    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_COMBAT_PLAYER_V1_CPP_ONLY anim=%s rifleSubobject=ASWW_TacticalRifleMesh socket=HandGrip_R"),
        *GetNameSafe(GetMesh() ? GetMesh()->GetAnimClass() : nullptr));
'@

$Source = $Source.Replace($BeginNeedle, $BeginBlock)

Write-Utf8Bom $V2Cpp $Source

# Re-hash header after source-only patch: it MUST still exactly equal backup.
$HeaderHashAfterPatch = (Get-FileHash -LiteralPath $V2H -Algorithm SHA256).Hash
$HeaderUntouched = $HeaderHashAfterPatch -eq $BackupHeaderHash

$SourceDisk = Get-Content -Raw -LiteralPath $V2Cpp

Write-Host "HEADER_UNTOUCHED_FROM_PRE_PHASE03=$HeaderUntouched"
Write-Host "CPP_ONLY_COMBAT_MARKER=$($SourceDisk -match 'ASWW_COMBAT_PLAYER_V1_CPP_ONLY_BEGIN')"
Write-Host "TP_RIFLE_ABP_SELECTED=$($SourceDisk -match '/Game/Variant_Shooter/Anims/ABP_TP_Rifle')"
Write-Host "SKM_RIFLE_SELECTED=$($SourceDisk -match '/Game/Weapons/Rifle/Meshes/SKM_Rifle')"
Write-Host "HANDGRIP_R_ATTACH=$($SourceDisk -match 'SetupAttachment\(GetMesh\(\), TEXT\("HandGrip_R"\)\)')"
Write-Host "SHOULDER_CAMERA=$($SourceDisk -match 'SocketOffset = FVector\(0\.f, 55\.f, 52\.f\)')"
Write-Host "ADS_FOV=$($SourceDisk -match 'ADSCameraFOV = 68\.f')"

if (-not $HeaderUntouched) {
    Stop-Gate "HEADER_CHANGED_DURING_CPP_ONLY_PATCH" 24
}

if ($SourceDisk -notmatch "ASWW_COMBAT_PLAYER_V1_CPP_ONLY_BEGIN") {
    Stop-Gate "CPP_ONLY_COMBAT_MARKER_MISSING" 25
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 26
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLOSE ACTIVE UE/GAME PROCESSES GATE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 27
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REAL EDITOR BUILD — SERIAL / NO UBA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$EditorLog = Join-Path $EvidenceRoot "editor_build_no_uba.log"
$EditorArgs = @(
    "ArabiaStrikeWorldWarEditor"
    "Win64"
    "Development"
    "-Project=$ProjectFile"
    "-WaitMutex"
    "-NoHotReloadFromIDE"
    "-MaxParallelActions=1"
    "-NoUBA"
)

$EditorExit = Invoke-AndLog $BuildBat $EditorArgs $EditorLog
Write-Host "EDITOR_BUILD_EXIT=$EditorExit"

if ($EditorExit -ne 0) {
    Write-Host "=== EDITOR BUILD FAILURE TAIL ===" -ForegroundColor Yellow
    Get-Content -LiteralPath $EditorLog -Tail 260
    $StopCode = 30
    if ($EditorExit -gt 0) { $StopCode = $EditorExit }
    Stop-Gate "EDITOR_BUILD_FAILED_EXIT_$EditorExit" $StopCode
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REAL GAME BUILD — SERIAL / NO UBA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$GameLog = Join-Path $EvidenceRoot "game_build_no_uba.log"
$GameArgs = @(
    "ArabiaStrikeWorldWar"
    "Win64"
    "Development"
    "-Project=$ProjectFile"
    "-WaitMutex"
    "-MaxParallelActions=1"
    "-NoUBA"
)

$GameExit = Invoke-AndLog $BuildBat $GameArgs $GameLog
Write-Host "GAME_BUILD_EXIT=$GameExit"

if ($GameExit -ne 0) {
    Write-Host "=== GAME BUILD FAILURE TAIL ===" -ForegroundColor Yellow
    Get-Content -LiteralPath $GameLog -Tail 260
    $StopCode = 31
    if ($GameExit -gt 0) { $StopCode = $GameExit }
    Stop-Gate "GAME_BUILD_FAILED_EXIT_$GameExit" $StopCode
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COOK + STAGE + PAK + PACKAGE — NO BUILD STEP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRE_CPP_ONLY_COMBAT_$Stamp"
    try {
        Move-Item -LiteralPath $StageRoot -Destination $OldStage
        Write-Host "OLD_STAGE_MOVED=$OldStage"
    }
    catch {
        Stop-Gate "STAGE_ROOT_LOCKED_$($_.Exception.Message)" 32
    }
}

New-Item -ItemType Directory -Force -Path $ArchiveRoot | Out-Null

$PackageLog = Join-Path $EvidenceRoot "cook_stage_package.log"
$UATArgs = @(
    "BuildCookRun"
    "-project=$ProjectFile"
    "-noP4"
    "-platform=Win64"
    "-clientconfig=Development"
    "-cook"
    "-stage"
    "-stagingdirectory=$StageRoot"
    "-pak"
    "-package"
    "-archive"
    "-archivedirectory=$ArchiveRoot"
    "-utf8output"
)

$PackageStart = Get-Date
$PackageExit = Invoke-AndLog $RunUAT $UATArgs $PackageLog
Write-Host "PACKAGE_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Write-Host "=== PACKAGE FAILURE TAIL ===" -ForegroundColor Yellow
    Get-Content -LiteralPath $PackageLog -Tail 320
    $StopCode = 32
    if ($PackageExit -gt 0) { $StopCode = $PackageExit }
    Stop-Gate "COOK_STAGE_PACKAGE_FAILED_EXIT_$PackageExit" $StopCode
}

$Exes = @(
    Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
)

if ($Exes.Count -eq 0) {
    Stop-Gate "PACKAGE_EXIT_ZERO_BUT_EXE_NOT_FOUND" 33
}

$Exe = $Exes[0]
$FreshExe = $Exe.LastWriteTime -ge $PackageStart.AddMinutes(-2)

Write-Host "PACKAGED_EXE=$($Exe.FullName)"
Write-Host "PACKAGED_EXE_FRESH=$FreshExe"

if (-not $FreshExe) {
    Stop-Gate "PACKAGED_EXE_NOT_FRESH" 34
}

Write-Host ""
Write-Host "PHASE_03A_CPP_ONLY_COMBAT_RECOVERY=PASS" -ForegroundColor Green
Write-Host "V2_HEADER=RESTORED_EXACT_AND_UNTOUCHED" -ForegroundColor Green
Write-Host "COMBAT_PATCH=CPP_ONLY" -ForegroundColor Green
Write-Host "EDITOR_BUILD_NO_UBA=PASS" -ForegroundColor Green
Write-Host "GAME_BUILD_NO_UBA=PASS" -ForegroundColor Green
Write-Host "COOK_STAGE_PACKAGE=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_PHASE_03B_COMBAT_PLAYER_V1_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
