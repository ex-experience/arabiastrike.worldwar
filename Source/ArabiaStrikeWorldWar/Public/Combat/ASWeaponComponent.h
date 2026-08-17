#pragma once
#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "ASWeaponComponent.generated.h"

DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FASWeaponFired, FVector, TraceStart, FVector, TraceEnd);

UCLASS(ClassGroup=(ARABIASTRIKE), meta=(BlueprintSpawnableComponent))
class ARABIASTRIKEWORLDWAR_API UASWeaponComponent : public UActorComponent
{
    GENERATED_BODY()
public:
    UASWeaponComponent();
    UFUNCTION(BlueprintCallable) void RequestFire(const FVector& Origin, const FVector& Direction);
    UPROPERTY(BlueprintAssignable) FASWeaponFired OnWeaponFired;

protected:
    UPROPERTY(EditDefaultsOnly, Category="Weapon") float Damage = 24.f;
    UPROPERTY(EditDefaultsOnly, Category="Weapon") float Range = 20000.f;
    UPROPERTY(EditDefaultsOnly, Category="Weapon") float RoundsPerMinute = 720.f;
    double LastServerShotTime = -1000.0;

    UFUNCTION(Server, Reliable) void ServerFire(FVector_NetQuantize Origin, FVector_NetQuantizeNormal Direction);
    UFUNCTION(NetMulticast, Unreliable) void MulticastShotFX(FVector_NetQuantize Start, FVector_NetQuantize End);
    void FireAuthority(const FVector& Origin, const FVector& Direction);
};
