#include "Offline/ASOfflineDirector.h"

#include "AI/ASSoldierCharacter.h"
#include "Animation/AnimInstance.h"
#include "Combat/ASHealthComponent.h"
#include "Combat/ASWeaponComponent.h"
#include "Combat/ASWeaponDefinition.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/SplineComponent.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/World.h"
#include "Kismet/GameplayStatics.h"
#include "Mission/ASMissionDirector.h"
#include "TimerManager.h"
#include "Vehicles/ASPilotableVehiclePawn.h"
#include "World/ASCivilianCharacter.h"
#include "World/ASTrafficRoute.h"
#include "World/ASTrafficVehicleAgent.h"

AASOfflineDirector::AASOfflineDirector()
{
    PrimaryActorTick.bCanEverTick = false;
    bReplicates = true;
}

void AASOfflineDirector::BeginPlay()
{
    Super::BeginPlay();
    if (HasAuthority())
    {
        GetWorldTimerManager().SetTimer(BootstrapTimer, this, &AASOfflineDirector::Bootstrap, 1.f, false);
    }
}

APawn* AASOfflineDirector::GetPlayerPawn() const
{
    return UGameplayStatics::GetPlayerPawn(this, 0);
}

FVector AASOfflineDirector::FindGroundedSpawn(const FVector& Desired) const
{
    if (!GetWorld()) return Desired;
    FHitResult Hit;
    FCollisionQueryParams Query(SCENE_QUERY_STAT(ASWWOfflineSpawnGround), false, this);
    if (GetWorld()->LineTraceSingleByChannel(
        Hit,
        Desired + FVector(0.f, 0.f, 1400.f),
        Desired - FVector(0.f, 0.f, 4000.f),
        ECC_Visibility,
        Query))
    {
        return Hit.ImpactPoint + FVector(0.f, 0.f, 96.f);
    }
    return Desired;
}

void AASOfflineDirector::Bootstrap()
{
    APawn* Player = GetPlayerPawn();
    if (!Player)
    {
        GetWorldTimerManager().SetTimer(BootstrapTimer, this, &AASOfflineDirector::Bootstrap, .5f, false);
        return;
    }

    RifleDefinition = LoadObject<UASWeaponDefinition>(
        nullptr,
        TEXT("/Game/Weapons/Definitions/DA_ASWW_Rifle_01.DA_ASWW_Rifle_01"));

    EnsureMissionDirector();
    EquipPlayer();

    const FVector PlayerLocation = Player->GetActorLocation();
    VehicleTransitionLocation = FindGroundedSpawn(PlayerLocation + Player->GetActorForwardVector() * 700.f);
    ExtractionLocation = FindGroundedSpawn(PlayerLocation + Player->GetActorForwardVector() * 3200.f);

    SpawnCivilianPopulation(14);
    SpawnTrafficLoop(7);
    SpawnTacticalVehicle();
    AdoptExistingEnemies();
    SpawnEnemyWave(5, 1500.f);
    for (AASCivilianCharacter* Civilian : Civilians)
    {
        if (IsValid(Civilian)) Civilian->NotifyThreat(PlayerLocation, .85f);
    }

    Stage = EASOfflineMissionStage::StreetCombat;
    ObjectiveText = TEXT("OBJECTIVE 01  |  CLEAR THE HOSTILE FIRETEAM");
    if (MissionDirector) MissionDirector->AdvancePhase();

    GetWorldTimerManager().SetTimer(ProgressTimer, this, &AASOfflineDirector::CheckProgress, .5f, true, .5f);
    UE_LOG(LogTemp, Warning, TEXT("ASWW_OFFLINE_BOOT rifle=%d enemies=%d civilians=%d traffic=%d vehicle=%d"),
        RifleDefinition ? 1 : 0,
        GetLivingEnemyCount(),
        GetCivilianCount(),
        GetTrafficVehicleCount(),
        IsValid(TacticalVehicle) ? 1 : 0);
}

void AASOfflineDirector::EnsureMissionDirector()
{
    MissionDirector = Cast<AASMissionDirector>(
        UGameplayStatics::GetActorOfClass(this, AASMissionDirector::StaticClass()));
    if (!MissionDirector && GetWorld())
    {
        MissionDirector = GetWorld()->SpawnActor<AASMissionDirector>(
            AASMissionDirector::StaticClass(), FVector::ZeroVector, FRotator::ZeroRotator);
    }
}

