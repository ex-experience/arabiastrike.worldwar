#include "Combat/ASWeaponComponent.h"
#include "Combat/ASWeaponDefinition.h"
#include "Combat/ASProjectile.h"
#include "Combat/ASSuppressible.h"
#include "Kismet/GameplayStatics.h"
#include "Net/UnrealNetwork.h"
#include "Engine/World.h"
#include "GameFramework/Pawn.h"
#include "GameFramework/Character.h"
UASWeaponComponent::UASWeaponComponent(){SetIsReplicatedByDefault(true);PrimaryComponentTick.bCanEverTick=false;}
void UASWeaponComponent::EquipDefinition(UASWeaponDefinition*D){if(!GetOwner()||!GetOwner()->HasAuthority()||!D)return;WeaponDefinition=D;Ammo.Magazine=D->MagazineSize;Ammo.Reserve=D->MagazineSize*4;OnRep_Definition();OnRep_Ammo();}
void UASWeaponComponent::RequestFire(const FVector&O,const FVector&D){if(GetOwner()&&GetOwner()->HasAuthority())FireAuthority(O,D);else ServerFire(O,D.GetSafeNormal());}
void UASWeaponComponent::ServerFire_Implementation(FVector_NetQuantize O,FVector_NetQuantizeNormal D){if(!GetOwner()||FVector::DistSquared(O,GetOwner()->GetActorLocation())>FMath::Square(700.f))return;FireAuthority(O,D);}
void UASWeaponComponent::FireAuthority(const FVector& O, const FVector& D)
{
    if (!WeaponDefinition)
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_FIRE_AUTH_REJECT_NO_DEFINITION"));
        return;
    }

    if (bReloading)
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_FIRE_AUTH_REJECT_RELOADING"));
        return;
    }

    if (!GetWorld())
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_FIRE_AUTH_REJECT_NO_WORLD"));
        return;
    }

    if (!GetOwner())
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_FIRE_AUTH_REJECT_NO_OWNER"));
        return;
    }

    if (Ammo.Magazine <= 0)
    {
        UE_LOG(
            LogTemp,
            Warning,
            TEXT("ASWW_QA_FIRE_AUTH_REJECT_EMPTY mag=%d reserve=%d"),
            Ammo.Magazine,
            Ammo.Reserve);
        return;
    }

    const double Now = GetWorld()->GetTimeSeconds();
    const double MinInterval =
        60.0 / FMath::Max(1.f, WeaponDefinition->RoundsPerMinute);

    if (Now - LastServerShotTime < MinInterval)
    {
        UE_LOG(
            LogTemp,
            Warning,
            TEXT("ASWW_QA_FIRE_AUTH_REJECT_COOLDOWN dt=%.4f min=%.4f"),
            Now - LastServerShotTime,
            MinInterval);
        return;
    }

    LastServerShotTime = Now;

    const int32 MagazineBefore = Ammo.Magazine;
    Ammo.Magazine--;
    OnRep_Ammo();

    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_QA_FIRE_AUTH_ACCEPTED magBefore=%d magAfter=%d reserve=%d"),
        MagazineBefore,
        Ammo.Magazine,
        Ammo.Reserve);

    const FVector Dir = FMath::VRandCone(
        D.GetSafeNormal(),
        FMath::DegreesToRadians(WeaponDefinition->SpreadDegrees));

    if (WeaponDefinition->FireMode == EASFireMode::Projectile &&
        WeaponDefinition->ProjectileClass)
    {
        FActorSpawnParameters P;
        P.Owner = GetOwner();
        P.Instigator = Cast<APawn>(GetOwner());

        AASProjectile* Projectile = GetWorld()->SpawnActor<AASProjectile>(
            WeaponDefinition->ProjectileClass,
            O,
            Dir.Rotation(),
            P);

        if (Projectile)
        {
            Projectile->InitDamage(WeaponDefinition->Damage);
        }

        MulticastShotFX(O, O + Dir * 500.f);

        UE_LOG(
            LogTemp,
            Warning,
            TEXT("ASWW_QA_FIRE_AUTH_PATH=PROJECTILE spawned=%d"),
            Projectile ? 1 : 0);
        return;
    }

    const FVector End = O + Dir * WeaponDefinition->Range;
    FHitResult Hit;
    FCollisionQueryParams Q(
        SCENE_QUERY_STAT(ASWeaponTrace),
        true,
        GetOwner());

    FVector FxEnd = End;

    if (GetWorld()->LineTraceSingleByChannel(
        Hit,
        O,
        End,
        ECC_Visibility,
        Q))
    {
        FxEnd = Hit.ImpactPoint;

        AController* C = nullptr;
        if (const APawn* P = Cast<APawn>(GetOwner()))
        {
            C = P->GetController();
        }

        UGameplayStatics::ApplyPointDamage(
            Hit.GetActor(),
            WeaponDefinition->Damage,
            Dir,
            Hit,
            C,
            GetOwner(),
            nullptr);

        UE_LOG(
            LogTemp,
            Warning,
            TEXT("ASWW_QA_FIRE_AUTH_HIT actor=%s"),
            *GetNameSafe(Hit.GetActor()));
    }
    else
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_FIRE_AUTH_HIT actor=NONE"));
    }

    ApplyNearMissSuppression(O, FxEnd);
    MulticastShotFX(O, FxEnd);
}
void UASWeaponComponent::ApplyNearMissSuppression(const FVector&Start,const FVector&End){if(!GetWorld())return;TArray<AActor*>Candidates;UGameplayStatics::GetAllActorsWithInterface(this,UASSuppressible::StaticClass(),Candidates);for(AActor*A:Candidates){if(!A||A==GetOwner())continue;const FVector P=A->GetActorLocation();const FVector Closest=FMath::ClosestPointOnSegment(P,Start,End);if(FVector::DistSquared(P,Closest)<=FMath::Square(SuppressionRadius))IASSuppressible::Execute_ApplySuppression(A,SuppressionPerShot,Start);}}
void UASWeaponComponent::RequestReload(){if(GetOwner()&&GetOwner()->HasAuthority())ServerReload_Implementation();else ServerReload();}
void UASWeaponComponent::ServerReload_Implementation()
{
    if (!WeaponDefinition)
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_RELOAD_REJECT_NO_DEFINITION"));
        return;
    }

    if (bReloading)
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_RELOAD_REJECT_ALREADY_RELOADING"));
        return;
    }

    if (Ammo.Magazine >= WeaponDefinition->MagazineSize)
    {
        UE_LOG(
            LogTemp,
            Warning,
            TEXT("ASWW_QA_RELOAD_REJECT_FULL_MAG mag=%d size=%d reserve=%d"),
            Ammo.Magazine,
            WeaponDefinition->MagazineSize,
            Ammo.Reserve);
        return;
    }

    if (Ammo.Reserve <= 0)
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_RELOAD_REJECT_NO_RESERVE mag=%d"), Ammo.Magazine);
        return;
    }

    if (!GetWorld())
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_RELOAD_REJECT_NO_WORLD"));
        return;
    }

    bReloading = true;

    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_QA_RELOAD_ACCEPTED mag=%d reserve=%d seconds=%.2f"),
        Ammo.Magazine,
        Ammo.Reserve,
        WeaponDefinition->ReloadSeconds);

    GetWorld()->GetTimerManager().SetTimer(
        ReloadTimer,
        this,
        &UASWeaponComponent::FinishReload,
        WeaponDefinition->ReloadSeconds,
        false);
}
void UASWeaponComponent::FinishReload()
{
    if (!WeaponDefinition)
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_RELOAD_FINISH_ABORT_NO_DEFINITION"));
        return;
    }

    const int32 Need = WeaponDefinition->MagazineSize - Ammo.Magazine;
    const int32 Take = FMath::Min(Need, Ammo.Reserve);

    Ammo.Magazine += Take;
    Ammo.Reserve -= Take;
    bReloading = false;
    OnRep_Ammo();

    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_QA_RELOAD_FINISHED mag=%d reserve=%d"),
        Ammo.Magazine,
        Ammo.Reserve);
}
void UASWeaponComponent::OnRep_Definition(){}void UASWeaponComponent::OnRep_Ammo(){OnAmmoChanged.Broadcast(Ammo.Magazine,Ammo.Reserve);}void UASWeaponComponent::MulticastShotFX_Implementation(FVector_NetQuantize S,FVector_NetQuantize E){OnWeaponFired.Broadcast(S,E);}void UASWeaponComponent::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps)const{Super::GetLifetimeReplicatedProps(OutLifetimeProps);DOREPLIFETIME(UASWeaponComponent,WeaponDefinition);DOREPLIFETIME(UASWeaponComponent,Ammo);DOREPLIFETIME(UASWeaponComponent,bReloading);}
