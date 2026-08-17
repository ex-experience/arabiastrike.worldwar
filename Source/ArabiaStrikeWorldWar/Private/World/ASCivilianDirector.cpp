#include "World/ASCivilianDirector.h"
#include "World/ASCivilianCharacter.h"
#include "NavigationSystem.h"
#include "TimerManager.h"
#include "Engine/World.h"

AASCivilianDirector::AASCivilianDirector()
{
    PrimaryActorTick.bCanEverTick = false;
}

void AASCivilianDirector::BeginPlay()
{
    Super::BeginPlay();
    if (HasAuthority()) GetWorldTimerManager().SetTimer(SpawnTimer, this, &AASCivilianDirector::AuthorityMaintainPopulation, 2.0f, true, 0.25f);
}

void AASCivilianDirector::AuthorityMaintainPopulation()
{
    if (!HasAuthority() || CivilianClasses.IsEmpty() || SpawnAnchors.IsEmpty()) return;
    ActiveCivilians.RemoveAll([](const TWeakObjectPtr<AASCivilianCharacter>& C){ return !C.IsValid(); });
    if (ActiveCivilians.Num() >= MaxActiveCivilians) return;

    AActor* Anchor = SpawnAnchors[FMath::RandRange(0, SpawnAnchors.Num()-1)];
    if (!Anchor) return;

    FVector SpawnLocation = Anchor->GetActorLocation();
    if (UNavigationSystemV1* Nav = FNavigationSystem::GetCurrent<UNavigationSystemV1>(GetWorld()))
    {
        FNavLocation NavLocation;
        if (Nav->GetRandomReachablePointInRadius(SpawnLocation, SpawnRadius, NavLocation)) SpawnLocation = NavLocation.Location;
    }

    TSubclassOf<AASCivilianCharacter> CivilianClass = CivilianClasses[FMath::RandRange(0, CivilianClasses.Num()-1)];
    if (!CivilianClass) return;
    FActorSpawnParameters Params;
    Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn;
    if (AASCivilianCharacter* Civilian = GetWorld()->SpawnActor<AASCivilianCharacter>(CivilianClass, SpawnLocation, FRotator::ZeroRotator, Params))
    {
        ActiveCivilians.Add(Civilian);
    }
}
