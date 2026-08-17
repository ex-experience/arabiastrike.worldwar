#pragma once
#include "CoreMinimal.h"
#include "GameFramework/PlayerState.h"
#include "ASPlayerState.generated.h"

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASPlayerState : public APlayerState
{
    GENERATED_BODY()
public:
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

    UPROPERTY(Replicated, BlueprintReadOnly) int32 SquadId = 0;
    UPROPERTY(Replicated, BlueprintReadOnly) int32 TeamId = 0;
    UPROPERTY(Replicated, BlueprintReadOnly) int32 Kills = 0;
    UPROPERTY(Replicated, BlueprintReadOnly) int32 Deaths = 0;
    UPROPERTY(Replicated, BlueprintReadOnly) int32 XP = 0;
};
