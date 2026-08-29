#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "ASCharacter.generated.h"

class AASGrenade;
class UASHealthComponent;
class UASWeaponComponent;
class UASWeaponInventoryComponent;
class UCameraComponent;
class USpringArmComponent;

UCLASS()
class ARABIASTRIKEWORLDWAR_API UASCharacterMovementComponent : public UCharacterMovementComponent
{
    GENERATED_BODY()

public:
    UASCharacterMovementComponent();

    void SetSprintIntent(bool bNewSprintIntent);
    bool HasSprintIntent() const { return bWantsToSprint; }

    virtual void UpdateFromCompressedFlags(uint8 Flags) override;
    virtual FNetworkPredictionData_Client* GetPredictionData_Client() const override;

private:
    uint8 bWantsToSprint : 1;
};

DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FASDownedStateChanged, bool, bDowned);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FASEliminatedStateChanged, bool, bEliminated);

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASCharacter : public ACharacter
{
    GENERATED_BODY()

public:
    explicit AASCharacter(const FObjectInitializer& ObjectInitializer);

    virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;
    virtual void Tick(float DeltaSeconds) override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

    UFUNCTION(BlueprintPure)
    UASHealthComponent* GetHealthComponent() const { return Health; }

    UFUNCTION(BlueprintPure)
    UASWeaponComponent* GetWeaponComponent() const { return Weapon; }

    UFUNCTION(BlueprintPure)
    UASWeaponInventoryComponent* GetInventoryComponent() const { return Inventory; }

    UFUNCTION(BlueprintPure)
    bool IsDowned() const { return bDowned; }

    UFUNCTION(BlueprintPure)
    bool IsEliminated() const { return bEliminated; }

    UFUNCTION(BlueprintPure, Category="Movement")
    bool IsSprinting() const { return bSprintHeld && !bDowned && !bEliminated; }

    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly, Category="Respawn")
    void InitializeForRespawn();

    UPROPERTY(BlueprintAssignable)
    FASDownedStateChanged OnDownedStateChanged;

    UPROPERTY(BlueprintAssignable)
    FASEliminatedStateChanged OnEliminatedStateChanged;

protected:
    virtual void BeginPlay() override;
    virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;

    UPROPERTY(VisibleAnywhere, BlueprintReadOnly)
    TObjectPtr<USpringArmComponent> CameraBoom;

    UPROPERTY(VisibleAnywhere, BlueprintReadOnly)
    TObjectPtr<UCameraComponent> FollowCamera;

    UPROPERTY(VisibleAnywhere, BlueprintReadOnly)
    TObjectPtr<UASHealthComponent> Health;

    UPROPERTY(VisibleAnywhere, BlueprintReadOnly)
    TObjectPtr<UASWeaponComponent> Weapon;

    UPROPERTY(VisibleAnywhere, BlueprintReadOnly)
    TObjectPtr<UASWeaponInventoryComponent> Inventory;

    UPROPERTY(EditDefaultsOnly, Category="Movement", meta=(ClampMin="0.0", Units="cm/s"))
    float WalkSpeed = 520.f;

    UPROPERTY(EditDefaultsOnly, Category="Movement", meta=(ClampMin="0.0", Units="cm/s"))
    float SprintSpeed = 820.f;

    UPROPERTY(EditDefaultsOnly, Category="Movement", meta=(ClampMin="0.0"))
    float DashStrength = 1100.f;

    UPROPERTY(EditDefaultsOnly, Category="Movement", meta=(ClampMin="0.0", Units="s"))
    float DashCooldown = 1.f;

    UPROPERTY(EditDefaultsOnly)
    float InteractDistance = 450.f;

    UPROPERTY(EditDefaultsOnly, Category="Coop")
    float ReviveDistance = 240.f;

    UPROPERTY(EditDefaultsOnly, Category="Coop")
    float BleedoutSeconds = 24.f;

    UPROPERTY(EditDefaultsOnly, Category="Grenade")
    TSubclassOf<AASGrenade> GrenadeClass;

    UPROPERTY(EditDefaultsOnly, Category="Grenade")
    int32 MaxGrenades = 3;

    UPROPERTY(ReplicatedUsing=OnRep_Downed, BlueprintReadOnly)
    bool bDowned = false;

    UPROPERTY(ReplicatedUsing=OnRep_Eliminated, BlueprintReadOnly)
    bool bEliminated = false;

    UPROPERTY(Replicated, BlueprintReadOnly)
    int32 Grenades = 3;

    bool bSprintHeld = false;
    bool bFireHeld = false;

    // Written and read only by authority-side dash execution.
    double LastDashServerTimeSeconds = -1000.0;

    FTimerHandle BleedoutTimer;

    void MoveForward(float Value);
    void MoveRight(float Value);
    void Turn(float Value);
    void LookUp(float Value);
    void SprintPressed();
    void SprintReleased();
    void FirePressed();
    void FireReleased();
    void Dash();
    void FireOnce();
    void Reload();
    void Interact();
    void ThrowGrenade();
    void EquipSlot1();
    void EquipSlot2();
    void EquipSlot3();
    void EquipSlot4();

    UFUNCTION(Server, Reliable)
    void ServerSetSprinting(bool bWantsToSprint);

    UFUNCTION(Server, Reliable)
    void ServerDash();

    UFUNCTION(Server, Reliable)
    void ServerInteract(FVector_NetQuantize Origin, FVector_NetQuantizeNormal Direction);

    UFUNCTION(Server, Reliable)
    void ServerThrowGrenade(FVector_NetQuantize Origin, FVector_NetQuantizeNormal Direction);

    UFUNCTION()
    void HandleHealthDeath(AActor* InstigatorActor);

    UFUNCTION()
    void OnRep_Downed();

    UFUNCTION()
    void OnRep_Eliminated();

    void SetSprintIntent(bool bWantsToSprint);
    void ForceSprintOff();
    void ApplyLifeState();
    void EnterDownedState();
    void FinalizeBleedout();
    bool TryReviveFrom(APawn* Reviver);

    friend class UASCharacterMovementComponent;
};
