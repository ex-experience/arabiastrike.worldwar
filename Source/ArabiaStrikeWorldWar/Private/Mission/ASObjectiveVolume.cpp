#include "Mission/ASObjectiveVolume.h"

#include "Mission/ASMissionDirector.h"
#include "Components/BoxComponent.h"
#include "GameFramework/Pawn.h"

AASObjectiveVolume::AASObjectiveVolume()
{
    bReplicates = false;

    Volume = CreateDefaultSubobject<UBoxComponent>(TEXT("Volume"));
    RootComponent = Volume;

    Volume->SetBoxExtent(FVector(300.f));

    Volume->OnComponentBeginOverlap.AddDynamic(
        this,
        &AASObjectiveVolume::Enter
    );
}

void AASObjectiveVolume::Enter(
    UPrimitiveComponent* OverlappedComponent,
    AActor* OtherActor,
    UPrimitiveComponent* OtherComp,
    int32 OtherBodyIndex,
    bool bFromSweep,
    const FHitResult& SweepResult
)
{
    if (bUsed && bOneShot)
    {
        return;
    }

    APawn* Pawn = Cast<APawn>(OtherActor);

    if (!Pawn ||
        !Pawn->IsPlayerControlled() ||
        !Director ||
        !Director->HasAuthority())
    {
        return;
    }

    bUsed = true;
    Director->AdvancePhase();
}