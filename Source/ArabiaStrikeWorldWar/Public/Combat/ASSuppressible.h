#pragma once
#include "CoreMinimal.h"
#include "UObject/Interface.h"
#include "ASSuppressible.generated.h"

UINTERFACE(BlueprintType)
class UASSuppressible : public UInterface
{
    GENERATED_BODY()
};

class ARABIASTRIKEWORLDWAR_API IASSuppressible
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintNativeEvent, BlueprintCallable, Category="Combat|Suppression")
    void ApplySuppression(float Amount, FVector SourceLocation);
};
