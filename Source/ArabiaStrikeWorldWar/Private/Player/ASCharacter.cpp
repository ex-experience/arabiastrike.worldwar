#include "Player/ASCharacter.h"

#include "Camera/CameraComponent.h"
#include "Animation/AnimInstance.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/StaticMesh.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/StaticMeshComponent.h"
#include "UObject/ConstructorHelpers.h"
#include "Combat/ASGrenade.h"
#include "Combat/ASHealthComponent.h"
#include "Combat/ASWeaponComponent.h"
#include "Combat/ASWeaponInventoryComponent.h"
#include "Engine/World.h"
#include "Game/ASGameMode.h"
#include "GameFramework/PlayerState.h"
#include "GameFramework/SpringArmComponent.h"
#include "Interaction/ASInteractable.h"
#include "Net/UnrealNetwork.h"
#include "Player/ASPlayerState.h"
#include "TimerManager.h"

namespace
{
class FSavedMove_ASCharacter final : public FSavedMove_Character
{
public:
    using Super = FSavedMove_Character;

    uint8 bSavedWantsToSprint : 1;

    virtual void Clear() override
    {
        Super::Clear();
        bSavedWantsToSprint = false;
    }

    virtual uint8 GetCompressedFlags() const override
    {
        uint8 Result = Super::GetCompressedFlags();
        if (bSavedWantsToSprint)
        {
            Result |= FLAG_Custom_0;
        }
        return Result;
    }

    virtual bool CanCombineWith(const FSavedMovePtr& NewMove, ACharacter* InCharacter, float MaxDelta) const override
    {
        const FSavedMove_ASCharacter* NewCharacterMove = static_cast<const FSavedMove_ASCharacter*>(NewMove.Get());
        if (bSavedWantsToSprint != NewCharacterMove->bSavedWantsToSprint)
        {
            return false;
        }
        return Super::CanCombineWith(NewMove, InCharacter, MaxDelta);
    }

    virtual void SetMoveFor(
        ACharacter* Character,
        float InDeltaTime,
        const FVector& NewAcceleration,
        FNetworkPredictionData_Client_Character& ClientData) override
    {
        Super::SetMoveFor(Character, InDeltaTime, NewAcceleration, ClientData);
        const UASCharacterMovementComponent* Movement =
            Cast<UASCharacterMovementComponent>(Character ? Character->GetCharacterMovement() : nullptr);
        bSavedWantsToSprint = Movement && Movement->HasSprintIntent();
    }

    virtual void PrepMoveFor(ACharacter* Character) override
    {
        Super::PrepMoveFor(Character);
        if (UASCharacterMovementComponent* Movement =
                Cast<UASCharacterMovementComponent>(Character ? Character->GetCharacterMovement() : nullptr))
        {
            Movement->SetSprintIntent(bSavedWantsToSprint);
        }
    }
};

class FNetworkPredictionData_Client_ASCharacter final : public FNetworkPredictionData_Client_Character
{
public:
    explicit FNetworkPredictionData_Client_ASCharacter(const UCharacterMovementComponent& ClientMovement)
        : FNetworkPredictionData_Client_Character(ClientMovement)
    {
    }

    virtual FSavedMovePtr AllocateNewMove() override
    {
        return FSavedMovePtr(new FSavedMove_ASCharacter());
    }
};
}

UASCharacterMovementComponent::UASCharacterMovementComponent()
    : bWantsToSprint(false)
{
}

void UASCharacterMovementComponent::SetSprintIntent(bool bNewSprintIntent)
{
    AASCharacter* Character = Cast<AASCharacter>(CharacterOwner);
    const bool bAllowedToSprint =
        bNewSprintIntent && Character && !Character->bDowned && !Character->bEliminated;

    bWantsToSprint = bAllowedToSprint;
    if (Character)
    {
        Character->bSprintHeld = bAllowedToSprint;
        MaxWalkSpeed = bAllowedToSprint ? Character->SprintSpeed : Character->WalkSpeed;
    }
}

