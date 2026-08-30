#pragma once
#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "ASWeaponInventoryComponent.generated.h"
class UASWeaponDefinition;
class UASWeaponComponent;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FASWeaponSlotChanged, int32, SlotIndex, UASWeaponDefinition*, Definition);

UCLASS(ClassGroup=(Combat), meta=(BlueprintSpawnableComponent))
class ARABIASTRIKEWORLDWAR_API UASWeaponInventoryComponent : public UActorComponent
{
    GENERATED_BODY()
public:
    UASWeaponInventoryComponent();
    virtual void BeginPlay() override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

    UPROPERTY(BlueprintAssignable) FASWeaponSlotChanged OnEquippedSlotChanged;
    UFUNCTION(BlueprintCallable) void RequestEquipSlot(int32 SlotIndex);
    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly) bool AddWeapon(UASWeaponDefinition* Definition, bool bAutoEquip=true);
    UFUNCTION(BlueprintPure) int32 GetEquippedSlot() const { return EquippedSlot; }
    const TArray<TObjectPtr<UASWeaponDefinition>>& GetLoadout() const { return Loadout; }

protected:
    UPROPERTY(EditDefaultsOnly, Category="Loadout") TArray<TObjectPtr<UASWeaponDefinition>> StartingLoadout;
    UPROPERTY(ReplicatedUsing=OnRep_Loadout) TArray<TObjectPtr<UASWeaponDefinition>> Loadout;
    UPROPERTY(ReplicatedUsing=OnRep_EquippedSlot) int32 EquippedSlot = INDEX_NONE;
    UPROPERTY() TObjectPtr<UASWeaponComponent> WeaponComponent;

    UFUNCTION(Server, Reliable) void ServerEquipSlot(int32 SlotIndex);
    UFUNCTION() void OnRep_Loadout();
    UFUNCTION() void OnRep_EquippedSlot();
    bool EquipSlotAuthority(int32 SlotIndex);
};
