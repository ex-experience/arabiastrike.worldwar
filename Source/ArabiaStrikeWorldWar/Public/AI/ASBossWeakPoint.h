#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASBossWeakPoint.generated.h"
class UBoxComponent;
UCLASS()
class ARABIASTRIKEWORLDWAR_API AASBossWeakPoint : public AActor
{
    GENERATED_BODY()
public:
    AASBossWeakPoint();
    virtual void BeginPlay() override;
    virtual float TakeDamage(float DamageAmount, FDamageEvent const& DamageEvent, AController* EventInstigator, AActor* DamageCauser) override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
    UFUNCTION(BlueprintPure) bool IsDestroyed() const { return Health <= 0.f; }
protected:
    UPROPERTY(VisibleAnywhere) TObjectPtr<UBoxComponent> HitBox;
    UPROPERTY(EditDefaultsOnly) float MaxHealth=150.f;
    UPROPERTY(ReplicatedUsing=OnRep_Health) float Health=150.f;
    UFUNCTION() void OnRep_Health();
};