void AASOfflineDirector::EquipPlayer()
{
    APawn* Player = GetPlayerPawn();
    if (!Player || !RifleDefinition) return;
    if (UASWeaponComponent* Weapon = Player->FindComponentByClass<UASWeaponComponent>())
    {
        Weapon->EquipDefinition(RifleDefinition);
    }
}

void AASOfflineDirector::ConfigureSoldier(AASSoldierCharacter* Soldier)
{
    if (!Soldier) return;
    if (RifleDefinition)
    {
        if (UASWeaponComponent* Weapon = Soldier->GetWeaponComponent()) Weapon->EquipDefinition(RifleDefinition);
    }

    USkeletalMeshComponent* Body = Soldier->GetMesh();
    if (!Body) return;
    if (USkeletalMesh* Manny = LoadObject<USkeletalMesh>(
        nullptr,
        TEXT("/Game/Characters/Mannequins/Meshes/SKM_Manny_Simple.SKM_Manny_Simple")))
    {
        Body->SetSkeletalMeshAsset(Manny);
        Body->SetRelativeLocation(FVector(0.f, 0.f, -90.f));
        Body->SetRelativeRotation(FRotator(0.f, -90.f, 0.f));
        Body->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    }
    if (UClass* AnimClass = LoadClass<UAnimInstance>(
        nullptr,
        TEXT("/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed.ABP_Unarmed_C")))
    {
        Body->SetAnimInstanceClass(AnimClass);
    }

    if (Soldier->GetComponentsByTag(USkeletalMeshComponent::StaticClass(), TEXT("OfflineRifle")).IsEmpty())
    {
        if (USkeletalMesh* RifleMesh = LoadObject<USkeletalMesh>(
            nullptr,
            TEXT("/Game/Weapons/Rifle/Meshes/SKM_Rifle.SKM_Rifle")))
        {
            USkeletalMeshComponent* Rifle = NewObject<USkeletalMeshComponent>(Soldier, TEXT("OfflineRifleMesh"));
            if (Rifle)
            {
                Rifle->ComponentTags.Add(TEXT("OfflineRifle"));
                Rifle->SetSkeletalMeshAsset(RifleMesh);
                Rifle->SetCollisionEnabled(ECollisionEnabled::NoCollision);
                Rifle->SetGenerateOverlapEvents(false);
                Soldier->AddInstanceComponent(Rifle);
                Rifle->RegisterComponent();
                Rifle->AttachToComponent(
                    Body,
                    FAttachmentTransformRules::SnapToTargetNotIncludingScale,
                    TEXT("HandGrip_R"));
            }
        }
    }
}

void AASOfflineDirector::AdoptExistingEnemies()
{
    TArray<AActor*> Existing;
    UGameplayStatics::GetAllActorsOfClass(this, AASSoldierCharacter::StaticClass(), Existing);
    for (AActor* Actor : Existing)
    {
        if (AASSoldierCharacter* Soldier = Cast<AASSoldierCharacter>(Actor))
        {
            ConfigureSoldier(Soldier);
            ActiveEnemies.AddUnique(Soldier);
        }
    }
}

void AASOfflineDirector::SpawnEnemyWave(int32 DesiredTotal, float Radius)
{
    APawn* Player = GetPlayerPawn();
    if (!Player || !GetWorld()) return;
    const int32 Missing = FMath::Max(0, DesiredTotal - GetLivingEnemyCount());
    for (int32 Index = 0; Index < Missing; ++Index)
    {
        const float Angle = (2.f * PI * Index) / FMath::Max(1, Missing);
        const float SpawnRadius = Radius + (Index % 2) * 260.f;
        const FVector Offset(FMath::Cos(Angle) * SpawnRadius, FMath::Sin(Angle) * SpawnRadius, 0.f);
        const FVector Location = FindGroundedSpawn(Player->GetActorLocation() + Offset);
        const FRotator Rotation = (Player->GetActorLocation() - Location).Rotation();
        FActorSpawnParameters Params;
        Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn;
        if (AASSoldierCharacter* Soldier = GetWorld()->SpawnActor<AASSoldierCharacter>(
            AASSoldierCharacter::StaticClass(), Location, Rotation, Params))
        {
            ConfigureSoldier(Soldier);
            ActiveEnemies.AddUnique(Soldier);
        }
    }
}

