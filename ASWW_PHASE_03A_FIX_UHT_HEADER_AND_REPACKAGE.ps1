[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$StageRoot = "D:\ASWW_STAGE",
    [string]$Phase03BackupRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar\Saved\Verification\CombatPlayerV1_20260829_024216"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_03A_UHT_REPAIR=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Write-Utf8Bom([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($true))
}

Set-Location $ProjectRoot
$env:GIT_PAGER = "cat"

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

$BuildScript = Join-Path $ProjectRoot "BuildScripts\build_win64.ps1"
$V2H = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Player\ASPlayerCharacterV2.h"
$V2Cpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASPlayerCharacterV2.cpp"

$BackupH = Join-Path $Phase03BackupRoot "ASPlayerCharacterV2.h.before_combat_v1"
$BackupCpp = Join-Path $Phase03BackupRoot "ASPlayerCharacterV2.cpp.before_combat_v1"

foreach ($Required in @($BuildScript,$V2H,$V2Cpp,$BackupH,$BackupCpp)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CONFIRM CURRENT UHT FAILURE SHAPE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$BrokenHeader = Get-Content -Raw -LiteralPath $V2H
$BrokenSource = Get-Content -Raw -LiteralPath $V2Cpp

$CurrentHeaderMarker = $BrokenHeader -match "ASWW_COMBAT_PLAYER_V1_BEGIN"
$CurrentSourceMarker = $BrokenSource -match "ASWW_COMBAT_PLAYER_V1_BEGIN"

Write-Host "CURRENT_HEADER_COMBAT_MARKER=$CurrentHeaderMarker"
Write-Host "CURRENT_SOURCE_COMBAT_MARKER=$CurrentSourceMarker"

if (-not ($CurrentHeaderMarker -and $CurrentSourceMarker)) {
    Stop-Gate "CURRENT_FILES_DO_NOT_MATCH_PHASE03A_BROKEN_PATCH_SHAPE" 12
}

$InlineUFunction = $BrokenHeader -match 'UFUNCTION\(BlueprintPure[^)]*\)[\s\S]{0,300}GetTacticalRifleMesh\(\)\s+const\s*\{'
Write-Host "INLINE_UFUNCTION_GETTER_DETECTED=$InlineUFunction"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PRECISE LOCAL RECOVERY FROM PHASE03A BACKUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$RepairBackup = Join-Path $ProjectRoot "Saved\Verification\CombatPlayerV1_UHTRepair_$Stamp"
New-Item -ItemType Directory -Force -Path $RepairBackup | Out-Null

Copy-Item -LiteralPath $V2H -Destination (Join-Path $RepairBackup "ASPlayerCharacterV2.h.broken") -Force
Copy-Item -LiteralPath $V2Cpp -Destination (Join-Path $RepairBackup "ASPlayerCharacterV2.cpp.broken") -Force

# Restore ONLY the two V2 files from the explicit local pre-Phase03A backup.
# No git restore/reset/checkout is used.
Copy-Item -LiteralPath $BackupH -Destination $V2H -Force
Copy-Item -LiteralPath $BackupCpp -Destination $V2Cpp -Force

Write-Host "RECOVERED_FROM_LOCAL_BACKUP=$Phase03BackupRoot"
Write-Host "REPAIR_BACKUP=$RepairBackup"

$Header = Get-Content -Raw -LiteralPath $V2H
$Source = Get-Content -Raw -LiteralPath $V2Cpp

if ($Header -match "ASWW_COMBAT_PLAYER_V1_BEGIN" -or $Source -match "ASWW_COMBAT_PLAYER_V1_BEGIN") {
    Stop-Gate "PRE_PHASE03_BACKUP_ALREADY_CONTAINS_COMBAT_MARKER" 13
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " APPLY UHT-SAFE COMBAT PLAYER V1 PATCH" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if ($Header -notmatch "class USkeletalMeshComponent;") {
    $GeneratedInclude = '#include "ASPlayerCharacterV2.generated.h"'
    if ($Header -notmatch [regex]::Escape($GeneratedInclude)) {
        Stop-Gate "GENERATED_HEADER_INCLUDE_NOT_FOUND" 20
    }
    $Header = $Header.Replace(
        $GeneratedInclude,
        $GeneratedInclude + "`r`n`r`nclass USkeletalMeshComponent;"
    )
}

$HeaderBlock = @'

    // ASWW_COMBAT_PLAYER_V1_BEGIN
    UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category="ASWW|Combat Player")
    TObjectPtr<USkeletalMeshComponent> TacticalRifleMesh;

    UFUNCTION(BlueprintPure, Category="ASWW|Combat Player")
    USkeletalMeshComponent* GetTacticalRifleMesh() const;
    // ASWW_COMBAT_PLAYER_V1_END
'@

$ClassEnd = $Header.LastIndexOf("};")
if ($ClassEnd -lt 0) {
    Stop-Gate "CLASS_TERMINATOR_NOT_FOUND_IN_V2_HEADER" 21
}
$Header = $Header.Insert($ClassEnd, $HeaderBlock)

if ($Source -notmatch '#include "Components/SkeletalMeshComponent.h"') {
    $CapsuleInclude = '#include "Components/CapsuleComponent.h"'
    if ($Source -notmatch [regex]::Escape($CapsuleInclude)) {
        Stop-Gate "CAPSULE_INCLUDE_NOT_FOUND_IN_V2_SOURCE" 22
    }

    $Source = $Source.Replace(
        $CapsuleInclude,
        $CapsuleInclude + "`r`n" +
        '#include "Components/SkeletalMeshComponent.h"' + "`r`n" +
        '#include "Engine/SkeletalMesh.h"'
    )
}

$UnarmedPath = 'TEXT("/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed")'
$RifleABPPath = 'TEXT("/Game/Variant_Shooter/Anims/ABP_TP_Rifle")'

if ($Source -notmatch [regex]::Escape($UnarmedPath)) {
    Stop-Gate "PROVEN_UNARMED_BASELINE_PATH_NOT_FOUND_IN_PRE_PHASE03_SOURCE" 23
}
$Source = $Source.Replace($UnarmedPath, $RifleABPPath)

$CtorNeedle = "PrimaryActorTick.bCanEverTick = true;"
if ($Source -notmatch [regex]::Escape($CtorNeedle)) {
    Stop-Gate "V2_CONSTRUCTOR_TICK_MARKER_NOT_FOUND" 24
}

$CtorBlock = @'
PrimaryActorTick.bCanEverTick = true;

    // ASWW_COMBAT_PLAYER_V1_BEGIN
    static ConstructorHelpers::FObjectFinder<USkeletalMesh> TacticalRifleAsset(
        TEXT("/Game/Weapons/Rifle/Meshes/SKM_Rifle.SKM_Rifle"));

    TacticalRifleMesh = CreateDefaultSubobject<USkeletalMeshComponent>(TEXT("TacticalRifleMesh"));
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
    // ASWW_COMBAT_PLAYER_V1_END
'@

$Source = $Source.Replace($CtorNeedle, $CtorBlock)

$BeginNeedle = "Super::BeginPlay();"
if ($Source -notmatch [regex]::Escape($BeginNeedle)) {
    Stop-Gate "V2_BEGINPLAY_SUPER_MARKER_NOT_FOUND" 25
}

$BeginBlock = @'
Super::BeginPlay();

    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_COMBAT_PLAYER_V1 anim=%s rifle=%s socket=HandGrip_R"),
        *GetNameSafe(GetMesh() ? GetMesh()->GetAnimClass() : nullptr),
        *GetNameSafe(TacticalRifleMesh ? TacticalRifleMesh->GetSkeletalMeshAsset() : nullptr));
