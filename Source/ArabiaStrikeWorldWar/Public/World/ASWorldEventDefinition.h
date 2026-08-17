#pragma once
#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "Game/ASGameState.h"
#include "ASWorldEventDefinition.generated.h"
UCLASS(BlueprintType)
class ARABIASTRIKEWORLDWAR_API UASWorldEventDefinition : public UPrimaryDataAsset
{
    GENERATED_BODY()
public:
    UPROPERTY(EditAnywhere,BlueprintReadOnly) FName EventId=NAME_None;
    UPROPERTY(EditAnywhere,BlueprintReadOnly) EASWorldEvent EventType=EASWorldEvent::Calm;
    UPROPERTY(EditAnywhere,BlueprintReadOnly,meta=(ClampMin="0",ClampMax="5")) int32 ThreatLevel=1;
    UPROPERTY(EditAnywhere,BlueprintReadOnly) float DurationSeconds=120.f;
    UPROPERTY(EditAnywhere,BlueprintReadOnly) float CooldownSeconds=300.f;
    UPROPERTY(EditAnywhere,BlueprintReadOnly) TArray<FName> AllowedDistricts;
    UPROPERTY(EditAnywhere,BlueprintReadOnly) FName CinematicCue=NAME_None;
};
