#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "World/ASWorldTypes.h"
#include "ASWorldEnvironmentDirector.generated.h"

DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FASEnvironmentStateChanged, const FASWorldEnvironmentState&, NewState);

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASWorldEnvironmentDirector : public AActor
{
    GENERATED_BODY()
public:
    AASWorldEnvironmentDirector();
    virtual void BeginPlay() override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="World|Time") bool bAdvanceTime = true;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="World|Time", meta=(ClampMin="0.0")) float GameMinutesPerRealSecond = 1.0f;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="World|Time", meta=(ClampMin="0.1")) float UpdateIntervalSeconds = 1.0f;
    UPROPERTY(ReplicatedUsing=OnRep_EnvironmentState, BlueprintReadOnly, Category="World") FASWorldEnvironmentState EnvironmentState;
    UPROPERTY(BlueprintAssignable, Category="World") FASEnvironmentStateChanged OnEnvironmentStateChanged;

    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly, Category="World") void SetTimeOfDay(float Hours);
    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly, Category="World") void SetWeather(EASWeatherType Weather, float Intensity);
    UFUNCTION(BlueprintPure, Category="World") float GetSunPitchDegrees() const;

protected:
    UFUNCTION() void OnRep_EnvironmentState();
    UFUNCTION(BlueprintImplementableEvent, Category="World") void BP_ApplyEnvironmentState(const FASWorldEnvironmentState& State);

private:
    FTimerHandle UpdateTimer;
    void AuthorityUpdateEnvironment();
    void BroadcastEnvironmentState();
};
