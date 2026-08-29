#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASProjectile.generated.h"

class USphereComponent;
class UProjectileMovementComponent;

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASProjectile : public AActor
{
    GENERATED_BODY()

public:
    AASProjectile();
    virtual void BeginPlay() override;

protected:
    UPROPERTY(VisibleAnywhere)
    TObjectPtr<USphereComponent> Collision;

    UPROPERTY(VisibleAnywhere)
    TObjectPtr<UProjectileMovementComponent> Movement;

    UPROPERTY(EditDefaultsOnly)
    float Damage = 90.f;

    UPROPERTY(EditDefaultsOnly)
    float InnerRadius = 180.f;

    UPROPERTY(EditDefaultsOnly)
    float OuterRadius = 520.f;

    UPROPERTY(EditDefaultsOnly)
    float LifeSeconds = 8.f;

    UFUNCTION()
    void OnImpact(
        UPrimitiveComponent* HitComponent,
        AActor* OtherActor,
        UPrimitiveComponent* OtherComp,
        FVector NormalImpulse,
        const FHitResult& Hit
    );

    UFUNCTION(NetMulticast, Unreliable)
    void MulticastImpactFX(
        FVector_NetQuantize Location,
        FVector_NetQuantizeNormal Normal
    );

public:
    void InitDamage(float NewDamage)
    {
        Damage = NewDamage;
    }
};