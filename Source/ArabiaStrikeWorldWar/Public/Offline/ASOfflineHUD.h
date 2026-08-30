#pragma once

#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "ASOfflineHUD.generated.h"

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASOfflineHUD : public AHUD
{
    GENERATED_BODY()
public:
    virtual void DrawHUD() override;
};
