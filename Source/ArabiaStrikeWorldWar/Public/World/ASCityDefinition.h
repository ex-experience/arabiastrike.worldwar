#pragma once
#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "World/ASWorldTypes.h"
#include "ASCityDefinition.generated.h"
class UWorld;

UCLASS(BlueprintType)
class ARABIASTRIKEWORLDWAR_API UASCityDefinition : public UPrimaryDataAsset
{
    GENERATED_BODY()
public:
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="City") FName CityId = TEXT("JEDDAH");
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="City") FText DisplayName;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="City") TSoftObjectPtr<UWorld> WorldMap;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="City") TArray<FASDistrictRuntimeProfile> DistrictProfiles;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="City") FASWorldEnvironmentState DefaultEnvironment;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Online", meta=(ClampMin="1", ClampMax="128")) int32 RecommendedMaxPlayers = 16;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Online") bool bEnabledForMatchmaking = true;
};
