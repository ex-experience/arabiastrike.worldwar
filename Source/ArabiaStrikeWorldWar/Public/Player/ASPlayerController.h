#pragma once
#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "Online/ASChatTypes.h"
#include "ASPlayerController.generated.h"

DECLARE_DYNAMIC_MULTICAST_DELEGATE_ThreeParams(FASChatReceived, FString, Sender, FString, Message, EASChatChannel, Channel);

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASPlayerController : public APlayerController
{
    GENERATED_BODY()
public:
    UPROPERTY(BlueprintAssignable) FASChatReceived OnChatReceived;
    UFUNCTION(BlueprintCallable) void SendChat(const FString& Message, EASChatChannel Channel);
    UFUNCTION(Server, Reliable) void ServerSendChat(const FString& Message, EASChatChannel Channel);
    UFUNCTION(Client, Reliable) void ClientReceiveChat(const FString& Sender, const FString& Message, EASChatChannel Channel);
};
