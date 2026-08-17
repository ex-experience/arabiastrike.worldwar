#pragma once
#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "Combat/ASCombatTypes.h"
#include "ASWeaponComponent.generated.h"
class UASWeaponDefinition;
DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FASWeaponFired,FVector,Start,FVector,End);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FASAmmoChanged,int32,Magazine,int32,Reserve);
UCLASS(ClassGroup=(Combat),meta=(BlueprintSpawnableComponent))
class ARABIASTRIKEWORLDWAR_API UASWeaponComponent : public UActorComponent
{
    GENERATED_BODY()
public:
    UASWeaponComponent();
    UPROPERTY(BlueprintAssignable) FASWeaponFired OnWeaponFired;
    UPROPERTY(BlueprintAssignable) FASAmmoChanged OnAmmoChanged;
    UFUNCTION(BlueprintCallable) void RequestFire(const FVector& Origin,const FVector& Direction);
    UFUNCTION(BlueprintCallable) void RequestReload();
    UFUNCTION(BlueprintCallable) void EquipDefinition(UASWeaponDefinition* Definition);
    UFUNCTION(BlueprintPure) FASAmmoState GetAmmo() const { return Ammo; }
    UFUNCTION(BlueprintPure) UASWeaponDefinition* GetDefinition() const { return WeaponDefinition; }
    UFUNCTION(BlueprintPure) bool IsReloading() const { return bReloading; }
protected:
    UPROPERTY(EditDefaultsOnly,ReplicatedUsing=OnRep_Definition) TObjectPtr<UASWeaponDefinition> WeaponDefinition;
    UPROPERTY(ReplicatedUsing=OnRep_Ammo) FASAmmoState Ammo;
    UPROPERTY(Replicated) bool bReloading=false;
    UPROPERTY(EditDefaultsOnly, Category="Combat|Suppression") float SuppressionRadius=260.f;
    UPROPERTY(EditDefaultsOnly, Category="Combat|Suppression") float SuppressionPerShot=0.16f;
    double LastServerShotTime=-1000.0;
    FTimerHandle ReloadTimer;
    UFUNCTION(Server,Reliable) void ServerFire(FVector_NetQuantize Origin,FVector_NetQuantizeNormal Direction);
    UFUNCTION(Server,Reliable) void ServerReload();
    UFUNCTION(NetMulticast,Unreliable) void MulticastShotFX(FVector_NetQuantize Start,FVector_NetQuantize End);
    UFUNCTION() void OnRep_Definition(); UFUNCTION() void OnRep_Ammo();
    void FireAuthority(const FVector& Origin,const FVector& Direction); void FinishReload();
    void ApplyNearMissSuppression(const FVector& Start,const FVector& End);
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& Out) const override;
};
