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
    Write-Host "PHASE_01_PLAYER_FOUNDATION=STOPPED" -ForegroundColor Red
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

$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$BuildScript = Join-Path $ProjectRoot "BuildScripts\build_win64.ps1"
$GameModeCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Game\ASGameMode.cpp"
$CharacterCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"
$CharacterH = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Player\ASCharacter.h"
$InputIni = Join-Path $ProjectRoot "Config\DefaultInput.ini"

foreach ($Required in @($ProjectFile,$BuildScript,$GameModeCpp,$CharacterCpp,$CharacterH,$InputIni)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

$NewHeader = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Player\ASPlayerCharacterV2.h"
$NewCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASPlayerCharacterV2.cpp"

if ((Test-Path -LiteralPath $NewHeader) -or (Test-Path -LiteralPath $NewCpp)) {
    Stop-Gate "PLAYER_V2_FILES_ALREADY_EXIST_REVIEW_BEFORE_RERUN" 12
}

$GameModeText = Get-Content -Raw -LiteralPath $GameModeCpp
if ($GameModeText -notmatch 'DefaultPawnClass\s*=\s*AASCharacter::StaticClass\(\);') {
    Stop-Gate "EXPECTED_LEGACY_DEFAULT_PAWN_ASSIGNMENT_NOT_FOUND" 13
}

# We deliberately keep the existing AASCharacter intact. The new class inherits
# health/weapon/inventory/downed/respawn logic but owns the PC movement/input layer.
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\AAAPlayerFoundationV1_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

Copy-Item -LiteralPath $GameModeCpp -Destination (Join-Path $BackupRoot "ASGameMode.cpp.before_phase01") -Force
Copy-Item -LiteralPath $InputIni -Destination (Join-Path $BackupRoot "DefaultInput.ini.before_phase01") -Force
Copy-Item -LiteralPath $CharacterCpp -Destination (Join-Path $BackupRoot "ASCharacter.cpp.reference") -Force
Copy-Item -LiteralPath $CharacterH -Destination (Join-Path $BackupRoot "ASCharacter.h.reference") -Force

Write-Host "BACKUP_ROOT=$BackupRoot"

$Header = @'
#pragma once

#include "CoreMinimal.h"
#include "Player/ASCharacter.h"
#include "ASPlayerCharacterV2.generated.h"

UENUM(BlueprintType)
enum class EASMovementStance : uint8
{
    Standing UMETA(DisplayName="Standing"),
    Crouched UMETA(DisplayName="Crouched"),
    Prone UMETA(DisplayName="Prone"),
    Sliding UMETA(DisplayName="Sliding")
};

UENUM(BlueprintType)
enum class EASCombatReadyState : uint8
{
    Relaxed UMETA(DisplayName="Relaxed"),
    LowReady UMETA(DisplayName="Low Ready"),
    HighReady UMETA(DisplayName="High Ready"),
    ADS UMETA(DisplayName="ADS")
};

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASPlayerCharacterV2 : public AASCharacter
{
    GENERATED_BODY()

public:
    AASPlayerCharacterV2();

    virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;
    virtual void Tick(float DeltaSeconds) override;

    UFUNCTION(BlueprintPure, Category="ASWW|Player Foundation")
    EASMovementStance GetMovementStance() const { return MovementStance; }

    UFUNCTION(BlueprintPure, Category="ASWW|Player Foundation")
    EASCombatReadyState GetCombatReadyState() const { return CombatReadyState; }

    UFUNCTION(BlueprintPure, Category="ASWW|Player Foundation")
    bool IsAiming() const { return bAimHeld; }

    UFUNCTION(BlueprintPure, Category="ASWW|Player Foundation")
    bool IsSprintingV2() const { return bSprintHeldV2; }

protected:
    virtual void BeginPlay() override;

    void MoveForwardV2(float Value);
    void MoveRightV2(float Value);
    void TurnV2(float Value);
    void LookUpV2(float Value);

    void JumpOrMantlePressed();
    bool TryMantle();

    void SprintPressedV2();
    void SprintReleasedV2();
    void CrouchSlidePressed();
    void PronePressed();

    void AimPressed();
    void AimReleased();

    void FreeLookPressed();
    void FreeLookReleased();

    void CombatStancePressed();

    void FirePressedV2();
    void FireReleasedV2();
    void ReloadPressedV2();
    void InteractPressedV2();
    void VehicleInteractPressedV2();
    void GrenadePressedV2();
    void MeleePressedV2();
    void FireModePressedV2();

    void Weapon1PressedV2();
    void Weapon2PressedV2();
    void Weapon3PressedV2();
    void Weapon4PressedV2();

    void StartSlide();
    void StopSlide();
    void EnterProne();
    void ExitProne();
    void ExitCrouchIfNeeded();
    void UpdateMovementProfile();
    void UpdateCamera(float DeltaSeconds);

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Movement")
    float TacticalWalkSpeed = 360.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Movement")
    float CombatJogSpeed = 520.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Movement")
    float TacticalSprintSpeed = 760.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Movement")
    float CrouchMoveSpeed = 280.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Movement")
    float ProneMoveSpeed = 150.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Movement")
    float AimMoveSpeed = 340.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Slide")
    float SlideMinSpeed = 430.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Slide")
    float SlideImpulse = 520.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Slide")
    float SlideDuration = 0.65f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Prone")
    float ProneCapsuleHalfHeight = 44.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Mantle")
    float MantleForwardProbe = 95.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Mantle")
    float MantleLowHeight = 45.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Mantle")
    float MantleHighHeight = 125.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Camera")
    float DefaultCameraFOV = 90.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Camera")
    float ADSCameraFOV = 72.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Camera")
    float CameraFOVInterpSpeed = 12.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Camera")
    float CameraArmLength = 320.f;

    UPROPERTY(BlueprintReadOnly, Category="ASWW|Player Foundation")
    EASMovementStance MovementStance = EASMovementStance::Standing;

    UPROPERTY(BlueprintReadOnly, Category="ASWW|Player Foundation")
    EASCombatReadyState CombatReadyState = EASCombatReadyState::LowReady;

    bool bSprintHeldV2 = false;
    bool bAimHeld = false;
    bool bFreeLookHeld = false;

    float StandingCapsuleHalfHeight = 88.f;

    FTimerHandle SlideTimerHandle;
};
'@

$Cpp = @'
#include "Player/ASPlayerCharacterV2.h"

#include "Animation/AnimInstance.h"
#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/SpringArmComponent.h"
#include "Engine/World.h"
#include "TimerManager.h"
#include "UObject/ConstructorHelpers.h"

AASPlayerCharacterV2::AASPlayerCharacterV2()
{
    PrimaryActorTick.bCanEverTick = true;

    // Phase 01 intentionally restores the proven locomotion AnimBP.
    // Rifle pose/upper-body layering is introduced in Phase 02 instead of
    // replacing the entire locomotion state machine.
    static ConstructorHelpers::FClassFinder<UAnimInstance> ProvenLocomotionAnim(
        TEXT("/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed"));
    if (ProvenLocomotionAnim.Succeeded() && GetMesh())
    {
        GetMesh()->SetAnimInstanceClass(ProvenLocomotionAnim.Class);
    }

    if (UCharacterMovementComponent* Move = GetCharacterMovement())
    {
        Move->NavAgentProps.bCanCrouch = true;
        Move->MaxWalkSpeed = CombatJogSpeed;
        Move->MaxWalkSpeedCrouched = CrouchMoveSpeed;
        Move->AirControl = 0.32f;
        Move->BrakingDecelerationWalking = 1700.f;
        Move->GroundFriction = 7.5f;
        Move->JumpZVelocity = 520.f;
        Move->bOrientRotationToMovement = false;
    }

    bUseControllerRotationYaw = true;

    if (CameraBoom)
    {
        CameraBoom->TargetArmLength = CameraArmLength;
        CameraBoom->bUsePawnControlRotation = true;
    }

    if (FollowCamera)
    {
        FollowCamera->SetFieldOfView(DefaultCameraFOV);
    }
}

void AASPlayerCharacterV2::BeginPlay()
{
    Super::BeginPlay();

    if (UCapsuleComponent* Capsule = GetCapsuleComponent())
    {
        StandingCapsuleHalfHeight = Capsule->GetUnscaledCapsuleHalfHeight();
    }

    UpdateMovementProfile();
}

void AASPlayerCharacterV2::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    UpdateCamera(DeltaSeconds);
}