void UASCharacterMovementComponent::UpdateFromCompressedFlags(uint8 Flags)
{
    Super::UpdateFromCompressedFlags(Flags);
    SetSprintIntent((Flags & FSavedMove_Character::FLAG_Custom_0) != 0);
}

FNetworkPredictionData_Client* UASCharacterMovementComponent::GetPredictionData_Client() const
{
    if (!ClientPredictionData)
    {
        UASCharacterMovementComponent* MutableThis = const_cast<UASCharacterMovementComponent*>(this);
        MutableThis->ClientPredictionData = new FNetworkPredictionData_Client_ASCharacter(*this);
        MutableThis->ClientPredictionData->MaxSmoothNetUpdateDist = 92.f;
        MutableThis->ClientPredictionData->NoSmoothNetUpdateDist = 140.f;
    }
    return ClientPredictionData;
}

AASCharacter::AASCharacter(const FObjectInitializer& ObjectInitializer)
    : Super(ObjectInitializer.SetDefaultSubobjectClass<UASCharacterMovementComponent>(
          ACharacter::CharacterMovementComponentName))
{
    PrimaryActorTick.bCanEverTick = true;
    bReplicates = true;
    SetReplicateMovement(true);

    GetCharacterMovement()->MaxWalkSpeed = WalkSpeed;
    GetCharacterMovement()->bOrientRotationToMovement = false;
    bUseControllerRotationYaw = true;

    CameraBoom = CreateDefaultSubobject<USpringArmComponent>(TEXT("CameraBoom"));
    CameraBoom->SetupAttachment(RootComponent);
    CameraBoom->TargetArmLength = 360.f;
    CameraBoom->bUsePawnControlRotation = true;

    FollowCamera = CreateDefaultSubobject<UCameraComponent>(TEXT("FollowCamera"));
    FollowCamera->SetupAttachment(CameraBoom, USpringArmComponent::SocketName);
    static ConstructorHelpers::FObjectFinder<USkeletalMesh> PlayerMeshAsset(
        TEXT("/Game/Characters/Mannequins/Meshes/SKM_Manny_Simple.SKM_Manny_Simple"));
    if (PlayerMeshAsset.Succeeded())
    {
        GetMesh()->SetSkeletalMeshAsset(PlayerMeshAsset.Object);
        GetMesh()->SetRelativeLocation(FVector(0.f, 0.f, -90.f));
        GetMesh()->SetRelativeRotation(FRotator(0.f, -90.f, 0.f));
        GetMesh()->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    }

    static ConstructorHelpers::FClassFinder<UAnimInstance> PlayerAnimClass(
        TEXT("/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed"));
    if (PlayerAnimClass.Succeeded())
    {
        GetMesh()->SetAnimInstanceClass(PlayerAnimClass.Class);
    }

    // ASWW_REAL_RIFLE_VISUAL_BEGIN
    UStaticMeshComponent* RifleVisual =
        CreateDefaultSubobject<UStaticMeshComponent>(TEXT("ASWW_RifleVisual"));
    RifleVisual->SetupAttachment(GetMesh(), TEXT("HandGrip_R"));
    RifleVisual->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    RifleVisual->SetGenerateOverlapEvents(false);

    static ConstructorHelpers::FObjectFinder<UStaticMesh> RifleMeshAsset(
        TEXT("/Game/Weapons/Rifle/Meshes/SM_Rifle.SM_Rifle"));
    if (RifleMeshAsset.Succeeded())
    {
        RifleVisual->SetStaticMesh(RifleMeshAsset.Object);

        // Initial proof transform only. We verify visually before tuning.
        RifleVisual->SetRelativeTransform(FTransform::Identity);
    }

    UE_LOG(LogTemp, Warning,
        TEXT("ASWW_COMBAT_PROOF RIFLE_VISUAL mesh=%s parent=%s socket=HandGrip_R"),
        *GetNameSafe(RifleVisual->GetStaticMesh()),
        *GetNameSafe(RifleVisual->GetAttachParent()));
    // ASWW_REAL_RIFLE_VISUAL_END

    // ASWW_TP_RIFLE_TACTICAL_BEGIN
    // Third-person rifle AnimBlueprint: ABP_TP_Rifle.
    // Rifle visual attached to real Manny socket: HandGrip_R.
    // Manny provides ik_hand_gun / ik_hand_l chains.
    // Left-hand support grip remains visually gated; no false IK PASS is claimed here.
    // ASWW_TP_RIFLE_TACTICAL_END

    // ASWW_PLAYER_REGRESSION_AB_TEST_BEGIN
    // Temporary A/B isolation:
    // ABP_TP_Rifle -> ABP_Unarmed
    // Rifle remains attached to HandGrip_R.
    // If movement/camera recover, direct ABP_TP_Rifle assignment is the regression source.
    // ASWW_PLAYER_REGRESSION_AB_TEST_END

    UE_LOG(LogTemp, Warning,
        TEXT("ASWW_REAL_PLAYER_MANNY mesh=%s animClass=%s"),
        *GetNameSafe(GetMesh()->GetSkeletalMeshAsset()),
        *GetNameSafe(GetMesh()->GetAnimClass()));
Health = CreateDefaultSubobject<UASHealthComponent>(TEXT("Health"));
    Weapon = CreateDefaultSubobject<UASWeaponComponent>(TEXT("Weapon"));
    Inventory = CreateDefaultSubobject<UASWeaponInventoryComponent>(TEXT("Inventory"));
}

