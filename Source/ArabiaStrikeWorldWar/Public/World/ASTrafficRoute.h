#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASTrafficRoute.generated.h"
class USplineComponent;

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASTrafficRoute : public AActor
{
    GENERATED_BODY()
public:
    AASTrafficRoute();
    UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category="Traffic") TObjectPtr<USplineComponent> RouteSpline;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Traffic") bool bLoop = true;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Traffic", meta=(ClampMin="100")) float SpeedLimitCmPerSecond = 1800.0f;
};
