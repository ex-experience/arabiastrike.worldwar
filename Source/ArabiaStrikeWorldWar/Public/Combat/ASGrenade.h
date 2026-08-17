#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASGrenade.generated.h"
class USphereComponent; class UProjectileMovementComponent;

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASGrenade : public AActor
{
    GENERATED_BODY()
public:
    AASGrenade();
    virtual void BeginPlay() override;
    void InitThrow(float InDamage, float InFuseSeconds);
protected:
    UPROPERTY(VisibleAnywhere) TObjectPtr<USphereComponent> Collision;
    UPROPERTY(VisibleAnywhere) TObjectPtr<UProjectileMovementComponent> Movement;
    UPROPERTY(EditDefaultsOnly) float Damage = 120.f;
    UPROPERTY(EditDefaultsOnly) float InnerRadius = 250.f;
    UPROPERTY(EditDefaultsOnly) float OuterRadius = 700.f;
    UPROPERTY(EditDefaultsOnly) float FuseSeconds = 2.4f;
    FTimerHandle FuseTimer;
    UFUNCTION() void Explode();
    UFUNCTION(NetMulticast, Unreliable) void MulticastExplosionFX(FVector_NetQuantize Location);
};
