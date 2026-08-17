#include "Game/ASGameState.h"
#include "Net/UnrealNetwork.h"
void AASGameState::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME(AASGameState, ActiveWorldEvent);
    DOREPLIFETIME(AASGameState, WorldThreatLevel);
}