void AASOfflineDirector::SpawnCivilianPopulation(int32 Count)
{
    APawn* Player = GetPlayerPawn();
    if (!Player || !GetWorld()) return;
    for (int32 Index = 0; Index < Count; ++Index)
    {
        const float Angle = (2.f * PI * Index) / FMath::Max(1, Count);
        const float Radius = 650.f + (Index % 4) * 220.f;
        const FVector Offset(FMath::Cos(Angle) * Radius, FMath::Sin(Angle) * Radius, 0.f);
        const FVector Location = FindGroundedSpawn(Player->GetActorLocation() + Offset);
        FActorSpawnParameters Params;
        Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn;
        if (AASCivilianCharacter* Civilian = GetWorld()->SpawnActor<AASCivilianCharacter>(
            AASCivilianCharacter::StaticClass(), Location, FRotator(0.f, Angle * 57.29578f, 0.f), Params))
        {
            Civilians.Add(Civilian);
        }
    }
}

void AASOfflineDirector::SpawnTrafficLoop(int32 Count)
{
    APawn* Player = GetPlayerPawn();
    if (!Player || !GetWorld()) return;

    const FVector Center = Player->GetActorLocation();
    TrafficRoute = GetWorld()->SpawnActor<AASTrafficRoute>(
        AASTrafficRoute::StaticClass(), Center, FRotator::ZeroRotator);
    if (!TrafficRoute || !TrafficRoute->RouteSpline) return;

    USplineComponent* Spline = TrafficRoute->RouteSpline;
    Spline->ClearSplinePoints(false);
    const TArray<FVector> RoutePoints = {
        FindGroundedSpawn(Center + FVector(-1800.f, -1200.f, 0.f)) - FVector(0.f, 0.f, 42.f),
        FindGroundedSpawn(Center + FVector(1800.f, -1200.f, 0.f)) - FVector(0.f, 0.f, 42.f),
        FindGroundedSpawn(Center + FVector(1800.f, 1200.f, 0.f)) - FVector(0.f, 0.f, 42.f),
        FindGroundedSpawn(Center + FVector(-1800.f, 1200.f, 0.f)) - FVector(0.f, 0.f, 42.f)
    };
    for (const FVector& Point : RoutePoints)
    {
        Spline->AddSplinePoint(Point, ESplineCoordinateSpace::World, false);
    }
    Spline->SetClosedLoop(true, true);

    const float Length = Spline->GetSplineLength();
    for (int32 Index = 0; Index < Count; ++Index)
    {
        const float Distance = Length * static_cast<float>(Index) / FMath::Max(1, Count);
        const FVector Location = Spline->GetLocationAtDistanceAlongSpline(Distance, ESplineCoordinateSpace::World)
            + FVector(0.f, 0.f, 65.f);
        const FRotator Rotation = Spline->GetRotationAtDistanceAlongSpline(Distance, ESplineCoordinateSpace::World);
        FActorSpawnParameters Params;
        Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn;
        if (AASTrafficVehicleAgent* Vehicle = GetWorld()->SpawnActor<AASTrafficVehicleAgent>(
            AASTrafficVehicleAgent::StaticClass(), Location, Rotation, Params))
        {
            Vehicle->AssignRoute(TrafficRoute, Distance);
            TrafficVehicles.Add(Vehicle);
        }
    }
}

void AASOfflineDirector::SpawnTacticalVehicle()
{
    APawn* Player = GetPlayerPawn();
    if (!Player || !GetWorld()) return;
    const FVector Location = FindGroundedSpawn(
        Player->GetActorLocation() + Player->GetActorRightVector() * 420.f + Player->GetActorForwardVector() * 280.f)
        - FVector(0.f, 0.f, 48.f);
    FActorSpawnParameters Params;
    Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn;
    TacticalVehicle = GetWorld()->SpawnActor<AASPilotableVehiclePawn>(
        AASPilotableVehiclePawn::StaticClass(), Location, Player->GetActorRotation(), Params);
}

