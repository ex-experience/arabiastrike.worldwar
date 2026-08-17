#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Pawn.h"
#include "ASBoatPawn.generated.h"
UCLASS()
class ARABIASTRIKEWORLDWAR_API AASBoatPawn : public APawn
{
    GENERATED_BODY()
public:
    AASBoatPawn();
    virtual void Tick(float DeltaSeconds) override;
    UFUNCTION(Server,Reliable) void ServerSetBoatInput(float Throttle,float Steering);
    UPROPERTY(EditAnywhere,BlueprintReadOnly,Category="Boat") float MaxSpeedCmPerSecond=2200.f;
    UPROPERTY(EditAnywhere,BlueprintReadOnly,Category="Boat") float TurnRateDegreesPerSecond=45.f;
    UPROPERTY(EditAnywhere,BlueprintReadOnly,Category="Boat") bool bUseWaterBuoyancyPresentation=true;
protected:
    UPROPERTY(Replicated) float RepThrottle=0.f;
    UPROPERTY(Replicated) float RepSteering=0.f;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
};
