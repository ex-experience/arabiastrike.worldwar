#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASWorldStreamingBudgetDirector.generated.h"
USTRUCT(BlueprintType)
struct FASWorldBudgetSnapshot
{
    GENERATED_BODY()
    UPROPERTY(BlueprintReadOnly) int32 ReplicatedActors=0;
    UPROPERTY(BlueprintReadOnly) int32 Pawns=0;
    UPROPERTY(BlueprintReadOnly) int32 Vehicles=0;
    UPROPERTY(BlueprintReadOnly) int32 Civilians=0;
};
UCLASS()
class ARABIASTRIKEWORLDWAR_API AASWorldStreamingBudgetDirector : public AActor
{
    GENERATED_BODY()
public:
    AASWorldStreamingBudgetDirector();
    virtual void BeginPlay() override;
    UPROPERTY(EditAnywhere,BlueprintReadOnly,Category="Budget") int32 SoftReplicatedActorBudget=800;
    UPROPERTY(EditAnywhere,BlueprintReadOnly,Category="Budget") int32 SoftPawnBudget=160;
    UPROPERTY(BlueprintReadOnly,Category="Budget") FASWorldBudgetSnapshot LastSnapshot;
    UFUNCTION(BlueprintPure,Category="Budget") bool IsOverSoftBudget() const;
protected:
    void SampleWorldBudget();
    FTimerHandle SampleTimer;
    UFUNCTION(BlueprintImplementableEvent,Category="Budget") void BP_OnBudgetSampled(const FASWorldBudgetSnapshot& Snapshot,bool bOverBudget);
};
