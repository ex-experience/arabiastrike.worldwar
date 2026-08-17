#pragma once
#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "ASVehicleTurretComponent.generated.h"
DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FASVehicleWeaponFired, FVector, Start, FVector, End);
UCLASS(ClassGroup=(Vehicle), meta=(BlueprintSpawnableComponent))
class ARABIASTRIKEWORLDWAR_API UASVehicleTurretComponent : public UActorComponent
{
    GENERATED_BODY()
public:
    UASVehicleTurretComponent();
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
    UPROPERTY(BlueprintAssignable) FASVehicleWeaponFired OnVehicleWeaponFired;
    UFUNCTION(BlueprintCallable) void RequestAim(FRotator AimRotation);
    UFUNCTION(BlueprintCallable) void RequestFire();
    UFUNCTION(BlueprintPure) FRotator GetAimRotation() const { return ReplicatedAim; }
protected:
    UPROPERTY(EditDefaultsOnly) float Damage=34.f;
    UPROPERTY(EditDefaultsOnly) float Range=25000.f;
    UPROPERTY(EditDefaultsOnly) float RoundsPerMinute=650.f;
    UPROPERTY(Replicated) FRotator ReplicatedAim;
    double LastShot=-1000.0;
    UFUNCTION(Server, Unreliable) void ServerSetAim(FRotator AimRotation);
    UFUNCTION(Server, Reliable) void ServerFire();
    UFUNCTION(NetMulticast, Unreliable) void MulticastFireFX(FVector_NetQuantize Start, FVector_NetQuantize End);
    void FireAuthority();
};
