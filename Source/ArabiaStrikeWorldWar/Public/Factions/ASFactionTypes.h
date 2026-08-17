#pragma once
#include "CoreMinimal.h"
#include "ASFactionTypes.generated.h"

UENUM(BlueprintType)
enum class EASFaction : uint8
{
    Neutral,
    Player,
    Civilian,
    JeddahSecurity,
    RedDune,
    Mercenary,
    RogueMachine
};

UENUM(BlueprintType)
enum class EASFactionAttitude : uint8 { Friendly, Neutral, Hostile };
