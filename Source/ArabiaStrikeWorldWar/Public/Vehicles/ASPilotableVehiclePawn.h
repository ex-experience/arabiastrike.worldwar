#pragma once
#include "CoreMinimal.h"
#include "Vehicles/ASVehiclePawn.h"
#include "Interaction/ASInteractable.h"
#include "ASPilotableVehiclePawn.generated.h"
class UCameraComponent; class UFloatingPawnMovement; class USpringArmComponent; class UStaticMeshComponent; class UASVehicleTurretComponent; class UASVehicleDamageModelComponent;
UCLASS()
class ARABIASTRIKEWORLDWAR_API AASPilotableVehiclePawn : public AASVehiclePawn, public IASInteractable
{
    GENERATED_BODY()
public:
    AASPilotableVehiclePawn();
    virtual void SetupPlayerInputComponent(UInputComponent*) override;
    virtual FText GetInteractionLabel_Implementation(APawn*) const override;
    virtual bool Interact_Implementation(APawn*) override;
    UFUNCTION(BlueprintCallable) void ExitVehicle();
protected:
    UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> Body;
    UPROPERTY(VisibleAnywhere) TObjectPtr<USpringArmComponent> CameraBoom;
    UPROPERTY(VisibleAnywhere) TObjectPtr<UCameraComponent> DriveCamera;
    UPROPERTY(VisibleAnywhere) TObjectPtr<UFloatingPawnMovement> DriveMovement;
    UPROPERTY(VisibleAnywhere) TObjectPtr<UASVehicleTurretComponent> Turret;
    UPROPERTY(VisibleAnywhere) TObjectPtr<UASVehicleDamageModelComponent> DamageModel;
    UPROPERTY(EditDefaultsOnly) float TurnRate=65.f;
    UPROPERTY() TObjectPtr<APawn> StoredDriverPawn;
    void Throttle(float V); void Steer(float V); void FireTurret(); void AimTurret(float Value);
    UFUNCTION(Server,Reliable) void ServerExit(APlayerController* InController);
};