'@

$Source = $Source.Replace($BeginNeedle, $BeginBlock)

# UFUNCTION is declaration-only in the header. Define it in cpp so UHT sees a
# normal reflected function declaration terminated by a semicolon.
$GetterDefinition = @'

USkeletalMeshComponent* AASPlayerCharacterV2::GetTacticalRifleMesh() const
{
    return TacticalRifleMesh;
}

'@

# Insert before the first normal V2 method following the constructor when possible.
$MethodMatches = [regex]::Matches(
    $Source,
    '(?m)^[A-Za-z_][A-Za-z0-9_:<>,\s*&]*\s+AASPlayerCharacterV2::[A-Za-z_][A-Za-z0-9_]*\s*\('
)

if ($MethodMatches.Count -lt 2) {
    # Safe fallback: append definition at EOF.
    $Source = $Source.TrimEnd() + "`r`n" + $GetterDefinition
}
else {
    $InsertAt = $MethodMatches[1].Index
    $Source = $Source.Insert($InsertAt, $GetterDefinition)
}

Write-Utf8Bom $V2H $Header
Write-Utf8Bom $V2Cpp $Source

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " POST-PATCH STRUCTURAL VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$HeaderDisk = Get-Content -Raw -LiteralPath $V2H
$SourceDisk = Get-Content -Raw -LiteralPath $V2Cpp

