#include "World/ASWorldEventDirector.h"
#include "Game/ASGameState.h"
#include "Engine/World.h"
AASWorldEventDirector::AASWorldEventDirector() { bReplicates = true; PrimaryActorTick.bCanEverTick = false; }
void AASWorldEventDirector::BeginPlay() { Super::BeginPlay(); }
void AASWorldEventDirector::StartEvent(EASWorldEvent Event, int32 Threat)
{
    if (!HasAuthority()) return;
    if (AASGameState* GS = GetWorld()->GetGameState<AASGameState>()) { GS->ActiveWorldEvent = Event; GS->WorldThreatLevel = FMath::Clamp(Threat,0,5); }
}
void AASWorldEventDirector::EndEvent() { StartEvent(EASWorldEvent::Calm, 0); }
