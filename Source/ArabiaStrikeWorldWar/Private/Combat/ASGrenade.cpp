#include "Combat/ASGrenade.h"
#include "Components/SphereComponent.h"
#include "GameFramework/ProjectileMovementComponent.h"
#include "Kismet/GameplayStatics.h"
#include "TimerManager.h"

AASGrenade::AASGrenade()
{
    bReplicates = true;
    SetReplicateMovement(true);
    Collision = CreateDefaultSubobject<USphereComponent>(TEXT("Collision"));
    RootComponent = Collision;
    Collision->InitSphereRadius(10.f);
    Collision->SetCollisionProfileName(TEXT("PhysicsActor"));
    Movement = CreateDefaultSubobject<UProjectileMovementComponent>(TEXT("Movement"));
    Movement->InitialSpeed = 1500.f;
    Movement->MaxSpeed = 1800.f;
    Movement->ProjectileGravityScale = 1.15f;
    Movement->bShouldBounce = true;
    Movement->Bounciness = 0.35f;
}

void AASGrenade::BeginPlay()
{
    Super::BeginPlay();
    if (HasAuthority()) GetWorldTimerManager().SetTimer(FuseTimer, this, &AASGrenade::Explode, FuseSeconds, false);
}

void AASGrenade::InitThrow(float InDamage, float InFuseSeconds)
{
    if (!HasAuthority()) return;
    Damage = FMath::Max(1.f, InDamage);
    FuseSeconds = FMath::Clamp(InFuseSeconds, 0.25f, 10.f);
    if (HasActorBegunPlay()) GetWorldTimerManager().SetTimer(FuseTimer, this, &AASGrenade::Explode, FuseSeconds, false);
}

void AASGrenade::Explode()
{
    if (!HasAuthority()) return;
    TArray<AActor*> Ignore; Ignore.Add(this); if (GetOwner()) Ignore.Add(GetOwner());
    UGameplayStatics::ApplyRadialDamageWithFalloff(this, Damage, Damage*0.2f, GetActorLocation(), InnerRadius, OuterRadius, 1.f, nullptr, Ignore, this, GetInstigatorController());
    MulticastExplosionFX(GetActorLocation());
    Destroy();
}

void AASGrenade::MulticastExplosionFX_Implementation(FVector_NetQuantize) {}