void AASPlayerCharacterV2::SetupPlayerInputComponent(UInputComponent* Input)
{
    // Bypass AASCharacter's legacy binding table so Phase 01 owns the complete
    // PC control schema without duplicate action handlers.
    ACharacter::SetupPlayerInputComponent(Input);

    check(Input);

    Input->BindAxis("MoveForward", this, &AASPlayerCharacterV2::MoveForwardV2);
    Input->BindAxis("MoveRight", this, &AASPlayerCharacterV2::MoveRightV2);
    Input->BindAxis("Turn", this, &AASPlayerCharacterV2::TurnV2);
    Input->BindAxis("LookUp", this, &AASPlayerCharacterV2::LookUpV2);

    Input->BindAction("Jump", IE_Pressed, this, &AASPlayerCharacterV2::JumpOrMantlePressed);

    Input->BindAction("Sprint", IE_Pressed, this, &AASPlayerCharacterV2::SprintPressedV2);
    Input->BindAction("Sprint", IE_Released, this, &AASPlayerCharacterV2::SprintReleasedV2);

    Input->BindAction("CrouchSlide", IE_Pressed, this, &AASPlayerCharacterV2::CrouchSlidePressed);
    Input->BindAction("Prone", IE_Pressed, this, &AASPlayerCharacterV2::PronePressed);

    Input->BindAction("Aim", IE_Pressed, this, &AASPlayerCharacterV2::AimPressed);
    Input->BindAction("Aim", IE_Released, this, &AASPlayerCharacterV2::AimReleased);

    Input->BindAction("FreeLook", IE_Pressed, this, &AASPlayerCharacterV2::FreeLookPressed);
    Input->BindAction("FreeLook", IE_Released, this, &AASPlayerCharacterV2::FreeLookReleased);

    Input->BindAction("CombatStance", IE_Pressed, this, &AASPlayerCharacterV2::CombatStancePressed);

    Input->BindAction("Fire", IE_Pressed, this, &AASPlayerCharacterV2::FirePressedV2);
    Input->BindAction("Fire", IE_Released, this, &AASPlayerCharacterV2::FireReleasedV2);
    Input->BindAction("Reload", IE_Pressed, this, &AASPlayerCharacterV2::ReloadPressedV2);
    Input->BindAction("Interact", IE_Pressed, this, &AASPlayerCharacterV2::InteractPressedV2);
    Input->BindAction("VehicleInteract", IE_Pressed, this, &AASPlayerCharacterV2::VehicleInteractPressedV2);
    Input->BindAction("Grenade", IE_Pressed, this, &AASPlayerCharacterV2::GrenadePressedV2);
    Input->BindAction("Melee", IE_Pressed, this, &AASPlayerCharacterV2::MeleePressedV2);
    Input->BindAction("FireMode", IE_Pressed, this, &AASPlayerCharacterV2::FireModePressedV2);

    Input->BindAction("Weapon1", IE_Pressed, this, &AASPlayerCharacterV2::Weapon1PressedV2);
    Input->BindAction("Weapon2", IE_Pressed, this, &AASPlayerCharacterV2::Weapon2PressedV2);
    Input->BindAction("Weapon3", IE_Pressed, this, &AASPlayerCharacterV2::Weapon3PressedV2);
    Input->BindAction("Weapon4", IE_Pressed, this, &AASPlayerCharacterV2::Weapon4PressedV2);
}

