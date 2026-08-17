#include "World/ASTrafficDirector.h"
#include "World/ASTrafficRoute.h"
#include "World/ASTrafficVehicleAgent.h"
#include "Components/SplineComponent.h"
#include "TimerManager.h"
#include "Engine/World.h"

AASTrafficDirector::AASTrafficDirector()
{
    PrimaryActorTick.bCanEverTick = false;
    bReplicates = false;
}

void AASTrafficDirector::BeginPlay()
{
    Super::BeginPlay();
    if (HasAuthority()) GetWorldTimerManager().SetTimer(SpawnTimer, this, &AASTrafficDirector::AuthoritySpawnTraffic, SpawnIntervalSeconds, true, 0.5f);
}

void AASTrafficDirector::CompactVehicleList()
{
    ActiveVehicles.RemoveAll([](const TWeakObjectPtr<AASTrafficVehicleAgent>& Agent){ return !Agent.IsValid(); });
}

void AASTrafficDirector::AuthoritySpawnTraffic()
{
    if (!HasAuthority() || Routes.IsEmpty() || VehicleClasses.IsEmpty()) return;
    CompactVehicleList();
    if (ActiveVehicles.Num() >= MaxActiveVehicles) return;

    AASTrafficRoute* Route = Routes[FMath::RandRange(0, Routes.Num()-1)];
    TSubclassOf<AASTrafficVehicleAgent> AgentClass = VehicleClasses[FMath::RandRange(0, VehicleClasses.Num()-1)];
    if (!Route || !Route->RouteSpline || !AgentClass) return;

    const FVector SpawnLocation = Route->RouteSpline->GetLocationAtDistanceAlongSpline(0.0f, ESplineCoordinateSpace::World);
    const FRotator SpawnRotation = Route->RouteSpline->GetRotationAtDistanceAlongSpline(0.0f, ESplineCoordinateSpace::World);
    FActorSpawnParameters Params;
    Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn;
    if (AASTrafficVehicleAgent* Agent = GetWorld()->SpawnActor<AASTrafficVehicleAgent>(AgentClass, SpawnLocation, SpawnRotation, Params))
    {
        Agent->AssignRoute(Route, 0.0f);
        ActiveVehicles.Add(Agent);
    }
}
