#include "Mission/ASMissionDirector.h"
#include "Net/UnrealNetwork.h"
AASMissionDirector::AASMissionDirector(){bReplicates=true;}
void AASMissionDirector::AdvancePhase(){if(!HasAuthority()||Phase==EASMissionPhase::Complete)return;EASMissionPhase Old=Phase;Phase=static_cast<EASMissionPhase>(static_cast<uint8>(Phase)+1);OnPhaseChanged.Broadcast(Old,Phase);ForceNetUpdate();}
void AASMissionDirector::ReportHostageRescued(){if(!HasAuthority()||Phase!=EASMissionPhase::Rescue)return;RescuedHostages=FMath::Clamp(RescuedHostages+1,0,FMath::Max(1,RequiredHostages));OnRep_RescueProgress();if(RescuedHostages>=RequiredHostages)AdvancePhase();}
void AASMissionDirector::OnRep_Phase(EASMissionPhase Old){OnPhaseChanged.Broadcast(Old,Phase);}
void AASMissionDirector::OnRep_RescueProgress(){OnRescueProgressChanged.Broadcast(RescuedHostages,RequiredHostages);}
void AASMissionDirector::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps)const{Super::GetLifetimeReplicatedProps(OutLifetimeProps);DOREPLIFETIME(AASMissionDirector,Phase);DOREPLIFETIME(AASMissionDirector,RequiredHostages);DOREPLIFETIME(AASMissionDirector,RescuedHostages);}
