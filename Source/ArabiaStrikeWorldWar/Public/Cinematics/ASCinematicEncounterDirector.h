#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASCinematicEncounterDirector.generated.h"
USTRUCT(BlueprintType)
struct FASCinematicCueState
{
    GENERATED_BODY()
    UPROPERTY(BlueprintReadOnly) FName CueId=NAME_None;
    UPROPERTY(BlueprintReadOnly) double ServerStartTime=0.0;
    UPROPERTY(BlueprintReadOnly) bool bSkippable=true;
};
UCLASS()
class ARABIASTRIKEWORLDWAR_API AASCinematicEncounterDirector : public AActor
{
    GENERATED_BODY()
public:
    AASCinematicEncounterDirector();
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
    UPROPERTY(ReplicatedUsing=OnRep_CinematicCue,BlueprintReadOnly,Category="Cinematics") FASCinematicCueState ActiveCue;
    UFUNCTION(BlueprintCallable,BlueprintAuthorityOnly,Category="Cinematics") void StartCinematicCue(FName CueId,bool bSkippable=true);
    UFUNCTION(BlueprintCallable,BlueprintAuthorityOnly,Category="Cinematics") void EndCinematicCue();
protected:
    UFUNCTION() void OnRep_CinematicCue();
    UFUNCTION(BlueprintImplementableEvent,Category="Cinematics") void BP_PlaySynchronizedCue(const FASCinematicCueState& Cue);
    UFUNCTION(BlueprintImplementableEvent,Category="Cinematics") void BP_StopSynchronizedCue();
};
