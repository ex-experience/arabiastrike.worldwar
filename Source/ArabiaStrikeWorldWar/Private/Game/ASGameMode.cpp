#include "Game/ASGameMode.h"
#include "Game/ASGameState.h"
#include "Player/ASCharacter.h"
#include "Player/ASPlayerController.h"
#include "Player/ASPlayerState.h"
#include "Engine/World.h"
#include "EngineUtils.h"

AASGameMode::AASGameMode()
{
    DefaultPawnClass = AASCharacter::StaticClass();
    PlayerControllerClass = AASPlayerController::StaticClass();
    PlayerStateClass = AASPlayerState::StaticClass();
    GameStateClass = AASGameState::StaticClass();
}

void AASGameMode::BroadcastChat(AASPlayerController* SenderPC, const FString& Message, EASChatChannel Channel)
{
    if (!SenderPC || !SenderPC->PlayerState) return;
    const FString SenderName = SenderPC->PlayerState->GetPlayerName();
    const AASPlayerState* SenderState = SenderPC->GetPlayerState<AASPlayerState>();
    const APawn* SenderPawn = SenderPC->GetPawn();

    for (FConstPlayerControllerIterator It = GetWorld()->GetPlayerControllerIterator(); It; ++It)
    {
        AASPlayerController* Target = Cast<AASPlayerController>(It->Get());
        if (!Target) continue;

        bool bDeliver = (Channel == EASChatChannel::Global);
        if (Channel == EASChatChannel::Squad)
        {
            const AASPlayerState* TargetState = Target->GetPlayerState<AASPlayerState>();
            bDeliver = SenderState && TargetState && SenderState->SquadId == TargetState->SquadId;
        }
        else if (Channel == EASChatChannel::Proximity)
        {
            const APawn* TargetPawn = Target->GetPawn();
            bDeliver = SenderPawn && TargetPawn && FVector::DistSquared(SenderPawn->GetActorLocation(), TargetPawn->GetActorLocation()) <= FMath::Square(3000.f);
        }

        if (bDeliver) Target->ClientReceiveChat(SenderName, Message, Channel);
    }
}
