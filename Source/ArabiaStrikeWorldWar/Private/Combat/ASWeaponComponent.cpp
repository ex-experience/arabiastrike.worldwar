#include "Combat/ASWeaponComponent.h"
#include "Combat/ASWeaponDefinition.h"
#include "Combat/ASProjectile.h"
#include "Kismet/GameplayStatics.h"
#include "Net/UnrealNetwork.h"
#include "Engine/World.h"
#include "GameFramework/Pawn.h"
UASWeaponComponent::UASWeaponComponent(){SetIsReplicatedByDefault(true);PrimaryComponentTick.bCanEverTick=false;}
void UASWeaponComponent::EquipDefinition(UASWeaponDefinition* D){if(!GetOwner()||!GetOwner()->HasAuthority()||!D)return;WeaponDefinition=D;Ammo.Magazine=D->MagazineSize;Ammo.Reserve=D->MagazineSize*4;OnRep_Ammo();}
void UASWeaponComponent::RequestFire(const FVector&O,const FVector&D){if(GetOwner()&&GetOwner()->HasAuthority())FireAuthority(O,D);else ServerFire(O,D.GetSafeNormal());}
void UASWeaponComponent::ServerFire_Implementation(FVector_NetQuantize O,FVector_NetQuantizeNormal D){FireAuthority(O,D);}
void UASWeaponComponent::FireAuthority(const FVector&O,const FVector&D)
{
    if(!WeaponDefinition||bReloading||!GetWorld()||!GetOwner()||Ammo.Magazine<=0)return;
    const double Now=GetWorld()->GetTimeSeconds(); const double Min=60.0/FMath::Max(1.f,WeaponDefinition->RoundsPerMinute); if(Now-LastServerShotTime<Min)return; LastServerShotTime=Now;
    Ammo.Magazine--; OnRep_Ammo();
    const FVector Dir=FMath::VRandCone(D.GetSafeNormal(),FMath::DegreesToRadians(WeaponDefinition->SpreadDegrees));
    if(WeaponDefinition->FireMode==EASFireMode::Projectile && WeaponDefinition->ProjectileClass){FActorSpawnParameters P;P.Owner=GetOwner();P.Instigator=Cast<APawn>(GetOwner());auto* Pr=GetWorld()->SpawnActor<AASProjectile>(WeaponDefinition->ProjectileClass,O,Dir.Rotation(),P);if(Pr)Pr->InitDamage(WeaponDefinition->Damage);MulticastShotFX(O,O+Dir*500.f);return;}
    const FVector End=O+Dir*WeaponDefinition->Range; FHitResult Hit; FCollisionQueryParams Q(SCENE_QUERY_STAT(ASWeaponTrace),true,GetOwner()); FVector FxEnd=End;
    if(GetWorld()->LineTraceSingleByChannel(Hit,O,End,ECC_Visibility,Q)){FxEnd=Hit.ImpactPoint;AController*C=nullptr;if(const APawn*P=Cast<APawn>(GetOwner()))C=P->GetController();UGameplayStatics::ApplyPointDamage(Hit.GetActor(),WeaponDefinition->Damage,Dir,Hit,C,GetOwner(),nullptr);} MulticastShotFX(O,FxEnd);
}
void UASWeaponComponent::RequestReload(){if(GetOwner()&&GetOwner()->HasAuthority())ServerReload_Implementation();else ServerReload();}
void UASWeaponComponent::ServerReload_Implementation(){if(!WeaponDefinition||bReloading||Ammo.Magazine>=WeaponDefinition->MagazineSize||Ammo.Reserve<=0)return;bReloading=true;GetWorld()->GetTimerManager().SetTimer(ReloadTimer,this,&UASWeaponComponent::FinishReload,WeaponDefinition->ReloadSeconds,false);}
void UASWeaponComponent::FinishReload(){if(!WeaponDefinition)return;int32 Need=WeaponDefinition->MagazineSize-Ammo.Magazine;int32 Take=FMath::Min(Need,Ammo.Reserve);Ammo.Magazine+=Take;Ammo.Reserve-=Take;bReloading=false;OnRep_Ammo();}
void UASWeaponComponent::OnRep_Definition(){} void UASWeaponComponent::OnRep_Ammo(){OnAmmoChanged.Broadcast(Ammo.Magazine,Ammo.Reserve);} void UASWeaponComponent::MulticastShotFX_Implementation(FVector_NetQuantize S,FVector_NetQuantize E){OnWeaponFired.Broadcast(S,E);}
void UASWeaponComponent::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>&O)const{Super::GetLifetimeReplicatedProps(O);DOREPLIFETIME(UASWeaponComponent,WeaponDefinition);DOREPLIFETIME(UASWeaponComponent,Ammo);DOREPLIFETIME(UASWeaponComponent,bReloading);}
