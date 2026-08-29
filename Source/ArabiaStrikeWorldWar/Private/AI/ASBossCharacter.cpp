#include "AI/ASBossCharacter.h"
#include "AI/ASBossWeakPoint.h"
#include "Combat/ASHealthComponent.h"
#include "Net/UnrealNetwork.h"
AASBossCharacter::AASBossCharacter(){PrimaryActorTick.bCanEverTick=true;bReplicates=true;Health=CreateDefaultSubobject<UASHealthComponent>(TEXT("Health"));}
void AASBossCharacter::Tick(float D){Super::Tick(D);if(HasAuthority()&&Health)UpdatePhaseAuthority();}
void AASBossCharacter::RegisterWeakPoint(AASBossWeakPoint*W){if(HasAuthority()&&W)WeakPoints.AddUnique(W);}
void AASBossCharacter::NotifyWeakPointDestroyed(AASBossWeakPoint*W){if(!HasAuthority()||!W)return;DestroyedWeakPoints++;UpdatePhaseAuthority();}
int32 AASBossCharacter::GetLivingWeakPointCount()const{int32 Count=0;for(const AASBossWeakPoint*W:WeakPoints)if(W&&!W->IsDestroyed())Count++;return Count;}
void AASBossCharacter::UpdatePhaseAuthority(){const float Ratio=Health->GetHealthRatio();int32 NewPhase=FMath::Clamp(1+FMath::FloorToInt((1.f-Ratio)*MaxPhases),1,MaxPhases);if(DestroyedWeakPoints>=2)NewPhase=FMath::Max(NewPhase,3);if(GetLivingWeakPointCount()==0&&WeakPoints.Num()>0)NewPhase=MaxPhases;if(NewPhase!=Phase){Phase=NewPhase;OnRep_Phase();}}
void AASBossCharacter::OnRep_Phase(){OnBossPhaseChanged.Broadcast(Phase,Health?Health->GetHealthRatio():0.f);}
void AASBossCharacter::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps)const{Super::GetLifetimeReplicatedProps(OutLifetimeProps);DOREPLIFETIME(AASBossCharacter,Phase);DOREPLIFETIME(AASBossCharacter,DestroyedWeakPoints);}