$HeaderHasTerminator = $HeaderDisk.TrimEnd().EndsWith("};")
$HeaderGetterDecl = $HeaderDisk -match 'UFUNCTION\(BlueprintPure[^)]*\)\s*[\r\n]+\s*USkeletalMeshComponent\*\s+GetTacticalRifleMesh\(\)\s+const\s*;'
$HeaderGetterInline = $HeaderDisk -match 'GetTacticalRifleMesh\(\)\s+const\s*\{'
$SourceGetterDef = $SourceDisk -match 'USkeletalMeshComponent\*\s+AASPlayerCharacterV2::GetTacticalRifleMesh\(\)\s+const\s*\{'
$CombatHeaderMarker = $HeaderDisk -match "ASWW_COMBAT_PLAYER_V1_BEGIN"
$CombatSourceMarker = $SourceDisk -match "ASWW_COMBAT_PLAYER_V1_BEGIN"
$RifleABP = $SourceDisk -match "/Game/Variant_Shooter/Anims/ABP_TP_Rifle"
$RifleMesh = $SourceDisk -match "/Game/Weapons/Rifle/Meshes/SKM_Rifle"
$RightGrip = $SourceDisk -match 'SetupAttachment\(GetMesh\(\), TEXT\("HandGrip_R"\)\)'

Write-Host "HEADER_CLASS_TERMINATOR_OK=$HeaderHasTerminator"
Write-Host "HEADER_GETTER_DECLARATION_ONLY=$HeaderGetterDecl"
Write-Host "HEADER_INLINE_GETTER_PRESENT=$HeaderGetterInline"
Write-Host "SOURCE_GETTER_DEFINITION=$SourceGetterDef"
Write-Host "COMBAT_MARKER_HEADER=$CombatHeaderMarker"
Write-Host "COMBAT_MARKER_SOURCE=$CombatSourceMarker"
Write-Host "TP_RIFLE_ABP_SELECTED=$RifleABP"
Write-Host "SKM_RIFLE_SELECTED=$RifleMesh"
Write-Host "HANDGRIP_R_ATTACH=$RightGrip"

if (-not $HeaderHasTerminator) {
    Stop-Gate "HEADER_DOES_NOT_END_WITH_CLASS_SEMICOLON" 26
}
if (-not $HeaderGetterDecl -or $HeaderGetterInline) {
    Stop-Gate "UHT_UNSAFE_GETTER_SHAPE_REMAINS" 27
}
if (-not ($SourceGetterDef -and $CombatHeaderMarker -and $CombatSourceMarker -and $RifleABP -and $RifleMesh -and $RightGrip)) {
    Stop-Gate "COMBAT_PATCH_POST_VERIFY_FAILED" 28
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 29
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REBUILD + COOK + PACKAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 30
}

$PackageStart = Get-Date

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRE_COMBAT_UHT_REPAIR_$Stamp"
    try {
        Move-Item -LiteralPath $StageRoot -Destination $OldStage
        Write-Host "OLD_STAGE_MOVED=$OldStage"
    }
    catch {
        Stop-Gate "STAGE_ROOT_LOCKED_$($_.Exception.Message)" 31
    }
}

$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\CombatPlayerV1UHTRepair"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$PackageLog = Join-Path $EvidenceRoot "combat_player_v1_uht_repair_package_$Stamp.log"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BuildScript -UERoot $UERoot 2>&1 |
    Tee-Object -FilePath $PackageLog
$PackageExit = $LASTEXITCODE

Write-Host "PACKAGE_SCRIPT_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Write-Host ""
    Write-Host "=== PACKAGE FAILURE TAIL ===" -ForegroundColor Yellow
    Get-Content -LiteralPath $PackageLog -Tail 260
    $StopCode = 32
    if ($PackageExit -gt 0) { $StopCode = $PackageExit }
    Stop-Gate "BUILD_WIN64_FAILED_EXIT_$PackageExit" $StopCode
}

$Exes = @(
    Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
)

if ($Exes.Count -eq 0) {
    Stop-Gate "PACKAGE_EXIT_ZERO_BUT_EXE_NOT_FOUND" 33
}

$Exe = $Exes[0]
$FreshExe = $Exe.LastWriteTime -ge $PackageStart.AddMinutes(-1)

Write-Host "PACKAGED_EXE=$($Exe.FullName)"
Write-Host "PACKAGED_EXE_FRESH=$FreshExe"

if (-not $FreshExe) {
    Stop-Gate "PACKAGED_EXE_NOT_FRESH" 34
}

Write-Host ""
Write-Host "PHASE_03A_UHT_REPAIR=PASS" -ForegroundColor Green
Write-Host "UHT_EOF_SEMICOLON_BLOCKER=FIXED" -ForegroundColor Green
Write-Host "COMBAT_PLAYER_V1_PATCH=REAPPLIED_UHT_SAFE" -ForegroundColor Green
Write-Host "BUILD_COOK_PACKAGE=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_PHASE_03B_COMBAT_PLAYER_V1_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
