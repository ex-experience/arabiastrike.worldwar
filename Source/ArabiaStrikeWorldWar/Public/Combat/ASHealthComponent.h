#pragma once
#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "ASHealthComponent.generated.h"

DECLARE_DYNAMIC_MULTICAST_DELEGATE_ThreeParams(FASHealthChanged, float, Health, float, MaxHealth, AActor*, InstigatorActor);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FASDeath, AActor*, InstigatorActor);

UCLASS(ClassGroup=(ARABIASTRIKE), meta=(BlueprintSpawnableComponent))
class ARABIASTRIKEWORLDWAR_API UASHealthComponent : public UActorComponent
{
    GENERATED_BODY()
public:
    UASHealthComponent();
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
    UPROPERTY(BlueprintAssignable) FASHealthChanged OnHealthChanged;
    UPROPERTY(BlueprintAssignable) FASDeath OnDeath;
    UFUNCTION(BlueprintPure) float GetHealth() const { return Health; }
    UFUNCTION(BlueprintPure) float GetMaxHealth() const { return MaxHealth; }
    UFUNCTION(BlueprintPure) float GetHealthRatio() const { return MaxHealth > 0.f ? Health/MaxHealth : 0.f; }
    UFUNCTION(BlueprintPure) bool IsDead() const { return Health <= 0.f; }
    UFUNCTION(BlueprintCallable) void Heal(float Amount);
    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly) bool Revive(float HealthFraction=0.35f);
protected:
    virtual void BeginPlay() override;
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category="Health", meta=(ClampMin="1.0")) float MaxHealth = 100.f;
    UPROPERTY(ReplicatedUsing=OnRep_Health, VisibleInstanceOnly, Category="Health") float Health = 100.f;
    UFUNCTION() void HandleOwnerTakeAnyDamage(AActor* DamagedActor, float Damage, const UDamageType* DamageType, AController* InstigatedBy, AActor* DamageCauser);
    UFUNCTION() void OnRep_Health(float OldHealth);
};
