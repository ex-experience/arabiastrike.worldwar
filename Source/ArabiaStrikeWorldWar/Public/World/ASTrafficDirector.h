#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "World/ASWorldTypes.h"
#include "ASTrafficDirector.generated.h"
class AASTrafficRoute;
class AASTrafficVehicleAgent;

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASTrafficDirector : public AActor
{
    GENERATED_BODY()
public:
    AASTrafficDirector();
    virtual void BeginPlay() override;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Traffic") EASCityDistrict District = EASCityDistrict::Corniche;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Traffic") TArray<TObjectPtr<AASTrafficRoute>> Routes;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Traffic") TArray<TSubclassOf<AASTrafficVehicleAgent>> VehicleClasses;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Traffic", meta=(ClampMin="0", ClampMax="100")) int32 MaxActiveVehicles = 18;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Traffic", meta=(ClampMin="0.25")) float SpawnIntervalSeconds = 2.5f;

private:
    FTimerHandle SpawnTimer;
    TArray<TWeakObjectPtr<AASTrafficVehicleAgent>> ActiveVehicles;
    void AuthoritySpawnTraffic();
    void CompactVehicleList();
};