void AASCharacter::BeginPlay()
{
    Super::BeginPlay();
    ForceSprintOff();
    Grenades = MaxGrenades;
    if (Health)
    {
        Health->OnDeath.AddDynamic(this, &AASCharacter::HandleHealthDeath);
    }
}

void AASCharacter::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
    GetWorldTimerManager().ClearTimer(BleedoutTimer);
    ForceSprintOff();
    Super::EndPlay(EndPlayReason);
}

void AASCharacter::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    if (bFireHeld && !bDowned && !bEliminated)
    {
        FireOnce();
    }
}

void AASCharacter::SetupPlayerInputComponent(UInputComponent* PlayerInputComponent)
{
    Super::SetupPlayerInputComponent(PlayerInputComponent);
    PlayerInputComponent->BindAxis("MoveForward", this, &AASCharacter::MoveForward);
    PlayerInputComponent->BindAxis("MoveRight", this, &AASCharacter::MoveRight);
    PlayerInputComponent->BindAxis("Turn", this, &AASCharacter::Turn);
    PlayerInputComponent->BindAxis("LookUp", this, &AASCharacter::LookUp);
    PlayerInputComponent->BindAction("Jump", IE_Pressed, this, &ACharacter::Jump);
    PlayerInputComponent->BindAction("Jump", IE_Released, this, &ACharacter::StopJumping);
    PlayerInputComponent->BindAction("Sprint", IE_Pressed, this, &AASCharacter::SprintPressed);
    PlayerInputComponent->BindAction("Sprint", IE_Released, this, &AASCharacter::SprintReleased);
    PlayerInputComponent->BindAction("Fire", IE_Pressed, this, &AASCharacter::FirePressed);
    PlayerInputComponent->BindAction("Fire", IE_Released, this, &AASCharacter::FireReleased);
    PlayerInputComponent->BindAction("Dash", IE_Pressed, this, &AASCharacter::Dash);
    PlayerInputComponent->BindAction("Reload", IE_Pressed, this, &AASCharacter::Reload);
    PlayerInputComponent->BindAction("Interact", IE_Pressed, this, &AASCharacter::Interact);
    PlayerInputComponent->BindAction("Grenade", IE_Pressed, this, &AASCharacter::ThrowGrenade);
    PlayerInputComponent->BindAction("Weapon1", IE_Pressed, this, &AASCharacter::EquipSlot1);
    PlayerInputComponent->BindAction("Weapon2", IE_Pressed, this, &AASCharacter::EquipSlot2);
    PlayerInputComponent->BindAction("Weapon3", IE_Pressed, this, &AASCharacter::EquipSlot3);
    PlayerInputComponent->BindAction("Weapon4", IE_Pressed, this, &AASCharacter::EquipSlot4);
}

