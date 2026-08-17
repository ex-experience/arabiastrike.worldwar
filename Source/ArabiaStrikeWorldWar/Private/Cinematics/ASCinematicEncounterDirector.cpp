#include "Cinematics/ASCinematicEncounterDirector.h"
#include "GameFramework/GameStateBase.h"
#include "Net/UnrealNetwork.h"
AASCinematicEncounterDirector::AASCinematicEncounterDirector(){ bReplicates=true; PrimaryActorTick.bCanEverTick=false; }
void AASCinematicEncounterDirector::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const { Super::GetLifetimeReplicatedProps(OutLifetimeProps); DOREPLIFETIME(AASCinematicEncounterDirector,ActiveCue); }
void AASCinematicEncounterDirector::StartCinematicCue(FName CueId,bool bSkippable){ if(!HasAuthority()||CueId.IsNone())return; ActiveCue.CueId=CueId; ActiveCue.bSkippable=bSkippable; const AGameStateBase* GS=GetWorld()->GetGameState(); ActiveCue.ServerStartTime=GS?GS->GetServerWorldTimeSeconds():GetWorld()->GetTimeSeconds(); OnRep_CinematicCue(); }
void AASCinematicEncounterDirector::EndCinematicCue(){ if(!HasAuthority())return; ActiveCue=FASCinematicCueState(); BP_StopSynchronizedCue(); }
void AASCinematicEncounterDirector::OnRep_CinematicCue(){ if(ActiveCue.CueId.IsNone()) BP_StopSynchronizedCue(); else BP_PlaySynchronizedCue(ActiveCue); }
