#include "Offline/ASOfflineLivingCityDirector.h"

#include "Offline/ASOfflineDirector.h"
#include "World/ASCivilianCharacter.h"
#include "World/ASTrafficVehicleAgent.h"
#include "World/ASWorldEnvironmentDirector.h"
#include "Components/HierarchicalInstancedStaticMeshComponent.h"
#include "Components/SceneComponent.h"
#include "Engine/DirectionalLight.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "Kismet/GameplayStatics.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "TimerManager.h"
#include "UObject/ConstructorHelpers.h"

AASOfflineLivingCityDirector::AASOfflineLivingCityDirector()
{
    PrimaryActorTick.bCanEverTick = false;

    SceneRoot = CreateDefaultSubobject<USceneComponent>(TEXT("SceneRoot"));
    SetRootComponent(SceneRoot);

    BuildingInstances = CreateDefaultSubobject<UHierarchicalInstancedStaticMeshComponent>(TEXT("CityBuildings"));
    BuildingInstances->SetupAttachment(SceneRoot);
    BuildingInstances->SetCollisionProfileName(TEXT("BlockAll"));

    RoadInstances = CreateDefaultSubobject<UHierarchicalInstancedStaticMeshComponent>(TEXT("CityRoads"));
    RoadInstances->SetupAttachment(SceneRoot);
    RoadInstances->SetCollisionEnabled(ECollisionEnabled::NoCollision);

    StreetLightInstances = CreateDefaultSubobject<UHierarchicalInstancedStaticMeshComponent>(TEXT("StreetLights"));
    StreetLightInstances->SetupAttachment(SceneRoot);
    StreetLightInstances->SetCollisionEnabled(ECollisionEnabled::NoCollision);

    static ConstructorHelpers::FObjectFinder<UStaticMesh> Cube(TEXT("/Engine/BasicShapes/Cube.Cube"));
    static ConstructorHelpers::FObjectFinder<UStaticMesh> Cylinder(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
    if (Cube.Succeeded())
    {
        BuildingInstances->SetStaticMesh(Cube.Object);
        RoadInstances->SetStaticMesh(Cube.Object);
    }
    if (Cylinder.Succeeded()) StreetLightInstances->SetStaticMesh(Cylinder.Object);
}

void AASOfflineLivingCityDirector::BeginPlay()
{
    Super::BeginPlay();
    if (HasAuthority())
    {
        GetWorldTimerManager().SetTimer(
            BootstrapTimer, this, &AASOfflineLivingCityDirector::BootstrapLivingCity, .5f, true, .25f);
    }
}

FVector AASOfflineLivingCityDirector::FindGround(const FVector& Desired) const
{
    if (!GetWorld()) return Desired;
    FHitResult Hit;
    FCollisionQueryParams Query(SCENE_QUERY_STAT(ASWWLivingCityGround), false, this);
    if (GetWorld()->LineTraceSingleByChannel(
        Hit,
        Desired + FVector(0.f, 0.f, 1800.f),
        Desired - FVector(0.f, 0.f, 4000.f),
        ECC_Visibility,
        Query))
    {
        return Hit.ImpactPoint;
    }
    return Desired;
}

void AASOfflineLivingCityDirector::BootstrapLivingCity()
{
    if (bBootstrapped || !HasAuthority() || !GetWorld()) return;
    APawn* Player = UGameplayStatics::GetPlayerPawn(this, 0);
    if (!Player) return;

    bBootstrapped = true;
    GetWorldTimerManager().ClearTimer(BootstrapTimer);
    const FVector Center = FindGround(Player->GetActorLocation());
    if (bCreateProceduralCityBlocks) BuildCityBlocks(Center);

    EnvironmentDirector = Cast<AASWorldEnvironmentDirector>(
        UGameplayStatics::GetActorOfClass(this, AASWorldEnvironmentDirector::StaticClass()));
    if (!EnvironmentDirector)
    {
        EnvironmentDirector = GetWorld()->SpawnActor<AASWorldEnvironmentDirector>(
            AASWorldEnvironmentDirector::StaticClass(), Center, FRotator::ZeroRotator);
    }
    if (EnvironmentDirector)
    {
        EnvironmentDirector->GameMinutesPerRealSecond = 4.f;
        EnvironmentDirector->SetTimeOfDay(16.75f);
    }

    GetWorldTimerManager().SetTimer(
        SimulationTimer, this, &AASOfflineLivingCityDirector::UpdateSimulation, 2.f, true, 1.f);
    UE_LOG(LogTemp, Warning,
        TEXT("ASWW_LIVING_CITY_BOOT buildings=%d roads=%d lights=%d civilians=%d traffic=%d"),
        GetBuildingCount(), GetRoadCount(), StreetLightInstances->GetInstanceCount(),
        GetCivilianCount(), GetTrafficCount());
}

void AASOfflineLivingCityDirector::BuildCityBlocks(const FVector& Center)
{
    if (UMaterialInterface* BaseMaterial = LoadObject<UMaterialInterface>(
        nullptr, TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial")))
    {
        if (UMaterialInstanceDynamic* Material = UMaterialInstanceDynamic::Create(BaseMaterial, this))
        {
            Material->SetVectorParameterValue(TEXT("Color"), FLinearColor(.28f, .31f, .34f));
            BuildingInstances->SetMaterial(0, Material);
        }
        if (UMaterialInstanceDynamic* Material = UMaterialInstanceDynamic::Create(BaseMaterial, this))
        {
            Material->SetVectorParameterValue(TEXT("Color"), FLinearColor(.025f, .03f, .035f));
            RoadInstances->SetMaterial(0, Material);
        }
        if (UMaterialInstanceDynamic* Material = UMaterialInstanceDynamic::Create(BaseMaterial, this))
        {
            Material->SetVectorParameterValue(TEXT("Color"), FLinearColor(.08f, .09f, .1f));
            StreetLightInstances->SetMaterial(0, Material);
        }
    }

    const float GroundZ = Center.Z + 3.f;
    const FVector LongRoadScale(48.f, 4.2f, .06f);
    const FVector EastWestOffsets[] = {
        FVector(0.f, 0.f, 0.f), FVector(0.f, 2500.f, 0.f), FVector(0.f, -2500.f, 0.f)};
    const FVector NorthSouthOffsets[] = {
        FVector(0.f, 0.f, .5f), FVector(2500.f, 0.f, .5f), FVector(-2500.f, 0.f, .5f)};
    for (const FVector& Offset : EastWestOffsets)
    {
        RoadInstances->AddInstance(FTransform(
            FRotator::ZeroRotator, FVector(Center.X + Offset.X, Center.Y + Offset.Y, GroundZ), LongRoadScale), true);
    }
    for (const FVector& Offset : NorthSouthOffsets)
    {
        RoadInstances->AddInstance(FTransform(
            FRotator(0.f, 90.f, 0.f),
            FVector(Center.X + Offset.X, Center.Y + Offset.Y, GroundZ + Offset.Z),
            LongRoadScale), true);
    }

    const int32 Coordinates[] = {-4200, -3400, -1700, -900, 900, 1700, 3400, 4200};
    for (const int32 X : Coordinates)
    {
        for (const int32 Y : Coordinates)
        {
            if (FMath::Abs(X) < 700 || FMath::Abs(Y) < 700 ||
                FMath::Abs(FMath::Abs(X) - 2500) < 450 || FMath::Abs(FMath::Abs(Y) - 2500) < 450)
            {
                continue;
            }
            const uint32 Hash = HashCombine(GetTypeHash(X), GetTypeHash(Y));
            const float Height = 650.f + static_cast<float>(Hash % 1850u);
            const float Width = 520.f + static_cast<float>((Hash >> 5u) % 220u);
            const float Depth = 500.f + static_cast<float>((Hash >> 9u) % 250u);
            const FVector Location(Center.X + X, Center.Y + Y, GroundZ + Height * .5f);
            BuildingInstances->AddInstance(FTransform(
                FRotator(0.f, static_cast<float>((Hash >> 12u) % 4u) * 90.f, 0.f),
                Location,
                FVector(Width / 100.f, Depth / 100.f, Height / 100.f)), true);
        }
    }

    const FVector TowerOffsets[] = {
        FVector(4300.f, 4300.f, 0.f), FVector(-4300.f, 4300.f, 0.f),
        FVector(4300.f, -4300.f, 0.f), FVector(-4300.f, -4300.f, 0.f)};
    for (int32 Index = 0; Index < UE_ARRAY_COUNT(TowerOffsets); ++Index)
    {
        const float Height = 2600.f + Index * 380.f;
        FVector Location = Center + TowerOffsets[Index];
        Location.Z = GroundZ + Height * .5f;
        BuildingInstances->AddInstance(FTransform(
            FRotator::ZeroRotator, Location, FVector(8.f, 8.f, Height / 100.f)), true);
    }

    for (int32 Step = -4; Step <= 4; ++Step)
    {
        const float Offset = Step * 900.f;
        const FVector PoleScale(.09f, .09f, 3.2f);
        StreetLightInstances->AddInstance(FTransform(
            FRotator::ZeroRotator, Center + FVector(Offset, 520.f, 160.f), PoleScale), true);
        StreetLightInstances->AddInstance(FTransform(
            FRotator::ZeroRotator, Center + FVector(Offset, -520.f, 160.f), PoleScale), true);
        StreetLightInstances->AddInstance(FTransform(
            FRotator::ZeroRotator, Center + FVector(520.f, Offset, 160.f), PoleScale), true);
        StreetLightInstances->AddInstance(FTransform(
            FRotator::ZeroRotator, Center + FVector(-520.f, Offset, 160.f), PoleScale), true);
    }
}

void AASOfflineLivingCityDirector::UpdateSimulation()
{
    if (!HasAuthority()) return;
    APawn* Player = UGameplayStatics::GetPlayerPawn(this, 0);
    const AASOfflineDirector* Mission = Cast<AASOfflineDirector>(
        UGameplayStatics::GetActorOfClass(this, AASOfflineDirector::StaticClass()));
    const bool bCombatActive = Mission &&
        (Mission->GetOfflineStage() == EASOfflineMissionStage::StreetCombat ||
         Mission->GetOfflineStage() == EASOfflineMissionStage::Reinforcements);
    const bool bThreatResponse = bCombatActive && GetWorld()->GetTimeSeconds() > 18.f && Player;

    TArray<AActor*> Civilians;
    UGameplayStatics::GetAllActorsOfClass(this, AASCivilianCharacter::StaticClass(), Civilians);
    for (AActor* Actor : Civilians)
    {
        AASCivilianCharacter* Civilian = Cast<AASCivilianCharacter>(Actor);
        if (!Civilian || !Player) continue;
        const float Distance = FVector::Dist2D(Civilian->GetActorLocation(), Player->GetActorLocation());
        if (bThreatResponse && Distance < 2400.f && Civilian->Reaction == EASCivilianReaction::Calm)
        {
            Civilian->NotifyThreat(Player->GetActorLocation(), .85f);
        }
        else if (!bCombatActive && Civilian->Reaction != EASCivilianReaction::Calm)
        {
            Civilian->ReturnToRoutine();
        }
    }

    TArray<AActor*> Vehicles;
    UGameplayStatics::GetAllActorsOfClass(this, AASTrafficVehicleAgent::StaticClass(), Vehicles);
    for (AActor* Actor : Vehicles)
    {
        if (AASTrafficVehicleAgent* Vehicle = Cast<AASTrafficVehicleAgent>(Actor))
        {
            Vehicle->SetTrafficBehavior(
                bThreatResponse ? EASTrafficBehavior::Evacuating : EASTrafficBehavior::Normal);
        }
    }

    if (EnvironmentDirector)
    {
        TArray<AActor*> SunActors;
        UGameplayStatics::GetAllActorsOfClass(this, ADirectionalLight::StaticClass(), SunActors);
        if (!SunActors.IsEmpty())
        {
            SunActors[0]->SetActorRotation(FRotator(EnvironmentDirector->GetSunPitchDegrees(), -35.f, 0.f));
        }
    }
}

int32 AASOfflineLivingCityDirector::GetBuildingCount() const
{
    return BuildingInstances ? BuildingInstances->GetInstanceCount() : 0;
}

int32 AASOfflineLivingCityDirector::GetRoadCount() const
{
    return RoadInstances ? RoadInstances->GetInstanceCount() : 0;
}

int32 AASOfflineLivingCityDirector::GetCivilianCount() const
{
    TArray<AActor*> Actors;
    UGameplayStatics::GetAllActorsOfClass(this, AASCivilianCharacter::StaticClass(), Actors);
    return Actors.Num();
}

int32 AASOfflineLivingCityDirector::GetTrafficCount() const
{
    TArray<AActor*> Actors;
    UGameplayStatics::GetAllActorsOfClass(this, AASTrafficVehicleAgent::StaticClass(), Actors);
    return Actors.Num();
}

float AASOfflineLivingCityDirector::GetTimeOfDayHours() const
{
    return EnvironmentDirector ? EnvironmentDirector->EnvironmentState.TimeOfDayHours : 0.f;
}
