#pragma once
#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "Online/ASChatTypes.h"
#include "ASGameMode.generated.h"

class AASPlayerController;

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASGameMode : public AGameModeBase
{
    GENERATED_BODY()
public:
    AASGameMode();
    void BroadcastChat(AASPlayerController* SenderPC, const FString& Message, EASChatChannel Channel);
};
