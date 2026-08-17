#pragma once
#include "CoreMinimal.h"
#include "ASCivilianReactionTypes.generated.h"
UENUM(BlueprintType)
enum class EASCivilianReaction : uint8 { Calm, Observe, Flee, Cower, Evacuate };