void AASCharacter::MoveForward(float Value)
{
    if (Controller && Value != 0.f && !bDowned && !bEliminated)
    {
        AddMovementInput(GetActorForwardVector(), Value);
    }
}

void AASCharacter::MoveRight(float Value)
{
    if (Controller && Value != 0.f && !bDowned && !bEliminated)
    {
        AddMovementInput(GetActorRightVector(), Value);
    }
}

void AASCharacter::Turn(float Value)
{
    AddControllerYawInput(Value);
}

void AASCharacter::LookUp(float Value)
{
    AddControllerPitchInput(Value);
}

void AASCharacter::SetSprintIntent(bool bWantsToSprint)
{
    if (UASCharacterMovementComponent* Movement =
            Cast<UASCharacterMovementComponent>(GetCharacterMovement()))
    {
        Movement->SetSprintIntent(bWantsToSprint);
    }
    else
    {
        bSprintHeld = false;
        GetCharacterMovement()->MaxWalkSpeed = WalkSpeed;
    }
}

void AASCharacter::ForceSprintOff()
{
    SetSprintIntent(false);
}

void AASCharacter::SprintPressed()
{
    if (bDowned || bEliminated)
    {
        ForceSprintOff();
        return;
    }

    // The owning client predicts only the boolean intent. The saved move carries
    // the same flag so server replay uses the authoritative SprintSpeed value.
    SetSprintIntent(true);
    if (!HasAuthority())
    {
        ServerSetSprinting(true);
    }
}

void AASCharacter::SprintReleased()
{
    // Release must restore WalkSpeed even if life state changed while held.
    ForceSprintOff();
    if (!HasAuthority())
    {
        ServerSetSprinting(false);
    }
}

void AASCharacter::ServerSetSprinting_Implementation(bool bWantsToSprint)
{
    if (!HasAuthority())
    {
        return;
    }
    SetSprintIntent(bWantsToSprint && !bDowned && !bEliminated);
}

void AASCharacter::Dash()
{
    // No client LaunchCharacter prediction: this avoids a second launch when the
    // authoritative movement update is reconciled.
    if (bDowned || bEliminated)
    {
        return;
    }
    if (HasAuthority())
    {
        ServerDash_Implementation();
    }
    else
    {
        ServerDash();
    }
}

void AASCharacter::ServerDash_Implementation()
{
    UWorld* World = GetWorld();
    if (!HasAuthority() || !World || bDowned || bEliminated)
    {
        return;
    }

    const double ServerTimeSeconds = World->GetTimeSeconds();
    const double ServerCooldownSeconds = FMath::Max(0.0, static_cast<double>(DashCooldown));
    if (ServerTimeSeconds - LastDashServerTimeSeconds < ServerCooldownSeconds)
    {
        return;
    }

    FVector AuthoritativeDashDirection = GetActorForwardVector();
    AuthoritativeDashDirection.Z = 0.f;
    if (!AuthoritativeDashDirection.Normalize())
    {
        return;
    }

    LastDashServerTimeSeconds = ServerTimeSeconds;
    const FVector AuthoritativeLaunchVelocity =
        AuthoritativeDashDirection * DashStrength + FVector(0.f, 0.f, 80.f);
    LaunchCharacter(AuthoritativeLaunchVelocity, true, false);
}

void AASCharacter::FirePressed()
{
    if (bDowned || bEliminated)
    {
        return;
    }
    bFireHeld = true;
    FireOnce();
}

void AASCharacter::FireReleased()
{
    bFireHeld = false;
}

void AASCharacter::FireOnce()
{
    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_QA_FIRE_DISPATCH weapon=%d controller=%d downed=%d eliminated=%d"),
        Weapon ? 1 : 0,
        Controller ? 1 : 0,
        bDowned ? 1 : 0,
        bEliminated ? 1 : 0);

    if (!Weapon || !Controller || bDowned || bEliminated)
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_FIRE_DISPATCH_REJECT"));
        return;
    }

    FVector L;
    FRotator R;
    Controller->GetPlayerViewPoint(L, R);

    UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_FIRE_REQUEST_SENT"));
    Weapon->RequestFire(L, R.Vector());
}
void AASCharacter::Reload()
{
    if (Weapon && !bDowned && !bEliminated)
    {
        Weapon->RequestReload();
    }
}