void AASPlayerCharacterV2::MoveForwardV2(float Value)
{
    if (!Controller || FMath::IsNearlyZero(Value) || IsDowned() || IsEliminated())
    {
        return;
    }

    const FRotator ControlRotation = Controller->GetControlRotation();
    const FRotator YawRotation(0.f, ControlRotation.Yaw, 0.f);
    const FVector Direction = FRotationMatrix(YawRotation).GetUnitAxis(EAxis::X);
    AddMovementInput(Direction, Value);
}

void AASPlayerCharacterV2::MoveRightV2(float Value)
{
    if (!Controller || FMath::IsNearlyZero(Value) || IsDowned() || IsEliminated())
    {
        return;
    }

    const FRotator ControlRotation = Controller->GetControlRotation();
    const FRotator YawRotation(0.f, ControlRotation.Yaw, 0.f);
    const FVector Direction = FRotationMatrix(YawRotation).GetUnitAxis(EAxis::Y);
    AddMovementInput(Direction, Value);
}

void AASPlayerCharacterV2::TurnV2(float Value)
{
    AddControllerYawInput(Value);
}

void AASPlayerCharacterV2::LookUpV2(float Value)
{
    AddControllerPitchInput(Value);
}

void AASPlayerCharacterV2::JumpOrMantlePressed()
{
    if (IsDowned() || IsEliminated())
    {
        return;
    }

    if (MovementStance == EASMovementStance::Prone)
    {
        ExitProne();
        return;
    }

    if (MovementStance == EASMovementStance::Crouched)
    {
        ExitCrouchIfNeeded();
    }

    if (!TryMantle())
    {
        Jump();
    }
}

