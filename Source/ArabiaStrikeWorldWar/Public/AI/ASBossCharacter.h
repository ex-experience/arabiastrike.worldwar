#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "ASBossCharacter.generated.h"
class UASHealthComponent; class AASBossWeakPoint;
DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FASBossPhaseChanged,int32,Phase,float,HealthRatio);
UCLASS()
class ARABIASTRIKEWORLDWAR_API AASBossCharacter : public ACharacter
{
    GENERATED_BODY()
public:
    AASBossCharacter();
    virtual void Tick(float DeltaSeconds) override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
    UPROPERTY(ReplicatedUsing=OnRep_Phase, BlueprintReadOnly) int32 Phase=1;
    UPROPERTY(Replicated, BlueprintReadOnly) int32 DestroyedWeakPoints=0;
    UPROPERTY(BlueprintAssignable) FASBossPhaseChanged OnBossPhaseChanged;
    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly) void RegisterWeakPoint(AASBossWeakPoint* WeakPoint);
    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly) void NotifyWeakPointDestroyed(AASBossWeakPoint* WeakPoint);
    UFUNCTION(BlueprintPure) int32 GetLivingWeakPointCount() const;
protected:
    UPROPERTY(VisibleAnywhere, BlueprintReadOnly) TObjectPtr<UASHealthComponent> Health;
    UPROPERTY(EditDefaultsOnly) int32 MaxPhases=4;
    UPROPERTY() TArray<TObjectPtr<AASBossWeakPoint>> WeakPoints;
    UFUNCTION() void OnRep_Phase();
    void UpdatePhaseAuthority();
};
