#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Game/ASGameState.h"
#include "World/ASWorldTypes.h"
#include "ASDynamicEncounterDirector.generated.h"

USTRUCT(BlueprintType)
struct FASDynamicEncounterSpec
{
    GENERATED_BODY()
    UPROPERTY(EditAnywhere, BlueprintReadWrite) FName EncounterId = NAME_None;
    UPROPERTY(EditAnywhere, BlueprintReadWrite) EASCityDistrict District = EASCityDistrict::Corniche;
    UPROPERTY(EditAnywhere, BlueprintReadWrite) EASWorldEvent WorldEvent = EASWorldEvent::ConvoyAmbush;
    UPROPERTY(EditAnywhere, BlueprintReadWrite, meta=(ClampMin="0", ClampMax="5")) int32 MinimumThreatLevel = 1;
    UPROPERTY(EditAnywhere, BlueprintReadWrite, meta=(ClampMin="0.0")) float Weight = 1.0f;
    UPROPERTY(EditAnywhere, BlueprintReadWrite) TSubclassOf<AActor> EncounterActorClass;
};

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASDynamicEncounterDirector : public AActor
{
    GENERATED_BODY()
public:
    AASDynamicEncounterDirector();
    virtual void BeginPlay() override;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Encounter") TArray<FASDynamicEncounterSpec> EncounterTable;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Encounter", meta=(ClampMin="2.0")) float EvaluationIntervalSeconds = 20.0f;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Encounter", meta=(ClampMin="1000.0")) float SpawnDistanceFromPlayer = 4500.0f;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Encounter", meta=(ClampMin="0", ClampMax="20")) int32 MaxConcurrentEncounters = 3;

    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly, Category="Encounter") bool TryStartEncounter();

private:
    FTimerHandle EvaluateTimer;
    TArray<TWeakObjectPtr<AActor>> ActiveEncounters;
    const FASDynamicEncounterSpec* ChooseEncounter(EASCityDistrict District, int32 Threat) const;
};