bool AASPlayerCharacterV2::TryMantle()
{
    UWorld* World = GetWorld();
    UCapsuleComponent* Capsule = GetCapsuleComponent();
    if (!World || !Capsule || GetCharacterMovement()->IsFalling())
    {
        return false;
    }

    const FVector Forward = GetActorForwardVector();
    const FVector ActorLocation = GetActorLocation();
    const float Radius = Capsule->GetScaledCapsuleRadius();

    FCollisionQueryParams Params(SCENE_QUERY_STAT(ASWWMantle), false, this);

    FHitResult WallHit;
    const FVector WallStart = ActorLocation + FVector(0.f, 0.f, MantleLowHeight);
    const FVector WallEnd = WallStart + Forward * MantleForwardProbe;

    if (!World->LineTraceSingleByChannel(WallHit, WallStart, WallEnd, ECC_Visibility, Params))
    {
        return false;
    }

    FHitResult TopHit;
    const FVector TopStart = WallHit.ImpactPoint + Forward * (Radius + 8.f) + FVector(0.f, 0.f, MantleHighHeight);
    const FVector TopEnd = TopStart - FVector(0.f, 0.f, MantleHighHeight + 20.f);

    if (!World->LineTraceSingleByChannel(TopHit, TopStart, TopEnd, ECC_Visibility, Params))
    {
        return false;
    }

    const float ObstacleHeight = TopHit.ImpactPoint.Z - ActorLocation.Z;
    if (ObstacleHeight < 25.f || ObstacleHeight > MantleHighHeight)
    {
        return false;
    }

    const FVector Target = TopHit.ImpactPoint
        + Forward * (Radius + 18.f)
        + FVector(0.f, 0.f, Capsule->GetScaledCapsuleHalfHeight() + 4.f);

    FHitResult MoveHit;
    const bool bMoved = SetActorLocation(Target, true, &MoveHit, ETeleportType::None);
    if (bMoved)
    {
        GetCharacterMovement()->StopMovementImmediately();
    }
    return bMoved;
}

void AASPlayerCharacterV2::SprintPressedV2()
{
    if (IsDowned() || IsEliminated() || bAimHeld || MovementStance == EASMovementStance::Prone)
    {
        return;
    }

    bSprintHeldV2 = true;
    UpdateMovementProfile();
}

void AASPlayerCharacterV2::SprintReleasedV2()
{
    bSprintHeldV2 = false;
    UpdateMovementProfile();
}

