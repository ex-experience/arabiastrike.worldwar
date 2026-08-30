#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "World/ASCivilianReactionTypes.h"
#include "ASCivilianCharacter.generated.h"

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASCivilianCharacter : public ACharacter
{
    GENERATED_BODY()
public:
    AASCivilianCharacter();
    virtual void BeginPlay() override;
    virtual void Tick(float DeltaSeconds) override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Civilian") float WanderRadius = 1800.0f;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Civilian") float RepathIntervalSeconds = 4.0f;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Civilian") float PanicThreatDistance = 1600.0f;
    UPROPERTY(ReplicatedUsing=OnRep_Reaction,BlueprintReadOnly,Category="Civilian") EASCivilianReaction Reaction=EASCivilianReaction::Calm;
    UFUNCTION(BlueprintCallable,BlueprintAuthorityOnly,Category="Civilian") void NotifyThreat(FVector ThreatLocation,float Severity);
    UFUNCTION(BlueprintCallable,BlueprintAuthorityOnly,Category="Civilian") void BeginEvacuation(FVector EvacuationPoint);
    UFUNCTION(BlueprintCallable,BlueprintAuthorityOnly,Category="Civilian") void ReturnToRoutine();
protected:
    FVector HomeLocation = FVector::ZeroVector;
    FVector LastThreatLocation = FVector::ZeroVector;
    FVector FallbackDestination = FVector::ZeroVector;
    FTimerHandle WanderTimer;
    void ChooseNextDestination();
    UFUNCTION() void OnRep_Reaction();
    UFUNCTION(BlueprintImplementableEvent,Category="Civilian") void BP_OnReactionChanged(EASCivilianReaction NewReaction);
};
