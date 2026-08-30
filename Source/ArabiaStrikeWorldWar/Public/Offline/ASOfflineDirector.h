#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASOfflineDirector.generated.h"

class APawn;
class AASCivilianCharacter;
class AASMissionDirector;
class AASPilotableVehiclePawn;
class AASSoldierCharacter;
class AASTrafficRoute;
class AASTrafficVehicleAgent;
class UASWeaponDefinition;

UENUM(BlueprintType)
enum class EASOfflineMissionStage : uint8
{
    Boot,
    StreetCombat,
    VehicleTransition,
    Reinforcements,
    Extraction,
    Complete
};

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASOfflineDirector : public AActor
{
    GENERATED_BODY()

public:
    AASOfflineDirector();
    virtual void BeginPlay() override;

    UFUNCTION(BlueprintPure, Category="ASWW|Offline") FString GetObjectiveText() const { return ObjectiveText; }
    UFUNCTION(BlueprintPure, Category="ASWW|Offline") int32 GetLivingEnemyCount() const;
    UFUNCTION(BlueprintPure, Category="ASWW|Offline") int32 GetCivilianCount() const;
    UFUNCTION(BlueprintPure, Category="ASWW|Offline") int32 GetTrafficVehicleCount() const;
    UFUNCTION(BlueprintPure, Category="ASWW|Offline") float GetObjectiveDistance() const;
    UFUNCTION(BlueprintPure, Category="ASWW|Offline") EASOfflineMissionStage GetOfflineStage() const { return Stage; }
    UFUNCTION(BlueprintPure, Category="ASWW|Offline") bool IsMissionComplete() const { return Stage == EASOfflineMissionStage::Complete; }

private:
    void Bootstrap();
    void CheckProgress();
    void EnsureMissionDirector();
    void EquipPlayer();
    void AdoptExistingEnemies();
    void SpawnEnemyWave(int32 DesiredTotal, float Radius);
    void SpawnCivilianPopulation(int32 Count);
    void SpawnTrafficLoop(int32 Count);
    void SpawnTacticalVehicle();
    void ConfigureSoldier(AASSoldierCharacter* Soldier);
    FVector FindGroundedSpawn(const FVector& Desired) const;
    APawn* GetPlayerPawn() const;

    UPROPERTY() TObjectPtr<UASWeaponDefinition> RifleDefinition;
    UPROPERTY() TObjectPtr<AASMissionDirector> MissionDirector;
    UPROPERTY() TArray<TObjectPtr<AASSoldierCharacter>> ActiveEnemies;
    UPROPERTY() TArray<TObjectPtr<AASCivilianCharacter>> Civilians;
    UPROPERTY() TArray<TObjectPtr<AASTrafficVehicleAgent>> TrafficVehicles;
    UPROPERTY() TObjectPtr<AASTrafficRoute> TrafficRoute;
    UPROPERTY() TObjectPtr<AASPilotableVehiclePawn> TacticalVehicle;
    UPROPERTY() EASOfflineMissionStage Stage = EASOfflineMissionStage::Boot;

    FString ObjectiveText = TEXT("INITIALIZING JEDDAH OFFLINE OPERATION");
    FVector VehicleTransitionLocation = FVector::ZeroVector;
    FVector ExtractionLocation = FVector::ZeroVector;
    FTimerHandle BootstrapTimer;
    FTimerHandle ProgressTimer;
};
