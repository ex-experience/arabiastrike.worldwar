#include "Vehicles/ASChaosHummerPawn.h"
#include "Vehicles/ASVehicleDamageModelComponent.h"
#include "Vehicles/ASVehicleTurretComponent.h"
AASChaosHummerPawn::AASChaosHummerPawn(const FObjectInitializer& ObjectInitializer):Super(ObjectInitializer)
{
    bReplicates=true;
    SetReplicateMovement(true);
    Tags.Add(TEXT("Vehicle"));
    Tags.Add(TEXT("ChaosVehicle"));
    DamageModel=CreateDefaultSubobject<UASVehicleDamageModelComponent>(TEXT("DamageModel"));
    Turret=CreateDefaultSubobject<UASVehicleTurretComponent>(TEXT("Turret"));
}
