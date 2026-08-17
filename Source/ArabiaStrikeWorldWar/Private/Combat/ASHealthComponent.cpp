#include "Combat/ASHealthComponent.h"
#include "Net/UnrealNetwork.h"

UASHealthComponent::UASHealthComponent(){SetIsReplicatedByDefault(true);PrimaryComponentTick.bCanEverTick=false;}
void UASHealthComponent::BeginPlay(){Super::BeginPlay();Health=MaxHealth;if(AActor*Owner=GetOwner())Owner->OnTakeAnyDamage.AddDynamic(this,&UASHealthComponent::HandleOwnerTakeAnyDamage);}
void UASHealthComponent::HandleOwnerTakeAnyDamage(AActor*,float Damage,const UDamageType*,AController*,AActor* DamageCauser){if(!GetOwner()||!GetOwner()->HasAuthority()||Damage<=0.f||IsDead())return;const float Old=Health;Health=FMath::Clamp(Health-Damage,0.f,MaxHealth);OnHealthChanged.Broadcast(Health,MaxHealth,DamageCauser);if(Old>0.f&&Health<=0.f)OnDeath.Broadcast(DamageCauser);}
void UASHealthComponent::Heal(float Amount){if(!GetOwner()||!GetOwner()->HasAuthority()||Amount<=0.f||IsDead())return;Health=FMath::Clamp(Health+Amount,0.f,MaxHealth);OnHealthChanged.Broadcast(Health,MaxHealth,nullptr);}
bool UASHealthComponent::Revive(float HealthFraction){if(!GetOwner()||!GetOwner()->HasAuthority()||!IsDead())return false;Health=FMath::Clamp(MaxHealth*HealthFraction,1.f,MaxHealth);OnHealthChanged.Broadcast(Health,MaxHealth,nullptr);return true;}
void UASHealthComponent::OnRep_Health(float OldHealth){OnHealthChanged.Broadcast(Health,MaxHealth,nullptr);if(OldHealth>0.f&&Health<=0.f)OnDeath.Broadcast(nullptr);}
void UASHealthComponent::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>&Out)const{Super::GetLifetimeReplicatedProps(Out);DOREPLIFETIME(UASHealthComponent,Health);}