int32 AASOfflineDirector::GetLivingEnemyCount() const
{
    int32 Count = 0;
    for (AASSoldierCharacter* Soldier : ActiveEnemies)
    {
        if (!IsValid(Soldier)) continue;
        const UASHealthComponent* Health = Soldier->FindComponentByClass<UASHealthComponent>();
        if (!Health || !Health->IsDead()) ++Count;
    }
    return Count;
}

int32 AASOfflineDirector::GetCivilianCount() const
{
    int32 Count = 0;
    for (AASCivilianCharacter* Civilian : Civilians) if (IsValid(Civilian)) ++Count;
    return Count;
}

int32 AASOfflineDirector::GetTrafficVehicleCount() const
{
    int32 Count = 0;
    for (AASTrafficVehicleAgent* Vehicle : TrafficVehicles) if (IsValid(Vehicle)) ++Count;
    return Count;
}

float AASOfflineDirector::GetObjectiveDistance() const
{
    const APawn* Player = GetPlayerPawn();
    if (!Player) return -1.f;
    if (Stage == EASOfflineMissionStage::VehicleTransition && IsValid(TacticalVehicle))
    {
        return FVector::Dist(Player->GetActorLocation(), TacticalVehicle->GetActorLocation());
    }
    if (Stage == EASOfflineMissionStage::Extraction)
    {
        return FVector::Dist(Player->GetActorLocation(), ExtractionLocation);
    }
    return -1.f;
}

void AASOfflineDirector::CheckProgress()
{
    APawn* Player = GetPlayerPawn();
    if (!Player) return;

    for (AASSoldierCharacter* Soldier : ActiveEnemies)
    {
        if (!IsValid(Soldier)) continue;
        if (UASWeaponComponent* Weapon = Soldier->GetWeaponComponent())
        {
            const FASAmmoState Ammo = Weapon->GetAmmo();
            if (Ammo.Magazine <= 2 && Ammo.Reserve > 0 && !Weapon->IsReloading()) Weapon->RequestReload();
        }
    }

    const int32 LivingEnemies = GetLivingEnemyCount();
    if (Stage == EASOfflineMissionStage::StreetCombat && LivingEnemies == 0)
    {
        Stage = EASOfflineMissionStage::VehicleTransition;
        ObjectiveText = TEXT("OBJECTIVE 02  |  ENTER THE TACTICAL 4X4  [F]");
        if (MissionDirector) MissionDirector->AdvancePhase();
        return;
    }

    if (Stage == EASOfflineMissionStage::VehicleTransition && Cast<AASPilotableVehiclePawn>(Player))
    {
        ActiveEnemies.Empty();
        SpawnEnemyWave(7, 2100.f);
        Stage = EASOfflineMissionStage::Reinforcements;
        ObjectiveText = TEXT("OBJECTIVE 03  |  BREAK THE REINFORCEMENT WAVE");
        if (MissionDirector) MissionDirector->AdvancePhase();
        return;
    }

    if (Stage == EASOfflineMissionStage::Reinforcements && LivingEnemies == 0)
    {
        Stage = EASOfflineMissionStage::Extraction;
        ObjectiveText = TEXT("OBJECTIVE 04  |  REACH RED SEA EXTRACTION");
        for (AASCivilianCharacter* Civilian : Civilians)
        {
            if (IsValid(Civilian)) Civilian->BeginEvacuation(ExtractionLocation);
        }
        if (MissionDirector) MissionDirector->AdvancePhase();
        return;
    }

    if (Stage == EASOfflineMissionStage::Extraction &&
        FVector::Dist(Player->GetActorLocation(), ExtractionLocation) <= 350.f)
    {
        Stage = EASOfflineMissionStage::Complete;
        ObjectiveText = TEXT("MISSION COMPLETE  |  JEDDAH RED SEA DISTRICT SECURED");
        if (MissionDirector) MissionDirector->AdvancePhase();
        GetWorldTimerManager().ClearTimer(ProgressTimer);
        UE_LOG(LogTemp, Warning, TEXT("ASWW_OFFLINE_MISSION_COMPLETE"));
    }
}
