#include "Combat/ASProjectile.h"

#include "Components/SphereComponent.h"
#include "GameFramework/ProjectileMovementComponent.h"
#include "Kismet/GameplayStatics.h"

AASProjectile::AASProjectile()
{
    bReplicates = true;
    SetReplicateMovement(true);

    Collision = CreateDefaultSubobject<USphereComponent>(TEXT("Collision"));
    RootComponent = Collision;

    Collision->InitSphereRadius(12.f);
    Collision->SetCollisionProfileName(TEXT("Projectile"));

    Collision->OnComponentHit.AddDynamic(
        this,
        &AASProjectile::OnImpact
    );

    Movement = CreateDefaultSubobject<UProjectileMovementComponent>(TEXT("Movement"));
    Movement->InitialSpeed = 4200.f;
    Movement->MaxSpeed = 4200.f;
    Movement->bRotationFollowsVelocity = true;
}

void AASProjectile::BeginPlay()
{
    Super::BeginPlay();
    SetLifeSpan(LifeSeconds);
}

void AASProjectile::OnImpact(
    UPrimitiveComponent* HitComponent,
    AActor* OtherActor,
    UPrimitiveComponent* OtherComp,
    FVector NormalImpulse,
    const FHitResult& Hit
)
{
    if (!HasAuthority())
    {
        return;
    }

    TArray<AActor*> IgnoreActors;
    IgnoreActors.Add(this);

    if (GetOwner())
    {
        IgnoreActors.Add(GetOwner());
    }

    UGameplayStatics::ApplyRadialDamageWithFalloff(
        this,
        Damage,
        Damage * 0.2f,
        Hit.ImpactPoint,
        InnerRadius,
        OuterRadius,
        1.f,
        nullptr,
        IgnoreActors,
        this,
        GetInstigatorController()
    );

    MulticastImpactFX(
        Hit.ImpactPoint,
        Hit.ImpactNormal
    );

    Destroy();
}

void AASProjectile::MulticastImpactFX_Implementation(
    FVector_NetQuantize Location,
    FVector_NetQuantizeNormal Normal
)
{
}