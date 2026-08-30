#include "Vehicles/ASVehicleDamageModelComponent.h"
#include "Combat/ASHealthComponent.h"
#include "Net/UnrealNetwork.h"
UASVehicleDamageModelComponent::UASVehicleDamageModelComponent(){SetIsReplicatedByDefault(true);PrimaryComponentTick.bCanEverTick=false;}
void UASVehicleDamageModelComponent::BeginPlay(){Super::BeginPlay();if(UASHealthComponent*H=GetOwner()?GetOwner()->FindComponentByClass<UASHealthComponent>():nullptr)H->OnHealthChanged.AddDynamic(this,&UASVehicleDamageModelComponent::HandleHealthChanged);}
float UASVehicleDamageModelComponent::ResolveDamageMultiplier(FName Name)const{for(const auto&Z:Zones)if(Z.BoneOrZone==Name)return FMath::Max(0.f,Z.DamageMultiplier);return 1.f;}
void UASVehicleDamageModelComponent::HandleHealthChanged(float Health,float MaxHealth,AActor*){if(!GetOwner()||!GetOwner()->HasAuthority()||MaxHealth<=0.f)return;const float R=Health/MaxHealth;bCriticalDamage=R<=0.35f;bEngineDisabled=R<=0.12f;OnRep_DamageState();}
void UASVehicleDamageModelComponent::OnRep_DamageState(){}
void UASVehicleDamageModelComponent::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps)const{Super::GetLifetimeReplicatedProps(OutLifetimeProps);DOREPLIFETIME(UASVehicleDamageModelComponent,bEngineDisabled);DOREPLIFETIME(UASVehicleDamageModelComponent,bCriticalDamage);}
