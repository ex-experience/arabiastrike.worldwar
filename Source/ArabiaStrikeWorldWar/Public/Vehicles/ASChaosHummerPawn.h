#pragma once
#include "CoreMinimal.h"
#include "WheeledVehiclePawn.h"
#include "ASChaosHummerPawn.generated.h"
class UASVehicleDamageModelComponent;
class UASVehicleTurretComponent;

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASChaosHummerPawn : public AWheeledVehiclePawn
{
    GENERATED_BODY()
public:
    AASChaosHummerPawn(const FObjectInitializer& ObjectInitializer);
    UPROPERTY(VisibleAnywhere,BlueprintReadOnly,Category="Hummer") TObjectPtr<UASVehicleDamageModelComponent> DamageModel;
    UPROPERTY(VisibleAnywhere,BlueprintReadOnly,Category="Hummer") TObjectPtr<UASVehicleTurretComponent> Turret;
    UPROPERTY(EditAnywhere,BlueprintReadOnly,Category="Hummer") FName VehicleArchetype=TEXT("HUMMER_ASSAULT");
    UFUNCTION(BlueprintImplementableEvent,Category="Hummer") void BP_ConfigureChaosVehiclePresentation();
};
