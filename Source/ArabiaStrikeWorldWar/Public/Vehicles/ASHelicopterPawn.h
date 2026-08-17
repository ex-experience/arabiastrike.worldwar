#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Pawn.h"
#include "ASHelicopterPawn.generated.h"
class UStaticMeshComponent; class UFloatingPawnMovement; class UASHealthComponent; class UASVehicleTurretComponent;
UCLASS()
class ARABIASTRIKEWORLDWAR_API AASHelicopterPawn : public APawn
{
    GENERATED_BODY()
public:
    AASHelicopterPawn();
    virtual void Tick(float DeltaSeconds) override;
protected:
    UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> Body;
    UPROPERTY(VisibleAnywhere) TObjectPtr<UFloatingPawnMovement> FlightMovement;
    UPROPERTY(VisibleAnywhere) TObjectPtr<UASHealthComponent> Health;
    UPROPERTY(VisibleAnywhere) TObjectPtr<UASVehicleTurretComponent> NoseGun;
    UPROPERTY(EditDefaultsOnly) float AcquireRadius=9000.f;
    UPROPERTY(EditDefaultsOnly) float OrbitRadius=1800.f;
    UPROPERTY(EditDefaultsOnly) float OrbitAltitude=900.f;
    UPROPERTY(EditDefaultsOnly) float FireInterval=0.12f;
    TWeakObjectPtr<APawn> Target;
    double NextAcquire=0.0, NextFire=0.0;
    void AcquireTarget();
};