void AASPlayerCharacterV2::CrouchSlidePressed()
{
    if (IsDowned() || IsEliminated())
    {
        return;
    }

    if (MovementStance == EASMovementStance::Prone)
    {
        ExitProne();
        Crouch();
        MovementStance = EASMovementStance::Crouched;
        UpdateMovementProfile();
        return;
    }

    const float Speed2D = GetVelocity().Size2D();
    if ((bSprintHeldV2 || Speed2D >= SlideMinSpeed) && MovementStance == EASMovementStance::Standing)
    {
        StartSlide();
        return;
    }

    if (MovementStance == EASMovementStance::Crouched)
    {
        UnCrouch();
        MovementStance = EASMovementStance::Standing;
    }
    else
    {
        Crouch();
        MovementStance = EASMovementStance::Crouched;
        bSprintHeldV2 = false;
    }

    UpdateMovementProfile();
}

void AASPlayerCharacterV2::PronePressed()
{
    if (IsDowned() || IsEliminated() || GetCharacterMovement()->IsFalling())
    {
        return;
    }

    if (MovementStance == EASMovementStance::Prone)
    {
        ExitProne();
    }
    else
    {
        EnterProne();
    }
}

void AASPlayerCharacterV2::AimPressed()
{
    if (IsDowned() || IsEliminated())
    {
        return;
    }

    bAimHeld = true;
    bSprintHeldV2 = false;
    CombatReadyState = EASCombatReadyState::ADS;
    UpdateMovementProfile();
}

void AASPlayerCharacterV2::AimReleased()
{
    bAimHeld = false;
    CombatReadyState = EASCombatReadyState::HighReady;
    UpdateMovementProfile();
}

void AASPlayerCharacterV2::FreeLookPressed()
{
    bFreeLookHeld = true;
    bUseControllerRotationYaw = false;
}

void AASPlayerCharacterV2::FreeLookReleased()
{
    bFreeLookHeld = false;
    bUseControllerRotationYaw = true;
}

void AASPlayerCharacterV2::CombatStancePressed()
{
    if (bAimHeld)
    {
        return;
    }

    switch (CombatReadyState)
    {
    case EASCombatReadyState::Relaxed:
        CombatReadyState = EASCombatReadyState::LowReady;
        break;
    case EASCombatReadyState::LowReady:
        CombatReadyState = EASCombatReadyState::HighReady;
        break;
    default:
        CombatReadyState = EASCombatReadyState::Relaxed;
        break;
    }
}

void AASPlayerCharacterV2::FirePressedV2()
{
    FirePressed();
}

void AASPlayerCharacterV2::FireReleasedV2()
{
    FireReleased();
}

void AASPlayerCharacterV2::ReloadPressedV2()
{
    Reload();
}

void AASPlayerCharacterV2::InteractPressedV2()
{
    Interact();
}

void AASPlayerCharacterV2::VehicleInteractPressedV2()
{
    // Vehicle enter/exit receives its own system in the vehicle phase.
    // Until then, F routes to the existing safe interaction trace.
    Interact();
}

void AASPlayerCharacterV2::GrenadePressedV2()
{
    ThrowGrenade();
}

void AASPlayerCharacterV2::MeleePressedV2()
{
    // Reserved for Phase 04 melee system. No fake damage is applied here.
}

void AASPlayerCharacterV2::FireModePressedV2()
{
    // Reserved for Phase 03 weapon fire-mode state.
}

void AASPlayerCharacterV2::Weapon1PressedV2()
{
    EquipSlot1();
}

void AASPlayerCharacterV2::Weapon2PressedV2()
{
    EquipSlot2();
}

void AASPlayerCharacterV2::Weapon3PressedV2()
{
    EquipSlot3();
}

void AASPlayerCharacterV2::Weapon4PressedV2()
{
    EquipSlot4();
}

