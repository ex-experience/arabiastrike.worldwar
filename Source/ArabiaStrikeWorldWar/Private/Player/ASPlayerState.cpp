#include "Player/ASPlayerState.h"
#include "Net/UnrealNetwork.h"
void AASPlayerState::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME(AASPlayerState, SquadId);
    DOREPLIFETIME(AASPlayerState, TeamId);
    DOREPLIFETIME(AASPlayerState, Kills);
    DOREPLIFETIME(AASPlayerState, Deaths);
    DOREPLIFETIME(AASPlayerState, XP);
}
