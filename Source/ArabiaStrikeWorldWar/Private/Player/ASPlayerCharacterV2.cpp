#include "Player/ASPlayerCharacterV2.h"
#include "Combat/ASWeaponDefinition.h"
#include "Combat/ASWeaponInventoryComponent.h"

#include "Animation/AnimInstance.h"
#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "UObject/ConstructorHelpers.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/SpringArmComponent.h"
#include "Engine/World.h"
#include "TimerManager.h"
#include "UObject/ConstructorHelpers.h"

AASPlayerCharacterV2::AASPlayerCharacterV2(const FObjectInitializer& ObjectInitializer)
    : Super(ObjectInitializer)
{
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

    // ASWW_PHASE03F_DEFAULT_RIFLE_LOADOUT_BEGIN
    if (HasAuthority() && Inventory)
    {
        UASWeaponDefinition* RifleDefinition = LoadObject<UASWeaponDefinition>(
            nullptr,
            TEXT("/Game/Weapons/Definitions/DA_ASWW_Rifle_01.DA_ASWW_Rifle_01"));

        if (RifleDefinition)
        {
            const bool bLoadoutAccepted = Inventory->AddWeapon(RifleDefinition, true);

            UE_LOG(
                LogTemp,
                Warning,
                TEXT("ASWW_QA_RIFLE_DEFINITION_EQUIP load=1 accepted=%d asset=%s"),
                bLoadoutAccepted ? 1 : 0,
                *GetNameSafe(RifleDefinition));
        }
        else
        {
            UE_LOG(
                LogTemp,
                Error,
                TEXT("ASWW_QA_RIFLE_DEFINITION_EQUIP load=0 accepted=0 asset=NONE"));
        }
    }
    // ASWW_PHASE03F_DEFAULT_RIFLE_LOADOUT_END

    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_CONTROL_RECOVERY_AB_UNARMED anim=%s rifleSubobject=ASWW_TacticalRifleMesh socket=HandGrip_R"),
        *GetNameSafe(GetMesh() ? GetMesh()->GetAnimClass() : nullptr));

    if (UCapsuleComponent* Capsule = GetCapsuleComponent())
    {
        StandingCapsuleHalfHeight = Capsule->GetUnscaledCapsuleHalfHeight();
    }

    UpdateMovementProfile();
}

void AASPlayerCharacterV2::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);

    if (MovementStance == EASMovementStance::Standing && bIsCrouched)
    {
        UnCrouch(false);
    }
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
    UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_RELOAD_KEY_PRESSED"));
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

    if (MovementStance == EASMovementStance::Sliding)
    {
        StopSlide();
    }

    // Temporary safe-prone foundation.
    // ACharacter crouch preserves the character floor/base and prevents
    // the mesh from being pushed below the ground by raw capsule resizing.
    if (!bIsCrouched)
    {
        Crouch(false);
    }

    MovementStance = EASMovementStance::Prone;

    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_QA_Z_ENTER crouchedNow=%d capsuleHalfHeight=%.2f"),
        bIsCrouched ? 1 : 0,
        GetCapsuleComponent() ? GetCapsuleComponent()->GetUnscaledCapsuleHalfHeight() : -1.f);
    bSprintHeldV2 = false;
    UpdateMovementProfile();
}

void AASPlayerCharacterV2::ExitProne()
{
    // Recover gameplay state before asking CharacterMovement to restore the capsule.
    MovementStance = EASMovementStance::Standing;
    bSprintHeldV2 = false;

    if (UCharacterMovementComponent* Move = GetCharacterMovement())
    {
        Move->MaxWalkSpeedCrouched = CrouchMoveSpeed;
    }

    UnCrouch(false);
    UpdateMovementProfile();

    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_QA_Z_EXIT_REQUEST crouchedNow=%d capsuleHalfHeight=%.2f"),
        bIsCrouched ? 1 : 0,
        GetCapsuleComponent() ? GetCapsuleComponent()->GetUnscaledCapsuleHalfHeight() : -1.f);
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
        Move->MaxWalkSpeedCrouched = ProneMoveSpeed;
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