void AASPlayerCharacterV2::StartSlide()
{
    if (MovementStance == EASMovementStance::Sliding || IsDowned() || IsEliminated())
    {
        return;
    }

    bSprintHeldV2 = false;
    MovementStance = EASMovementStance::Sliding;
    Crouch();

    const FVector SlideDirection = GetVelocity().SizeSquared2D() > 100.f
        ? GetVelocity().GetSafeNormal2D()
        : GetActorForwardVector();

    LaunchCharacter(SlideDirection * SlideImpulse, false, false);

    GetWorldTimerManager().ClearTimer(SlideTimerHandle);
    GetWorldTimerManager().SetTimer(
        SlideTimerHandle,
        this,
        &AASPlayerCharacterV2::StopSlide,
        FMath::Max(0.15f, SlideDuration),
        false);

    UpdateMovementProfile();
}

void AASPlayerCharacterV2::StopSlide()
{
    if (MovementStance != EASMovementStance::Sliding)
    {
        return;
    }

    MovementStance = EASMovementStance::Crouched;
    UpdateMovementProfile();
}

void AASPlayerCharacterV2::EnterProne()
{
    GetWorldTimerManager().ClearTimer(SlideTimerHandle);

    if (MovementStance == EASMovementStance::Crouched || MovementStance == EASMovementStance::Sliding)
    {
        UnCrouch();
    }

    if (UCapsuleComponent* Capsule = GetCapsuleComponent())
    {
        Capsule->SetCapsuleHalfHeight(
            FMath::Clamp(ProneCapsuleHalfHeight, Capsule->GetUnscaledCapsuleRadius() + 1.f, StandingCapsuleHalfHeight),
            true);
    }

    MovementStance = EASMovementStance::Prone;
    bSprintHeldV2 = false;
    UpdateMovementProfile();
}

void AASPlayerCharacterV2::ExitProne()
{
    if (UCapsuleComponent* Capsule = GetCapsuleComponent())
    {
        Capsule->SetCapsuleHalfHeight(StandingCapsuleHalfHeight, true);
    }

    MovementStance = EASMovementStance::Standing;
    UpdateMovementProfile();
}

void AASPlayerCharacterV2::ExitCrouchIfNeeded()
{
    if (MovementStance == EASMovementStance::Crouched || MovementStance == EASMovementStance::Sliding)
    {
        GetWorldTimerManager().ClearTimer(SlideTimerHandle);
        UnCrouch();
        MovementStance = EASMovementStance::Standing;
        UpdateMovementProfile();
    }
}

void AASPlayerCharacterV2::UpdateMovementProfile()
{
    UCharacterMovementComponent* Move = GetCharacterMovement();
    if (!Move)
    {
        return;
    }

    if (MovementStance == EASMovementStance::Prone)
    {
        Move->MaxWalkSpeed = ProneMoveSpeed;
        return;
    }

    if (MovementStance == EASMovementStance::Sliding)
    {
        Move->MaxWalkSpeed = TacticalSprintSpeed;
        return;
    }

    if (MovementStance == EASMovementStance::Crouched)
    {
        Move->MaxWalkSpeed = CrouchMoveSpeed;
        Move->MaxWalkSpeedCrouched = CrouchMoveSpeed;
        return;
    }

    if (bAimHeld)
    {
        Move->MaxWalkSpeed = AimMoveSpeed;
    }
    else if (bSprintHeldV2)
    {
        Move->MaxWalkSpeed = TacticalSprintSpeed;
    }
    else
    {
        Move->MaxWalkSpeed = CombatJogSpeed;
    }
}

void AASPlayerCharacterV2::UpdateCamera(float DeltaSeconds)
{
    if (!FollowCamera)
    {
        return;
    }

    const float TargetFOV = bAimHeld ? ADSCameraFOV : DefaultCameraFOV;
    const float NewFOV = FMath::FInterpTo(
        FollowCamera->FieldOfView,
        TargetFOV,
        DeltaSeconds,
        CameraFOVInterpSpeed);

    FollowCamera->SetFieldOfView(NewFOV);
}
'@

Write-Utf8Bom $NewHeader $Header
Write-Utf8Bom $NewCpp $Cpp

