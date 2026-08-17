#pragma once
#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "Online/ASChatTypes.h"
#include "TimerManager.h"
#include "ASGameMode.generated.h"

class AASCharacter;
class AASPlayerController;

UCLASS(Config=Game)
class ARABIASTRIKEWORLDWAR_API AASGameMode : public AGameModeBase
{
    GENERATED_BODY()

public:
    AASGameMode();

    virtual void Logout(AController* Exiting) override;

    void BroadcastChat(AASPlayerController* SenderPC, const FString& Message, EASChatChannel Channel);

    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly, Category="Respawn")
    void HandlePlayerEliminated(AASCharacter* EliminatedCharacter);

protected:
    UPROPERTY(Config, EditDefaultsOnly, BlueprintReadOnly, Category="Respawn", meta=(ClampMin="0.0", Units="s"))
    float RespawnDelay = 5.f;

    UPROPERTY(Config, EditDefaultsOnly, BlueprintReadOnly, Category="Respawn", meta=(ClampMin="0.1", Units="s"))
    float RespawnRetryDelay = 1.f;

    UPROPERTY(Config, EditDefaultsOnly, BlueprintReadOnly, Category="Respawn", meta=(ClampMin="0.1", Units="s"))
    float EliminatedPawnCleanupDelay = 2.f;

private:
    TMap<TWeakObjectPtr<AController>, FTimerHandle> PendingRespawnTimers;

    void QueueRespawn(AController* Controller, float DelaySeconds);
    void RestartEliminatedPlayer(TWeakObjectPtr<AController> Controller);
    void CancelPendingRespawn(AController* Controller);
};
