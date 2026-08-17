#include "Combat/ASWeaponInventoryComponent.h"
#include "Combat/ASWeaponComponent.h"
#include "Combat/ASWeaponDefinition.h"
#include "Net/UnrealNetwork.h"

UASWeaponInventoryComponent::UASWeaponInventoryComponent()
{
    SetIsReplicatedByDefault(true);
    PrimaryComponentTick.bCanEverTick = false;
}

void UASWeaponInventoryComponent::BeginPlay()
{
    Super::BeginPlay();
    WeaponComponent = GetOwner() ? GetOwner()->FindComponentByClass<UASWeaponComponent>() : nullptr;
    if (GetOwner() && GetOwner()->HasAuthority())
    {
        for (UASWeaponDefinition* Def : StartingLoadout) if (Def) Loadout.AddUnique(Def);
        if (Loadout.Num() > 0) EquipSlotAuthority(0);
    }
}

bool UASWeaponInventoryComponent::AddWeapon(UASWeaponDefinition* Definition, bool bAutoEquip)
{
    if (!GetOwner() || !GetOwner()->HasAuthority() || !Definition) return false;
    const int32 Index = Loadout.AddUnique(Definition);
    if (bAutoEquip) EquipSlotAuthority(Index);
    OnRep_Loadout();
    return true;
}

void UASWeaponInventoryComponent::RequestEquipSlot(int32 SlotIndex)
{
    if (GetOwner() && GetOwner()->HasAuthority()) EquipSlotAuthority(SlotIndex);
    else ServerEquipSlot(SlotIndex);
}

void UASWeaponInventoryComponent::ServerEquipSlot_Implementation(int32 SlotIndex)
{
    EquipSlotAuthority(SlotIndex);
}

bool UASWeaponInventoryComponent::EquipSlotAuthority(int32 SlotIndex)
{
    if (!GetOwner() || !GetOwner()->HasAuthority() || !Loadout.IsValidIndex(SlotIndex) || !Loadout[SlotIndex]) return false;
    if (!WeaponComponent) WeaponComponent = GetOwner()->FindComponentByClass<UASWeaponComponent>();
    if (!WeaponComponent) return false;
    EquippedSlot = SlotIndex;
    WeaponComponent->EquipDefinition(Loadout[SlotIndex]);
    OnRep_EquippedSlot();
    return true;
}

void UASWeaponInventoryComponent::OnRep_Loadout() {}
void UASWeaponInventoryComponent::OnRep_EquippedSlot()
{
    UASWeaponDefinition* Def = Loadout.IsValidIndex(EquippedSlot) ? Loadout[EquippedSlot] : nullptr;
    OnEquippedSlotChanged.Broadcast(EquippedSlot, Def);
}

void UASWeaponInventoryComponent::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME(UASWeaponInventoryComponent, Loadout);
    DOREPLIFETIME(UASWeaponInventoryComponent, EquippedSlot);
}