Write-Host "CREATED=$NewHeader"
Write-Host "CREATED=$NewCpp"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PROMOTE PLAYER V2 AS DEFAULT PAWN" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$GameModeNew = $GameModeText

if ($GameModeNew -notmatch '#include "Player/ASPlayerCharacterV2.h"') {
    $GameModeNew = $GameModeNew.Replace(
        '#include "Player/ASCharacter.h"',
        "#include `"Player/ASCharacter.h`"`r`n#include `"Player/ASPlayerCharacterV2.h`""
    )
}

$GameModeNew = [regex]::Replace(
    $GameModeNew,
    'DefaultPawnClass\s*=\s*AASCharacter::StaticClass\(\);',
    'DefaultPawnClass = AASPlayerCharacterV2::StaticClass();',
    1
)

if (([regex]::Matches($GameModeNew, 'DefaultPawnClass\s*=\s*AASPlayerCharacterV2::StaticClass\(\);')).Count -ne 1) {
    Stop-Gate "FAILED_TO_PROMOTE_PLAYER_V2_DEFAULT_PAWN" 20
}

Write-Utf8Bom $GameModeCpp $GameModeNew
Write-Host "DEFAULT_PAWN=AASPlayerCharacterV2"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " APPLY PC CONTROL SCHEMA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$InputText = Get-Content -Raw -LiteralPath $InputIni

$RequiredMappings = @(
    '+ActionMappings=(ActionName="Aim",bShift=False,bCtrl=False,bAlt=False,bCmd=False,Key=RightMouseButton)',
    '+ActionMappings=(ActionName="CrouchSlide",bShift=False,bCtrl=False,bAlt=False,bCmd=False,Key=LeftControl)',
    '+ActionMappings=(ActionName="Prone",bShift=False,bCtrl=False,bAlt=False,bCmd=False,Key=Z)',
    '+ActionMappings=(ActionName="Melee",bShift=False,bCtrl=False,bAlt=False,bCmd=False,Key=V)',
    '+ActionMappings=(ActionName="FireMode",bShift=False,bCtrl=False,bAlt=False,bCmd=False,Key=B)',
    '+ActionMappings=(ActionName="CombatStance",bShift=False,bCtrl=False,bAlt=False,bCmd=False,Key=C)',
    '+ActionMappings=(ActionName="FreeLook",bShift=False,bCtrl=False,bAlt=False,bCmd=False,Key=LeftAlt)',
    '+ActionMappings=(ActionName="VehicleInteract",bShift=False,bCtrl=False,bAlt=False,bCmd=False,Key=F)',
    '+ActionMappings=(ActionName="TacticalEquipment",bShift=False,bCtrl=False,bAlt=False,bCmd=False,Key=ThumbMouseButton)'
)

foreach ($Mapping in $RequiredMappings) {
    if ($InputText -notmatch [regex]::Escape($Mapping)) {
        if (-not $InputText.EndsWith("`n")) { $InputText += "`r`n" }
        $InputText += $Mapping + "`r`n"
    }
}

# Legacy Dash stays in the ini for compatibility with old pawn instances,
# but Player V2 does not bind it. Ctrl is now Crouch/Slide for the active pawn.
Write-Utf8Bom $InputIni $InputText

