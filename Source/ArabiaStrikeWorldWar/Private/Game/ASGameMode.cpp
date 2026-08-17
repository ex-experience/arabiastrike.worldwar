#include "Game/ASGameMode.h"
#include "Game/ASGameState.h"
#include "Player/ASCharacter.h"
#include "Player/ASPlayerController.h"
#include "Player/ASPlayerState.h"
#include "GameFramework/GameStateBase.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "TimerManager.h"

AASGameMode::AASGameMode()
{
    DefaultPawnClass = AASCharacter::StaticClass();
    PlayerControllerClass = AASPlayerController::StaticClass();
    PlayerStateClass = AASPlayerState::StaticClass();
    GameStateClass = AASGameState::StaticClass();
}

void AASGameMode::Logout(AController* Exiting)
{
    CancelPendingRespawn(Exiting);
    Super::Logout(Exiting);
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

void AASGameMode::HandlePlayerEliminated(AASCharacter* EliminatedCharacter)
{
    if (!HasAuthority() || !IsValid(EliminatedCharacter) || !EliminatedCharacter->IsEliminated())
    {
        return;
    }

    AController* EliminatedController = EliminatedCharacter->GetController();
    EliminatedCharacter->SetLifeSpan(FMath::Max(0.1f, EliminatedPawnCleanupDelay));

    if (!IsValid(EliminatedController))
    {
        return;
    }

    const TWeakObjectPtr<AController> ControllerKey(EliminatedController);
    if (PendingRespawnTimers.Contains(ControllerKey))
    {
        if (EliminatedController->GetPawn() == EliminatedCharacter)
        {
            EliminatedController->UnPossess();
        }
        return;
    }

    const float SafeRespawnDelay = FMath::Max(0.f, RespawnDelay);
    if (AASPlayerController* PlayerController = Cast<AASPlayerController>(EliminatedController))
    {
        const UWorld* World = GetWorld();
        const AGameStateBase* CurrentGameState = World ? World->GetGameState() : nullptr;
        const double ServerTime = CurrentGameState
            ? CurrentGameState->GetServerWorldTimeSeconds()
            : (World ? World->GetTimeSeconds() : 0.0);
        PlayerController->SetRespawnState(true, ServerTime + SafeRespawnDelay);
    }

    if (EliminatedController->GetPawn() == EliminatedCharacter)
    {
        EliminatedController->UnPossess();
    }

    QueueRespawn(EliminatedController, SafeRespawnDelay);
}

void AASGameMode::QueueRespawn(AController* Controller, float DelaySeconds)
{
    if (!HasAuthority() || !IsValid(Controller))
    {
        return;
    }

    const TWeakObjectPtr<AController> ControllerKey(Controller);
    if (PendingRespawnTimers.Contains(ControllerKey))
    {
        return;
    }

    FTimerHandle TimerHandle;
    PendingRespawnTimers.Add(ControllerKey, TimerHandle);

    if (DelaySeconds <= 0.f)
    {
        RestartEliminatedPlayer(ControllerKey);
        return;
    }

    FTimerDelegate RespawnDelegate;
    RespawnDelegate.BindUObject(this, &AASGameMode::RestartEliminatedPlayer, ControllerKey);
    GetWorldTimerManager().SetTimer(
        PendingRespawnTimers.FindChecked(ControllerKey),
        RespawnDelegate,
        DelaySeconds,
        false);
}

void AASGameMode::RestartEliminatedPlayer(TWeakObjectPtr<AController> Controller)
{
    FTimerHandle ExpiredTimer;
    if (!PendingRespawnTimers.RemoveAndCopyValue(Controller, ExpiredTimer))
    {
        return;
    }

    AController* PlayerController = Controller.Get();
    if (!IsValid(PlayerController))
    {
        return;
    }

    if (!PlayerController->GetPawn())
    {
        RestartPlayer(PlayerController);
    }

    if (APawn* NewPawn = PlayerController->GetPawn())
    {
        if (AASCharacter* NewCharacter = Cast<AASCharacter>(NewPawn))
        {
            NewCharacter->InitializeForRespawn();
        }

        if (AASPlayerController* ASPlayerController = Cast<AASPlayerController>(PlayerController))
        {
            ASPlayerController->SetRespawnState(false, 0.f);
        }
        return;
    }

    UE_LOG(LogTemp, Warning, TEXT("Respawn failed for %s; retrying in %.2f seconds"),
        *GetNameSafe(PlayerController), RespawnRetryDelay);

    const float SafeRetryDelay = FMath::Max(0.1f, RespawnRetryDelay);
    if (AASPlayerController* ASPlayerController = Cast<AASPlayerController>(PlayerController))
    {
        const UWorld* World = GetWorld();
        const AGameStateBase* CurrentGameState = World ? World->GetGameState() : nullptr;
        const double ServerTime = CurrentGameState
            ? CurrentGameState->GetServerWorldTimeSeconds()
            : (World ? World->GetTimeSeconds() : 0.0);
        ASPlayerController->SetRespawnState(true, ServerTime + SafeRetryDelay);
    }
    QueueRespawn(PlayerController, SafeRetryDelay);
}

void AASGameMode::CancelPendingRespawn(AController* Controller)
{
    if (!Controller)
    {
        return;
    }

    FTimerHandle TimerHandle;
    if (PendingRespawnTimers.RemoveAndCopyValue(TWeakObjectPtr<AController>(Controller), TimerHandle))
    {
        GetWorldTimerManager().ClearTimer(TimerHandle);
    }

    if (AASPlayerController* PlayerController = Cast<AASPlayerController>(Controller))
    {
        PlayerController->SetRespawnState(false, 0.f);
    }
}
