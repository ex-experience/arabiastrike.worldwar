#include "World/ASTrafficVehicleAgent.h"
#include "World/ASTrafficRoute.h"
#include "Components/SplineComponent.h"
#include "Net/UnrealNetwork.h"

AASTrafficVehicleAgent::AASTrafficVehicleAgent()
{
    bReplicates = true;
    SetReplicateMovement(true);
    PrimaryActorTick.bCanEverTick = true;
    PrimaryActorTick.TickInterval = 0.05f;
}

void AASTrafficVehicleAgent::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME(AASTrafficVehicleAgent, DistanceAlongRoute);
    DOREPLIFETIME(AASTrafficVehicleAgent, TrafficBehavior);
}

void AASTrafficVehicleAgent::SetTrafficBehavior(EASTrafficBehavior NewBehavior)
{ if (!HasAuthority()) return; TrafficBehavior=NewBehavior; }

void AASTrafficVehicleAgent::AssignRoute(AASTrafficRoute* Route, float InitialDistance)
{
    if (!HasAuthority()) return;
    AssignedRoute = Route;
    DistanceAlongRoute = FMath::Max(0.0f, InitialDistance);
}

void AASTrafficVehicleAgent::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    if (!HasAuthority() || !AssignedRoute || !AssignedRoute->RouteSpline) return;

    const float Length = AssignedRoute->RouteSpline->GetSplineLength();
    if (Length <= KINDA_SMALL_NUMBER) return;

    if (TrafficBehavior==EASTrafficBehavior::Stopped) return;
    const float BehaviorScale = TrafficBehavior==EASTrafficBehavior::Yielding ? 0.35f : TrafficBehavior==EASTrafficBehavior::Evacuating ? 1.25f : 1.0f;
    const float Speed = FMath::Min(CruiseSpeedCmPerSecond, AssignedRoute->SpeedLimitCmPerSecond) * BehaviorScale;
    DistanceAlongRoute += Speed * DeltaSeconds;
    if (DistanceAlongRoute >= Length)
    {
        if (AssignedRoute->bLoop) DistanceAlongRoute = FMath::Fmod(DistanceAlongRoute, Length);
        else { Destroy(); return; }
    }

    const FVector Location = AssignedRoute->RouteSpline->GetLocationAtDistanceAlongSpline(DistanceAlongRoute, ESplineCoordinateSpace::World);
    const FRotator Rotation = AssignedRoute->RouteSpline->GetRotationAtDistanceAlongSpline(DistanceAlongRoute, ESplineCoordinateSpace::World);
    SetActorLocationAndRotation(Location, Rotation, false, nullptr, ETeleportType::None);
}
