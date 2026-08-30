#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASOfflineLivingCityDirector.generated.h"

class UHierarchicalInstancedStaticMeshComponent;
class USceneComponent;
class AASWorldEnvironmentDirector;

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASOfflineLivingCityDirector : public AActor
{
    GENERATED_BODY()

public:
    AASOfflineLivingCityDirector();
    virtual void BeginPlay() override;

    UFUNCTION(BlueprintPure, Category="ASWW|Living City") int32 GetBuildingCount() const;
    UFUNCTION(BlueprintPure, Category="ASWW|Living City") int32 GetRoadCount() const;
    UFUNCTION(BlueprintPure, Category="ASWW|Living City") int32 GetCivilianCount() const;
    UFUNCTION(BlueprintPure, Category="ASWW|Living City") int32 GetTrafficCount() const;
    UFUNCTION(BlueprintPure, Category="ASWW|Living City") float GetTimeOfDayHours() const;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="ASWW|Living City")
    bool bCreateProceduralCityBlocks = true;

protected:
    UPROPERTY(VisibleAnywhere)
    TObjectPtr<USceneComponent> SceneRoot;

    UPROPERTY(VisibleAnywhere)
    TObjectPtr<UHierarchicalInstancedStaticMeshComponent> BuildingInstances;

    UPROPERTY(VisibleAnywhere)
    TObjectPtr<UHierarchicalInstancedStaticMeshComponent> RoadInstances;

    UPROPERTY(VisibleAnywhere)
    TObjectPtr<UHierarchicalInstancedStaticMeshComponent> StreetLightInstances;

private:
    UPROPERTY()
    TObjectPtr<AASWorldEnvironmentDirector> EnvironmentDirector;

    FTimerHandle BootstrapTimer;
    FTimerHandle SimulationTimer;
    bool bBootstrapped = false;

    void BootstrapLivingCity();
    void BuildCityBlocks(const FVector& Center);
    void UpdateSimulation();
    FVector FindGround(const FVector& Desired) const;
};
