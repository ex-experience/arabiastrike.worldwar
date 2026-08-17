#include "World/ASLivingWorldEventDirector.h"
#include "World/ASWorldEventDefinition.h"
#include "Game/ASGameState.h"
#include "Net/UnrealNetwork.h"
#include "TimerManager.h"
AASLivingWorldEventDirector::AASLivingWorldEventDirector(){ bReplicates=true; PrimaryActorTick.bCanEverTick=false; }
void AASLivingWorldEventDirector::BeginPlay(){ Super::BeginPlay(); if(HasAuthority()) GetWorldTimerManager().SetTimer(EvaluationTimer,this,&AASLivingWorldEventDirector::AuthorityEvaluateEvents,EvaluationIntervalSeconds,true,5.f); }
void AASLivingWorldEventDirector::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const { Super::GetLifetimeReplicatedProps(OutLifetimeProps); DOREPLIFETIME(AASLivingWorldEventDirector,ActiveEventId); DOREPLIFETIME(AASLivingWorldEventDirector,ActiveEventType); }
bool AASLivingWorldEventDirector::TryStartEvent(UASWorldEventDefinition* Definition,FName DistrictId)
{
    if(!HasAuthority()||!Definition||!ActiveEventId.IsNone()||Definition->EventId.IsNone()) return false;
    const double Now=GetWorld()->GetTimeSeconds();
    if(const double* Until=CooldownUntil.Find(Definition->EventId); Until&&Now<*Until) return false;
    if(!Definition->AllowedDistricts.IsEmpty()&&!Definition->AllowedDistricts.Contains(DistrictId)) return false;
    ActiveEventId=Definition->EventId; ActiveEventType=Definition->EventType;
    if(AASGameState* GS=GetWorld()->GetGameState<AASGameState>()){ GS->ActiveWorldEvent=ActiveEventType; GS->WorldThreatLevel=FMath::Clamp(Definition->ThreatLevel,0,5); }
    CooldownUntil.Add(Definition->EventId,Now+Definition->CooldownSeconds);
    OnRep_ActiveEvent();
    GetWorldTimerManager().SetTimer(ActiveEventTimer,this,&AASLivingWorldEventDirector::EndActiveEvent,FMath::Max(1.f,Definition->DurationSeconds),false);
    return true;
}
void AASLivingWorldEventDirector::EndActiveEvent(){ if(!HasAuthority())return; const FName Old=ActiveEventId; ActiveEventId=NAME_None; ActiveEventType=EASWorldEvent::Calm; if(AASGameState* GS=GetWorld()->GetGameState<AASGameState>()){ GS->ActiveWorldEvent=EASWorldEvent::Calm; GS->WorldThreatLevel=0; } BP_OnLivingEventEnded(Old); }
void AASLivingWorldEventDirector::OnRep_ActiveEvent(){ if(!ActiveEventId.IsNone()) BP_OnLivingEventStarted(ActiveEventId,ActiveEventType); }
void AASLivingWorldEventDirector::AuthorityEvaluateEvents(){ if(!HasAuthority()||!ActiveEventId.IsNone())return; for(UASWorldEventDefinition* Def:EventPool){ if(TryStartEvent(Def,NAME_None)) break; } }
