#include "World/ASTrafficVehicleAgent.h"
#include "World/ASTrafficRoute.h"
#include "Components/StaticMeshComponent.h"
#include "Components/SplineComponent.h"
#include "Engine/StaticMesh.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Net/UnrealNetwork.h"
#include "UObject/ConstructorHelpers.h"

AASTrafficVehicleAgent::AASTrafficVehicleAgent()
{
    bReplicates = true;
    SetReplicateMovement(true);
    PrimaryActorTick.bCanEverTick = true;
    PrimaryActorTick.TickInterval = 0.05f;

    VehicleMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("VehicleMesh"));
    SetRootComponent(VehicleMesh);
    VehicleMesh->SetMobility(EComponentMobility::Movable);
    VehicleMesh->SetCollisionProfileName(TEXT("BlockAllDynamic"));
    static ConstructorHelpers::FObjectFinder<UStaticMesh> SportsCarMesh(TEXT("/Game/Vehicles/SportsCar/SM_SportsCar.SM_SportsCar"));
    if (SportsCarMesh.Succeeded()) VehicleMesh->SetStaticMesh(SportsCarMesh.Object);
    else
    {
        VehicleMesh->SetRelativeScale3D(FVector(2.4f, 1.05f, 0.55f));
        static ConstructorHelpers::FObjectFinder<UStaticMesh> BodyMesh(TEXT("/Engine/BasicShapes/Cube.Cube"));
        if (BodyMesh.Succeeded()) VehicleMesh->SetStaticMesh(BodyMesh.Object);
    }
    Tags.Add(TEXT("TrafficVehicle"));
}

void AASTrafficVehicleAgent::BeginPlay()
{
    Super::BeginPlay();
    if (VehicleMesh && VehicleMesh->GetNumMaterials() > 0)
    {
        if (UMaterialInstanceDynamic* Paint = VehicleMesh->CreateAndSetMaterialInstanceDynamic(0))
        {
            const uint32 Hash = GetTypeHash(GetActorLocation());
            const FLinearColor Palette[] = {
                FLinearColor(.04f, .06f, .08f), FLinearColor(.55f, .03f, .02f),
                FLinearColor(.75f, .78f, .82f), FLinearColor(.04f, .18f, .32f)};
            Paint->SetVectorParameterValue(TEXT("BaseColor"), Palette[Hash % UE_ARRAY_COUNT(Palette)]);
            Paint->SetVectorParameterValue(TEXT("Color"), Palette[Hash % UE_ARRAY_COUNT(Palette)]);
        }
    }
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
