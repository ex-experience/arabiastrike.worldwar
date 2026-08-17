#include "Player/ASPlayerController.h"
#include "Game/ASGameMode.h"

void AASPlayerController::SendChat(const FString& Message, EASChatChannel Channel)
{
    FString Clean = Message.Left(180).TrimStartAndEnd();
    if (!Clean.IsEmpty()) ServerSendChat(Clean, Channel);
}

void AASPlayerController::ServerSendChat_Implementation(const FString& Message, EASChatChannel Channel)
{
    FString Clean = Message.Left(180).TrimStartAndEnd();
    if (Clean.IsEmpty()) return;
    if (AASGameMode* GM = GetWorld() ? GetWorld()->GetAuthGameMode<AASGameMode>() : nullptr)
        GM->BroadcastChat(this, Clean, Channel);
}

void AASPlayerController::ClientReceiveChat_Implementation(const FString& Sender, const FString& Message, EASChatChannel Channel)
{
    OnChatReceived.Broadcast(Sender, Message, Channel);
}
