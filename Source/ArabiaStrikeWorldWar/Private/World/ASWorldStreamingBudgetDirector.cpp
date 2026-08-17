#include "World/ASWorldStreamingBudgetDirector.h"
#include "EngineUtils.h"
#include "GameFramework/Pawn.h"
#include "TimerManager.h"
AASWorldStreamingBudgetDirector::AASWorldStreamingBudgetDirector(){ PrimaryActorTick.bCanEverTick=false; }
void AASWorldStreamingBudgetDirector::BeginPlay(){ Super::BeginPlay(); GetWorldTimerManager().SetTimer(SampleTimer,this,&AASWorldStreamingBudgetDirector::SampleWorldBudget,2.f,true,1.f); }
bool AASWorldStreamingBudgetDirector::IsOverSoftBudget() const { return LastSnapshot.ReplicatedActors>SoftReplicatedActorBudget || LastSnapshot.Pawns>SoftPawnBudget; }
void AASWorldStreamingBudgetDirector::SampleWorldBudget(){ FASWorldBudgetSnapshot S; for(TActorIterator<AActor> It(GetWorld());It;++It){ AActor* A=*It; if(A->GetIsReplicated()) ++S.ReplicatedActors; if(A->IsA<APawn>()) ++S.Pawns; if(A->ActorHasTag(TEXT("Vehicle"))) ++S.Vehicles; if(A->ActorHasTag(TEXT("Civilian"))) ++S.Civilians; } LastSnapshot=S; BP_OnBudgetSampled(LastSnapshot,IsOverSoftBudget()); }
