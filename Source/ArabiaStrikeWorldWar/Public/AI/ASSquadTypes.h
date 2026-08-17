#pragma once
#include "CoreMinimal.h"
#include "ASSquadTypes.generated.h"

UENUM(BlueprintType)
enum class EASSquadRole : uint8
{
    Rifleman,
    Heavy,
    Flanker,
    Grenadier,
    Marksman,
    Commander
};

UENUM(BlueprintType)
enum class EASTacticalState : uint8
{
    Advance,
    Hold,
    Flank,
    Suppressed,
    Retreat
};
