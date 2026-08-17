#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "ASCharacter.generated.h"
class UASHealthComponent; class UASWeaponComponent; class UASWeaponInventoryComponent; class USpringArmComponent; class UCameraComponent; class AASGrenade;
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FASDownedStateChanged,bool,bDowned);
UCLASS()
class ARABIASTRIKEWORLDWAR_API AASCharacter : public ACharacter
{
    GENERATED_BODY()
public:
    AASCharacter();
    virtual void SetupPlayerInputComponent(UInputComponent*) override;
    virtual void Tick(float) override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
    UFUNCTION(BlueprintPure) UASHealthComponent* GetHealthComponent()const{return Health;}
    UFUNCTION(BlueprintPure) UASWeaponComponent* GetWeaponComponent()const{return Weapon;}
    UFUNCTION(BlueprintPure) UASWeaponInventoryComponent* GetInventoryComponent()const{return Inventory;}
    UFUNCTION(BlueprintPure) bool IsDowned() const { return bDowned; }
    UPROPERTY(BlueprintAssignable) FASDownedStateChanged OnDownedStateChanged;
protected:
    virtual void BeginPlay()override;
    UPROPERTY(VisibleAnywhere,BlueprintReadOnly) TObjectPtr<USpringArmComponent> CameraBoom;
    UPROPERTY(VisibleAnywhere,BlueprintReadOnly) TObjectPtr<UCameraComponent> FollowCamera;
    UPROPERTY(VisibleAnywhere,BlueprintReadOnly) TObjectPtr<UASHealthComponent> Health;
    UPROPERTY(VisibleAnywhere,BlueprintReadOnly) TObjectPtr<UASWeaponComponent> Weapon;
    UPROPERTY(VisibleAnywhere,BlueprintReadOnly) TObjectPtr<UASWeaponInventoryComponent> Inventory;
    UPROPERTY(EditDefaultsOnly) float WalkSpeed=520.f;
    UPROPERTY(EditDefaultsOnly) float SprintSpeed=820.f;
    UPROPERTY(EditDefaultsOnly) float DashStrength=1100.f;
    UPROPERTY(EditDefaultsOnly) float DashCooldown=1.f;
    UPROPERTY(EditDefaultsOnly) float InteractDistance=450.f;
    UPROPERTY(EditDefaultsOnly,Category="Coop") float ReviveDistance=240.f;
    UPROPERTY(EditDefaultsOnly,Category="Coop") float BleedoutSeconds=24.f;
    UPROPERTY(EditDefaultsOnly,Category="Grenade") TSubclassOf<AASGrenade> GrenadeClass;
    UPROPERTY(EditDefaultsOnly,Category="Grenade") int32 MaxGrenades=3;
    UPROPERTY(ReplicatedUsing=OnRep_Downed,BlueprintReadOnly) bool bDowned=false;
    UPROPERTY(Replicated,BlueprintReadOnly) bool bEliminated=false;
    UPROPERTY(Replicated,BlueprintReadOnly) int32 Grenades=3;
    bool bSprintHeld=false,bFireHeld=false;
    double LastDashTime=-1000.;
    FTimerHandle BleedoutTimer;
    void MoveForward(float);void MoveRight(float);void Turn(float);void LookUp(float);
    void SprintPressed();void SprintReleased();void FirePressed();void FireReleased();void Dash();void FireOnce();void Reload();void Interact();void ThrowGrenade();
    void EquipSlot1();void EquipSlot2();void EquipSlot3();void EquipSlot4();
    UFUNCTION(Server,Reliable) void ServerInteract(FVector_NetQuantize Origin,FVector_NetQuantizeNormal Direction);
    UFUNCTION(Server,Reliable) void ServerThrowGrenade(FVector_NetQuantize Origin,FVector_NetQuantizeNormal Direction);
    UFUNCTION() void HandleHealthDeath(AActor* InstigatorActor);
    UFUNCTION() void OnRep_Downed();
    void EnterDownedState();
    void FinalizeBleedout();
    bool TryReviveFrom(APawn* Reviver);
};
