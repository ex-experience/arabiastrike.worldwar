#pragma once
#include "CoreMinimal.h"
#include "ASChatTypes.generated.h"

UENUM(BlueprintType)
enum class EASChatChannel : uint8
{
    Global,
    Squad,
    Proximity
};
