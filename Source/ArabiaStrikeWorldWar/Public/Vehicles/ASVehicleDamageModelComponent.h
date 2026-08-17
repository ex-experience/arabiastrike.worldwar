#pragma once
#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "ASVehicleDamageModelComponent.generated.h"
USTRUCT(BlueprintType)
struct FASVehicleDamageZone
{
    GENERATED_BODY()
    UPROPERTY(EditAnywhere, BlueprintReadWrite) FName BoneOrZone;
    UPROPERTY(EditAnywhere, BlueprintReadWrite) float DamageMultiplier=1.f;
};
UCLASS(ClassGroup=(Vehicle), meta=(BlueprintSpawnableComponent))
class ARABIASTRIKEWORLDWAR_API UASVehicleDamageModelComponent : public UActorComponent
{
    GENERATED_BODY()
public:
    UASVehicleDamageModelComponent();
    virtual void BeginPlay() override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
    UFUNCTION(BlueprintPure) float ResolveDamageMultiplier(FName BoneOrZone) const;
    UFUNCTION(BlueprintPure) bool IsEngineDisabled() const { return bEngineDisabled; }
protected:
    UPROPERTY(EditDefaultsOnly) TArray<FASVehicleDamageZone> Zones;
    UPROPERTY(ReplicatedUsing=OnRep_DamageState) bool bEngineDisabled=false;
    UPROPERTY(ReplicatedUsing=OnRep_DamageState) bool bCriticalDamage=false;
    UFUNCTION() void HandleHealthChanged(float Health,float MaxHealth,AActor* InstigatorActor);
    UFUNCTION() void OnRep_DamageState();
};
