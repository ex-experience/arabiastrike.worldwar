#pragma once

#include "CoreMinimal.h"
#include "Game/ASGameMode.h"
#include "ASOfflineGameMode.generated.h"

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASOfflineGameMode : public AASGameMode
{
    GENERATED_BODY()
public:
    AASOfflineGameMode();
    virtual void StartPlay() override;
};
