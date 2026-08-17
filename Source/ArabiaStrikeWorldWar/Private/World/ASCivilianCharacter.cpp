#include "World/ASCivilianCharacter.h"
#include "AIController.h"
#include "NavigationSystem.h"
#include "Net/UnrealNetwork.h"
#include "TimerManager.h"
AASCivilianCharacter::AASCivilianCharacter(){ bReplicates=true; SetReplicateMovement(true); AutoPossessAI=EAutoPossessAI::PlacedInWorldOrSpawned; Tags.Add(TEXT("Civilian")); }
void AASCivilianCharacter::BeginPlay(){ Super::BeginPlay(); HomeLocation=GetActorLocation(); if(HasAuthority()) GetWorldTimerManager().SetTimer(WanderTimer,this,&AASCivilianCharacter::ChooseNextDestination,RepathIntervalSeconds,true,0.5f); }
void AASCivilianCharacter::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const { Super::GetLifetimeReplicatedProps(OutLifetimeProps); DOREPLIFETIME(AASCivilianCharacter,Reaction); }
void AASCivilianCharacter::OnRep_Reaction(){ BP_OnReactionChanged(Reaction); }
void AASCivilianCharacter::NotifyThreat(FVector ThreatLocation,float Severity){ if(!HasAuthority())return; LastThreatLocation=ThreatLocation; Reaction=Severity>=0.75f?EASCivilianReaction::Flee:Severity>=0.35f?EASCivilianReaction::Cower:EASCivilianReaction::Observe; OnRep_Reaction(); if(Reaction==EASCivilianReaction::Flee){ if(AAIController* AI=Cast<AAIController>(GetController())){ FVector Away=(GetActorLocation()-ThreatLocation).GetSafeNormal(); AI->MoveToLocation(GetActorLocation()+Away*PanicThreatDistance,100.f); } } }
void AASCivilianCharacter::BeginEvacuation(FVector EvacuationPoint){ if(!HasAuthority())return; Reaction=EASCivilianReaction::Evacuate; OnRep_Reaction(); if(AAIController* AI=Cast<AAIController>(GetController())) AI->MoveToLocation(EvacuationPoint,100.f); }
void AASCivilianCharacter::ChooseNextDestination(){ if(!HasAuthority()||Reaction!=EASCivilianReaction::Calm)return; AAIController* AI=Cast<AAIController>(GetController()); UNavigationSystemV1* Nav=FNavigationSystem::GetCurrent<UNavigationSystemV1>(GetWorld()); if(!AI||!Nav)return; FNavLocation Candidate; if(Nav->GetRandomReachablePointInRadius(HomeLocation,WanderRadius,Candidate)) AI->MoveToLocation(Candidate.Location,90.f,true,true,true,false,nullptr,true); }
