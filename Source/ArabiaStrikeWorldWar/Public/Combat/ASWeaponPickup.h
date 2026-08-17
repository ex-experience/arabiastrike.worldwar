#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Interaction/ASInteractable.h"
#include "ASWeaponPickup.generated.h"
class USphereComponent; class UStaticMeshComponent; class UASWeaponDefinition;

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASWeaponPickup : public AActor, public IASInteractable
{
    GENERATED_BODY()
public:
    AASWeaponPickup();
    virtual FText GetInteractionLabel_Implementation(APawn* InteractingPawn) const override;
    virtual bool Interact_Implementation(APawn* InteractingPawn) override;
protected:
    UPROPERTY(VisibleAnywhere) TObjectPtr<USphereComponent> Collision;
    UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> Mesh;
    UPROPERTY(EditAnywhere, BlueprintReadOnly) TObjectPtr<UASWeaponDefinition> WeaponDefinition;
};
