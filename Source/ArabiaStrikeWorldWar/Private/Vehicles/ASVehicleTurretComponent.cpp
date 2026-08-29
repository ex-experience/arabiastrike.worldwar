#include "Vehicles/ASVehicleTurretComponent.h"
#include "Kismet/GameplayStatics.h"
#include "GameFramework/Pawn.h"
#include "Net/UnrealNetwork.h"
#include "Engine/World.h"
UASVehicleTurretComponent::UASVehicleTurretComponent(){SetIsReplicatedByDefault(true);PrimaryComponentTick.bCanEverTick=false;}
void UASVehicleTurretComponent::RequestAim(FRotator R){R.Pitch=FMath::ClampAngle(R.Pitch,-25.f,55.f);R.Roll=0.f;if(GetOwner()&&GetOwner()->HasAuthority())ServerSetAim_Implementation(R);else ServerSetAim(R);}
void UASVehicleTurretComponent::ServerSetAim_Implementation(FRotator R){R.Pitch=FMath::ClampAngle(R.Pitch,-25.f,55.f);R.Roll=0.f;ReplicatedAim=R;}
void UASVehicleTurretComponent::RequestFire(){if(GetOwner()&&GetOwner()->HasAuthority())FireAuthority();else ServerFire();}
void UASVehicleTurretComponent::ServerFire_Implementation(){FireAuthority();}
void UASVehicleTurretComponent::FireAuthority(){if(!GetOwner()||!GetWorld())return;const double Now=GetWorld()->GetTimeSeconds();const double Min=60.0/FMath::Max(1.f,RoundsPerMinute);if(Now-LastShot<Min)return;LastShot=Now;const FVector Start=GetOwner()->GetActorLocation()+FVector(0,0,130)+GetOwner()->GetActorForwardVector()*180.f;const FVector Dir=ReplicatedAim.Vector().GetSafeNormal();if(FVector::DotProduct(Dir,GetOwner()->GetActorForwardVector())<-0.35f)return;const FVector End=Start+Dir*Range;FHitResult Hit;FCollisionQueryParams Q(SCENE_QUERY_STAT(ASVehicleTurret),true,GetOwner());FVector FxEnd=End;if(GetWorld()->LineTraceSingleByChannel(Hit,Start,End,ECC_Visibility,Q)){FxEnd=Hit.ImpactPoint;AController*C=nullptr;if(const APawn*P=Cast<APawn>(GetOwner()))C=P->GetController();UGameplayStatics::ApplyPointDamage(Hit.GetActor(),Damage,Dir,Hit,C,GetOwner(),nullptr);}MulticastFireFX(Start,FxEnd);}
void UASVehicleTurretComponent::MulticastFireFX_Implementation(FVector_NetQuantize S,FVector_NetQuantize E){OnVehicleWeaponFired.Broadcast(S,E);}
void UASVehicleTurretComponent::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps)const{Super::GetLifetimeReplicatedProps(OutLifetimeProps);DOREPLIFETIME(UASVehicleTurretComponent,ReplicatedAim);}