foreach ($Name in @("Aim","CrouchSlide","Prone","Melee","FireMode","CombatStance","FreeLook","VehicleInteract")) {
    $Seen = $InputText -match ('ActionName="' + [regex]::Escape($Name) + '"')
    Write-Host "INPUT_MAPPING_$($Name.ToUpper())=$Seen"
    if (-not $Seen) {
        Stop-Gate "INPUT_MAPPING_FAILED_$Name" 21
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " STATIC SAFETY CHECKS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$NewCppDisk = Get-Content -Raw -LiteralPath $NewCpp
$NewHeaderDisk = Get-Content -Raw -LiteralPath $NewHeader
$GameModeDisk = Get-Content -Raw -LiteralPath $GameModeCpp

$Checks = [ordered]@{
    PLAYER_V2_CLASS = $NewHeaderDisk -match 'class ARABIASTRIKEWORLDWAR_API AASPlayerCharacterV2'
    PROVEN_LOCOMOTION_RESTORED = $NewCppDisk -match '/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed'
    CROUCH_SLIDE_BOUND = $NewCppDisk -match 'BindAction\("CrouchSlide"'
    PRONE_BOUND = $NewCppDisk -match 'BindAction\("Prone"'
    AIM_BOUND = $NewCppDisk -match 'BindAction\("Aim"'
    FREE_LOOK_BOUND = $NewCppDisk -match 'BindAction\("FreeLook"'
    MANTLE_IMPLEMENTED = $NewCppDisk -match 'bool AASPlayerCharacterV2::TryMantle\(\)'
    CAMERA_ADS_FOV = $NewCppDisk -match 'ADSCameraFOV'
    DEFAULT_PAWN_V2 = $GameModeDisk -match 'DefaultPawnClass\s*=\s*AASPlayerCharacterV2::StaticClass\(\);'
}

foreach ($Pair in $Checks.GetEnumerator()) {
    Write-Host "$($Pair.Key)=$($Pair.Value)"
    if (-not $Pair.Value) {
        Stop-Gate "STATIC_CHECK_FAILED_$($Pair.Key)" 22
    }
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 23
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLEAN BUILD + COOK + PACKAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 24
}

$PackageStart = Get-Date

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRE_AAA_PHASE01_$Stamp"
    try {
        Move-Item -LiteralPath $StageRoot -Destination $OldStage
        Write-Host "OLD_STAGE_MOVED=$OldStage"
    }
    catch {
        Stop-Gate "STAGE_ROOT_LOCKED_$($_.Exception.Message)" 25
    }
}

$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\AAAPlayerFoundationV1"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$PackageLog = Join-Path $EvidenceRoot "aaa_phase01_package_$Stamp.log"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BuildScript -UERoot $UERoot 2>&1 |
    Tee-Object -FilePath $PackageLog
$PackageExit = $LASTEXITCODE

Write-Host "PACKAGE_SCRIPT_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Write-Host ""
    Write-Host "=== PACKAGE FAILURE TAIL ===" -ForegroundColor Yellow
    Get-Content -LiteralPath $PackageLog -Tail 220
    Stop-Gate "BUILD_WIN64_FAILED_EXIT_$PackageExit" $(if ($PackageExit -gt 0) { $PackageExit } else { 30 })
}

$Exes = @(
    Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
)

if ($Exes.Count -eq 0) {
    Stop-Gate "PACKAGE_EXIT_ZERO_BUT_EXE_NOT_FOUND" 31
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
    Stop-Gate "PACKAGED_OUTPUT_NOT_FRESH_OR_NO_CONTAINERS" 32
}

Write-Host ""
Write-Host "PHASE_01_PLAYER_FOUNDATION=PASS" -ForegroundColor Green
Write-Host "ACTIVE_PLAYER_CLASS=AASPlayerCharacterV2" -ForegroundColor Green
Write-Host "LOCOMOTION_BASE=ABP_Unarmed_PROVEN_BASELINE" -ForegroundColor Green
Write-Host "PC_INPUT_SCHEMA=INSTALLED" -ForegroundColor Green
Write-Host "SPRINT_CROUCH_SLIDE_PRONE=FOUNDATION_INSTALLED" -ForegroundColor Green
Write-Host "JUMP_MANTLE=FOUNDATION_INSTALLED" -ForegroundColor Green
Write-Host "ADS_CAMERA=FOUNDATION_INSTALLED" -ForegroundColor Green
Write-Host "FREE_LOOK=FOUNDATION_INSTALLED" -ForegroundColor Green
Write-Host "TACTICAL_STANCE_STATE=FOUNDATION_INSTALLED" -ForegroundColor Green
Write-Host "COMBAT_MELEE_VEHICLES=NOT_CLAIMED_YET" -ForegroundColor Yellow
Write-Host "NEXT_GATE=RUN_PHASE_01_PLAYER_FOUNDATION_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
