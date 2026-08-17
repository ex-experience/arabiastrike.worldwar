#include "World/ASTrafficRoute.h"
#include "Components/SplineComponent.h"

AASTrafficRoute::AASTrafficRoute()
{
    PrimaryActorTick.bCanEverTick = false;
    RouteSpline = CreateDefaultSubobject<USplineComponent>(TEXT("TrafficRouteSpline"));
    SetRootComponent(RouteSpline);
}
