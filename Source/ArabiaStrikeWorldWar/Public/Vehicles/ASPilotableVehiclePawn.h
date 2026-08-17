#pragma once
#include "CoreMinimal.h"
#include "Vehicles/ASVehiclePawn.h"
#include "Interaction/ASInteractable.h"
#include "ASPilotableVehiclePawn.generated.h"
class UFloatingPawnMovement; class UStaticMeshComponent;
UCLASS()
class ARABIASTRIKEWORLDWAR_API AASPilotableVehiclePawn : public AASVehiclePawn, public IASInteractable
{
    GENERATED_BODY()
public:
    AASPilotableVehiclePawn(); virtual void SetupPlayerInputComponent(UInputComponent*) override;
    virtual FText GetInteractionLabel_Implementation(APawn*) const override; virtual bool Interact_Implementation(APawn*) override;
    UFUNCTION(BlueprintCallable) void ExitVehicle();
protected:
    UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> Body; UPROPERTY(VisibleAnywhere) TObjectPtr<UFloatingPawnMovement> DriveMovement;
    UPROPERTY(EditDefaultsOnly) float TurnRate=65.f;
    void Throttle(float V); void Steer(float V);
    UFUNCTION(Server,Reliable) void ServerEnter(APawn* Pawn); UFUNCTION(Server,Reliable) void ServerExit(APlayerController* Controller);
};
