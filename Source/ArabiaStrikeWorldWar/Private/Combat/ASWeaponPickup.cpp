#include "Combat/ASWeaponPickup.h"
#include "Combat/ASWeaponInventoryComponent.h"
#include "Components/SphereComponent.h"
#include "Components/StaticMeshComponent.h"

AASWeaponPickup::AASWeaponPickup()
{
    bReplicates = true;
    Collision = CreateDefaultSubobject<USphereComponent>(TEXT("Collision"));
    RootComponent = Collision;
    Collision->InitSphereRadius(55.f);
    Collision->SetCollisionProfileName(TEXT("OverlapAllDynamic"));
    Mesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Mesh"));
    Mesh->SetupAttachment(RootComponent);
    Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
}

FText AASWeaponPickup::GetInteractionLabel_Implementation(APawn*) const
{
    return FText::FromString(TEXT("PICK UP WEAPON"));
}

bool AASWeaponPickup::Interact_Implementation(APawn* InteractingPawn)
{
    if (!HasAuthority() || !InteractingPawn || !WeaponDefinition) return false;
    if (UASWeaponInventoryComponent* Inventory = InteractingPawn->FindComponentByClass<UASWeaponInventoryComponent>())
    {
        if (Inventory->AddWeapon(WeaponDefinition, true))
        {
            Destroy();
            return true;
        }
    }
    return false;
}
