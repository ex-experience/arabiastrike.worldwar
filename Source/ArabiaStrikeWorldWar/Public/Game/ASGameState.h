#pragma once
#include "CoreMinimal.h"
#include "GameFramework/GameStateBase.h"
#include "ASGameState.generated.h"

UENUM(BlueprintType)
enum class EASWorldEvent : uint8 { Calm, ConvoyAmbush, HeliAttack, MechAssault, SecuritySweep, PortLockdown, SandstormEmergency, CivilianEvacuation, BoatInterdiction };

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASGameState : public AGameStateBase
{
    GENERATED_BODY()
public:
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
    UPROPERTY(Replicated, BlueprintReadOnly) EASWorldEvent ActiveWorldEvent = EASWorldEvent::Calm;
    UPROPERTY(Replicated, BlueprintReadOnly) int32 WorldThreatLevel = 0;
};