void AASCharacter::Interact()
{
    if (!Controller || !GetWorld() || bDowned || bEliminated)
    {
        return;
    }
    FVector ViewLocation;
    FRotator ViewRotation;
    Controller->GetPlayerViewPoint(ViewLocation, ViewRotation);
    if (HasAuthority())
    {
        ServerInteract_Implementation(ViewLocation, ViewRotation.Vector());
    }
    else
    {
        ServerInteract(ViewLocation, ViewRotation.Vector());
    }
}

void AASCharacter::ServerInteract_Implementation(
    FVector_NetQuantize Origin,
    FVector_NetQuantizeNormal Direction)
{
    if (bDowned || bEliminated || FVector::DistSquared(Origin, GetActorLocation()) > FMath::Square(700.f) ||
        !GetWorld())
    {
        return;
    }

    FHitResult Hit;
    FCollisionQueryParams Query(SCENE_QUERY_STAT(ASServerInteract), true, this);
    if (GetWorld()->LineTraceSingleByChannel(
            Hit,
            Origin,
            Origin + Direction * InteractDistance,
            ECC_Visibility,
            Query) &&
        Hit.GetActor())
    {
        if (AASCharacter* Target = Cast<AASCharacter>(Hit.GetActor()))
        {
            Target->TryReviveFrom(this);
            return;
        }
        if (Hit.GetActor()->GetClass()->ImplementsInterface(UASInteractable::StaticClass()))
        {
            IASInteractable::Execute_Interact(Hit.GetActor(), this);
        }
    }
}

void AASCharacter::ThrowGrenade()
{
    if (!Controller || bDowned || bEliminated || Grenades <= 0)
    {
        return;
    }
    FVector ViewLocation;
    FRotator ViewRotation;
    Controller->GetPlayerViewPoint(ViewLocation, ViewRotation);
    if (HasAuthority())
    {
        ServerThrowGrenade_Implementation(ViewLocation, ViewRotation.Vector());
    }
    else
    {
        ServerThrowGrenade(ViewLocation, ViewRotation.Vector());
    }
}

void AASCharacter::ServerThrowGrenade_Implementation(
    FVector_NetQuantize Origin,
    FVector_NetQuantizeNormal Direction)
{
    if (bDowned || bEliminated || !GrenadeClass || Grenades <= 0 ||
        FVector::DistSquared(Origin, GetActorLocation()) > FMath::Square(700.f) || !GetWorld())
    {
        return;
    }

    --Grenades;
    FActorSpawnParameters SpawnParameters;
    SpawnParameters.Owner = this;
    SpawnParameters.Instigator = this;
    GetWorld()->SpawnActor<AASGrenade>(
        GrenadeClass,
        Origin + Direction * 70.f,
        Direction.Rotation() + FRotator(-12.f, 0.f, 0.f),
        SpawnParameters);
}

void AASCharacter::EquipSlot1()
{
    if (Inventory && !bDowned && !bEliminated)
    {
        Inventory->RequestEquipSlot(0);
    }
}

void AASCharacter::EquipSlot2()
{
    if (Inventory && !bDowned && !bEliminated)
    {
        Inventory->RequestEquipSlot(1);
    }
}

void AASCharacter::EquipSlot3()
{
    if (Inventory && !bDowned && !bEliminated)
    {
        Inventory->RequestEquipSlot(2);
    }
}

void AASCharacter::EquipSlot4()
{
    if (Inventory && !bDowned && !bEliminated)
    {
        Inventory->RequestEquipSlot(3);
    }
}

void AASCharacter::HandleHealthDeath(AActor*)
{
    if (HasAuthority() && !bDowned && !bEliminated)
    {
        EnterDownedState();
    }
}

