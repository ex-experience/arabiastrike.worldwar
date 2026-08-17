#include "Combat/ASWeaponComponent.h"
#include "Kismet/GameplayStatics.h"
#include "Engine/World.h"
#include "GameFramework/Pawn.h"

UASWeaponComponent::UASWeaponComponent()
{
    SetIsReplicatedByDefault(true);
    PrimaryComponentTick.bCanEverTick = false;
}

void UASWeaponComponent::RequestFire(const FVector& Origin, const FVector& Direction)
{
    if (GetOwner() && GetOwner()->HasAuthority()) FireAuthority(Origin, Direction);
    else ServerFire(Origin, Direction.GetSafeNormal());
}

void UASWeaponComponent::ServerFire_Implementation(FVector_NetQuantize Origin, FVector_NetQuantizeNormal Direction)
{
    FireAuthority(Origin, Direction);
}

void UASWeaponComponent::FireAuthority(const FVector& Origin, const FVector& Direction)
{
    UWorld* World = GetWorld();
    if (!World || !GetOwner()) return;

    const double Now = World->GetTimeSeconds();
    const double MinInterval = 60.0 / FMath::Max(1.f, RoundsPerMinute);
    if ((Now - LastServerShotTime) < MinInterval) return;
    LastServerShotTime = Now;

    const FVector End = Origin + Direction.GetSafeNormal() * Range;
    FHitResult Hit;
    FCollisionQueryParams Params(SCENE_QUERY_STAT(ASWeaponTrace), true, GetOwner());
    FVector FxEnd = End;

    if (World->LineTraceSingleByChannel(Hit, Origin, End, ECC_Visibility, Params))
    {
        FxEnd = Hit.ImpactPoint;
        AController* InstigatorController = nullptr;
        if (const APawn* PawnOwner = Cast<APawn>(GetOwner())) InstigatorController = PawnOwner->GetController();
        UGameplayStatics::ApplyPointDamage(Hit.GetActor(), Damage, Direction, Hit, InstigatorController, GetOwner(), nullptr);
    }

    MulticastShotFX(Origin, FxEnd);
}

void UASWeaponComponent::MulticastShotFX_Implementation(FVector_NetQuantize Start, FVector_NetQuantize End)
{
    OnWeaponFired.Broadcast(Start, End);
}
