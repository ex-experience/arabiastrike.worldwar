#include "World/ASSecurityResponseDirector.h"
#include "Game/ASGameState.h"
#include "EngineUtils.h"
#include "Net/UnrealNetwork.h"
#include "TimerManager.h"
AASSecurityResponseDirector::AASSecurityResponseDirector(){ bReplicates=true; PrimaryActorTick.bCanEverTick=false; }
void AASSecurityResponseDirector::BeginPlay(){ Super::BeginPlay(); if(HasAuthority()) GetWorldTimerManager().SetTimer(ResponseTimer,this,&AASSecurityResponseDirector::AuthorityEvaluateResponse,ResponseIntervalSeconds,true,1.f); }
void AASSecurityResponseDirector::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const { Super::GetLifetimeReplicatedProps(OutLifetimeProps); DOREPLIFETIME(AASSecurityResponseDirector,ResponseTier); }
void AASSecurityResponseDirector::SetResponseTier(int32 NewTier){ if(!HasAuthority()) return; ResponseTier=FMath::Clamp(NewTier,0,5); OnRep_ResponseTier(); }
void AASSecurityResponseDirector::OnRep_ResponseTier(){ BP_OnResponseTierChanged(ResponseTier); }
int32 AASSecurityResponseDirector::CountActiveSecurityUnits() const { if(!SecurityUnitClass) return 0; int32 N=0; for(TActorIterator<APawn> It(GetWorld(),SecurityUnitClass);It;++It) ++N; return N; }
void AASSecurityResponseDirector::AuthorityEvaluateResponse()
{
    if(!HasAuthority()) return;
    const AASGameState* GS=GetWorld()->GetGameState<AASGameState>();
    SetResponseTier(GS?GS->WorldThreatLevel:0);
    if(ResponseTier<=0 || !SecurityUnitClass || ReinforcementAnchors.IsEmpty()) return;
    int32 Active=CountActiveSecurityUnits();
    const int32 Desired=FMath::Min(MaxActiveSecurityUnits,ResponseTier*2);
    for(int32 i=Active;i<Desired;++i){ AActor* Anchor=ReinforcementAnchors[i%ReinforcementAnchors.Num()]; if(Anchor) GetWorld()->SpawnActor<APawn>(SecurityUnitClass,Anchor->GetActorTransform()); }
}