void AASCharacter::EnterDownedState()
{
    if (!HasAuthority() || bDowned || bEliminated)
    {
        return;
    }

    GetWorldTimerManager().ClearTimer(BleedoutTimer);
    bDowned = true;
    bFireHeld = false;
    ForceSprintOff();
    OnRep_Downed();
    ForceNetUpdate();
    GetWorldTimerManager().SetTimer(
        BleedoutTimer,
        this,
        &AASCharacter::FinalizeBleedout,
        FMath::Max(0.1f, BleedoutSeconds),
        false);
}

bool AASCharacter::TryReviveFrom(APawn* Reviver)
{
    if (!HasAuthority() || !bDowned || bEliminated || !Reviver ||
        FVector::DistSquared(Reviver->GetActorLocation(), GetActorLocation()) > FMath::Square(ReviveDistance))
    {
        return false;
    }

    APlayerState* MyPlayerState = GetPlayerState();
    APlayerState* TheirPlayerState = Reviver->GetPlayerState();
    if (MyPlayerState && TheirPlayerState)
    {
        const AASPlayerState* MyASPlayerState = Cast<AASPlayerState>(MyPlayerState);
        const AASPlayerState* TheirASPlayerState = Cast<AASPlayerState>(TheirPlayerState);
        if (MyASPlayerState && TheirASPlayerState && MyASPlayerState->TeamId != TheirASPlayerState->TeamId)
        {
            return false;
        }
    }

    if (!Health || !Health->Revive(0.35f))
    {
        return false;
    }

    GetWorldTimerManager().ClearTimer(BleedoutTimer);
    bDowned = false;
    ForceSprintOff();
    OnRep_Downed();
    ForceNetUpdate();
    return true;
}

void AASCharacter::FinalizeBleedout()
{
    if (!HasAuthority() || !bDowned || bEliminated)
    {
        return;
    }

    GetWorldTimerManager().ClearTimer(BleedoutTimer);
    bEliminated = true;
    bDowned = false;
    bFireHeld = false;
    ForceSprintOff();
    OnRep_Downed();
    OnRep_Eliminated();
    ForceNetUpdate();
    if (AASGameMode* GameMode = GetWorld() ? GetWorld()->GetAuthGameMode<AASGameMode>() : nullptr)
    {
        GameMode->HandlePlayerEliminated(this);
    }
}

void AASCharacter::InitializeForRespawn()
{
    if (!HasAuthority())
    {
        return;
    }

    GetWorldTimerManager().ClearTimer(BleedoutTimer);
    bDowned = false;
    bEliminated = false;
    bFireHeld = false;
    ForceSprintOff();
    Grenades = MaxGrenades;
    LastDashServerTimeSeconds = -1000.0;
    if (Health)
    {
        Health->ResetHealth();
    }
    SetActorHiddenInGame(false);
    OnRep_Downed();
    OnRep_Eliminated();
    ForceNetUpdate();
}

void AASCharacter::ApplyLifeState()
{
    UCharacterMovementComponent* Movement = GetCharacterMovement();
    if (bEliminated)
    {
        ForceSprintOff();
        SetActorEnableCollision(false);
        SetCanBeDamaged(false);
        if (Movement)
        {
            Movement->StopMovementImmediately();
            Movement->DisableMovement();
        }
        return;
    }

    SetActorEnableCollision(true);
    SetCanBeDamaged(true);
    if (!Movement)
    {
        return;
    }

    if (bDowned)
    {
        ForceSprintOff();
        Movement->StopMovementImmediately();
        Movement->DisableMovement();
    }
    else
    {
        if (Movement->MovementMode == MOVE_None)
        {
            Movement->SetMovementMode(MOVE_Walking);
        }
        Movement->MaxWalkSpeed = bSprintHeld ? SprintSpeed : WalkSpeed;
    }
}

void AASCharacter::OnRep_Downed()
{
    ApplyLifeState();
    OnDownedStateChanged.Broadcast(bDowned);
}

void AASCharacter::OnRep_Eliminated()
{
    ApplyLifeState();
    OnEliminatedStateChanged.Broadcast(bEliminated);
}

void AASCharacter::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME(AASCharacter, bDowned);
    DOREPLIFETIME(AASCharacter, bEliminated);
    DOREPLIFETIME(AASCharacter, Grenades);
}
