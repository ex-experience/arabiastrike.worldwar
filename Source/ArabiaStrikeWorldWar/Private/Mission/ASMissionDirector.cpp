#include "Mission/ASMissionDirector.h"
#include "Net/UnrealNetwork.h"
AASMissionDirector::AASMissionDirector(){bReplicates=true;}
void AASMissionDirector::AdvancePhase(){if(!HasAuthority()||Phase==EASMissionPhase::Complete)return;EASMissionPhase Old=Phase;Phase=static_cast<EASMissionPhase>(static_cast<uint8>(Phase)+1);OnPhaseChanged.Broadcast(Old,Phase);ForceNetUpdate();}
void AASMissionDirector::OnRep_Phase(EASMissionPhase Old){OnPhaseChanged.Broadcast(Old,Phase);}void AASMissionDirector::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>&O)const{Super::GetLifetimeReplicatedProps(O);DOREPLIFETIME(AASMissionDirector,Phase);}
