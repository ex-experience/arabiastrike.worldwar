#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "ASOnlineReadiness.generated.h"

UCLASS()
class ARABIASTRIKEWORLDWAR_API UASOnlineReadiness : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintPure, Category="ARABIA STRIKE|Online") static bool IsDedicatedServerRuntime();
    UFUNCTION(BlueprintPure, Category="ARABIA STRIKE|Online") static FString ArchitectureStatus();
};
