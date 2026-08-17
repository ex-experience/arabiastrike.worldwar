#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Game/ASGameState.h"
#include "ASLivingWorldEventDirector.generated.h"
class UASWorldEventDefinition;

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASLivingWorldEventDirector : public AActor
{
    GENERATED_BODY()
public:
    AASLivingWorldEventDirector();
    virtual void BeginPlay() override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
    UPROPERTY(EditAnywhere,BlueprintReadOnly,Category="Events") TArray<TObjectPtr<UASWorldEventDefinition>> EventPool;
    UPROPERTY(EditAnywhere,BlueprintReadOnly,Category="Events") float EvaluationIntervalSeconds=30.f;
    UPROPERTY(ReplicatedUsing=OnRep_ActiveEvent,BlueprintReadOnly,Category="Events") FName ActiveEventId=NAME_None;
    UPROPERTY(Replicated,BlueprintReadOnly,Category="Events") EASWorldEvent ActiveEventType=EASWorldEvent::Calm;
    UFUNCTION(BlueprintCallable,BlueprintAuthorityOnly,Category="Events") bool TryStartEvent(UASWorldEventDefinition* Definition,FName DistrictId);
    UFUNCTION(BlueprintCallable,BlueprintAuthorityOnly,Category="Events") void EndActiveEvent();
protected:
    UFUNCTION() void OnRep_ActiveEvent();
    UFUNCTION(BlueprintImplementableEvent,Category="Events") void BP_OnLivingEventStarted(FName EventId,EASWorldEvent EventType);
    UFUNCTION(BlueprintImplementableEvent,Category="Events") void BP_OnLivingEventEnded(FName EventId);
    void AuthorityEvaluateEvents();
    FTimerHandle EvaluationTimer;
    FTimerHandle ActiveEventTimer;
    TMap<FName,double> CooldownUntil;
};
