#include "AI/ASBossWeakPoint.h"
#include "AI/ASBossCharacter.h"
#include "Components/BoxComponent.h"
#include "Net/UnrealNetwork.h"
AASBossWeakPoint::AASBossWeakPoint(){bReplicates=true;HitBox=CreateDefaultSubobject<UBoxComponent>(TEXT("HitBox"));RootComponent=HitBox;HitBox->SetBoxExtent(FVector(45));HitBox->SetCollisionProfileName(TEXT("BlockAllDynamic"));}
void AASBossWeakPoint::BeginPlay(){Super::BeginPlay();Health=MaxHealth;if(HasAuthority())if(AASBossCharacter*Boss=Cast<AASBossCharacter>(GetOwner()))Boss->RegisterWeakPoint(this);}
float AASBossWeakPoint::TakeDamage(float Amount,FDamageEvent const&,AController*,AActor*){if(!HasAuthority()||Amount<=0.f||Health<=0.f)return 0.f;const float Applied=FMath::Min(Amount,Health);Health-=Applied;OnRep_Health();if(Health<=0.f)if(AASBossCharacter*Boss=Cast<AASBossCharacter>(GetOwner()))Boss->NotifyWeakPointDestroyed(this);return Applied;}
void AASBossWeakPoint::OnRep_Health(){SetActorHiddenInGame(Health<=0.f);SetActorEnableCollision(Health>0.f);}
void AASBossWeakPoint::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>&Out)const{Super::GetLifetimeReplicatedProps(Out);DOREPLIFETIME(AASBossWeakPoint,Health);}
