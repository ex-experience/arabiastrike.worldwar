#include "World/ASWorldBootstrap.h"
#include "Engine/World.h"
#include "Kismet/GameplayStatics.h"

AASWorldBootstrap::AASWorldBootstrap()
{
    PrimaryActorTick.bCanEverTick = false;
    bReplicates = false;
}

bool AASWorldBootstrap::IsWorldPartitionActive() const
{
    return GetWorld() && GetWorld()->GetWorldPartition() != nullptr;
}

void AASWorldBootstrap::SpawnDirectorIfMissing(TSubclassOf<AActor> ActorClass)
{
    if (!HasAuthority() || !ActorClass || !GetWorld()) return;
    if (UGameplayStatics::GetActorOfClass(this, ActorClass)) return;
    GetWorld()->SpawnActor<AActor>(ActorClass, GetActorLocation(), FRotator::ZeroRotator);
}

void AASWorldBootstrap::BeginPlay()
{
    Super::BeginPlay();
    if (bRequireWorldPartition && !IsWorldPartitionActive())
    {
        UE_LOG(LogTemp, Error, TEXT("ASWW Phase 4: Jeddah World requires a World Partition map. Create the level from Unreal's Open World template or convert it before production use."));
    }
    if (HasAuthority())
    {
        SpawnDirectorIfMissing(EnvironmentDirectorClass);
        SpawnDirectorIfMissing(EncounterDirectorClass);
        SpawnDirectorIfMissing(WorldEventDirectorClass);
    }
}
