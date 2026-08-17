#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Game/ASGameState.h"
#include "ASWorldEventDirector.generated.h"

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASWorldEventDirector : public AActor
{
    GENERATED_BODY()
public:
    AASWorldEventDirector();
    virtual void BeginPlay() override;
    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly) void StartEvent(EASWorldEvent Event, int32 ThreatLevel);
    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly) void EndEvent();
};
