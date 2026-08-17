#include "World/ASDistrictVolume.h"
#include "Player/ASCharacter.h"
#include "Player/ASPlayerState.h"

AASDistrictVolume::AASDistrictVolume()
{
    bReplicates = false;
    SetActorHiddenInGame(true);
}

void AASDistrictVolume::BeginPlay()
{
    Super::BeginPlay();
    OnActorBeginOverlap.AddDynamic(this, &AASDistrictVolume::HandleBeginOverlap);
}

void AASDistrictVolume::HandleBeginOverlap(AActor* OverlappedActor, AActor* OtherActor)
{
    if (!HasAuthority()) return;
    const AASCharacter* Character = Cast<AASCharacter>(OtherActor);
    if (!Character) return;
    if (AASPlayerState* PS = Character->GetPlayerState<AASPlayerState>())
    {
        PS->SetCurrentDistrict(Profile.District);
    }
}
