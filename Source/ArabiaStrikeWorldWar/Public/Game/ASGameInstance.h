#pragma once
#include "CoreMinimal.h"
#include "Engine/GameInstance.h"
#include "ASGameInstance.generated.h"

UCLASS()
class ARABIASTRIKEWORLDWAR_API UASGameInstance : public UGameInstance
{
    GENERATED_BODY()
public:
    virtual void Init() override;
    UFUNCTION(BlueprintPure) FString GetOnlineBackendMode() const { return OnlineBackendMode; }
private:
    FString OnlineBackendMode = TEXT("Null");
};
