#pragma once
#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "Online/ASChatTypes.h"
#include "Combat/ASCombatTypes.h"
#include "Mission/ASMissionDirector.h"
#include "ASPlayerController.generated.h"

class AASCharacter;

USTRUCT(BlueprintType)
struct ARABIASTRIKEWORLDWAR_API FASRespawnState
{
    GENERATED_BODY()

    UPROPERTY(BlueprintReadOnly, Category="Respawn")
    bool bPending = false;

    UPROPERTY(BlueprintReadOnly, Category="Respawn")
    double EndServerTime = 0.0;
};

DECLARE_DYNAMIC_MULTICAST_DELEGATE_ThreeParams(FASChatReceived,FString,Sender,FString,Message,EASChatChannel,Channel);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FASRespawnStateChanged, bool, bPending, float, TimeRemaining);

enum class EASChatPolicyViolation : uint8
{
    EmptyMessage,
    InvalidChannel,
    Cooldown,
    BurstLimit
};

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASPlayerController : public APlayerController
{
    GENERATED_BODY()

public:
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

    UPROPERTY(BlueprintAssignable) FASChatReceived OnChatReceived;
    UPROPERTY(BlueprintAssignable, Category="Respawn") FASRespawnStateChanged OnRespawnStateChanged;

    UFUNCTION(BlueprintCallable) void SendChat(const FString& Message,EASChatChannel Channel);
    UFUNCTION(Server,Reliable) void ServerSendChat(const FString& Message,EASChatChannel Channel);
    UFUNCTION(Client,Reliable) void ClientReceiveChat(const FString& Sender,const FString& Message,EASChatChannel Channel);
    UFUNCTION(BlueprintPure,Category="HUD") AASCharacter* GetASCharacter() const;
    UFUNCTION(BlueprintPure,Category="HUD") float GetHealthRatio() const;
    UFUNCTION(BlueprintPure,Category="HUD") FASAmmoState GetAmmoState() const;
    UFUNCTION(BlueprintPure,Category="HUD") bool IsPlayerDowned() const;
    UFUNCTION(BlueprintPure,Category="HUD") EASMissionPhase GetMissionPhase() const;
    UFUNCTION(BlueprintPure,Category="HUD") int32 GetRescuedHostageCount() const;
    UFUNCTION(BlueprintPure,Category="HUD") int32 GetRequiredHostageCount() const;
    UFUNCTION(BlueprintPure,Category="HUD") EASCityDistrict GetCurrentDistrict() const;

    UFUNCTION(BlueprintPure, Category="Respawn") bool IsRespawnPending() const { return RespawnState.bPending; }
    UFUNCTION(BlueprintPure, Category="Respawn") float GetRespawnTimeRemaining() const;

    void SetRespawnState(bool bPending, double EndServerTime);

protected:
    virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;

    UPROPERTY(Transient, ReplicatedUsing=OnRep_RespawnState, BlueprintReadOnly, Category="Respawn")
    FASRespawnState RespawnState;

    UFUNCTION()
    void OnRep_RespawnState();

    /** Server-only extension point for future moderation telemetry. It performs no punitive action by default. */
    virtual void HandleChatPolicyViolation(EASChatPolicyViolation Reason, uint8 ViolationsInWindow, uint16 TotalViolations);

private:
    static constexpr int32 MaxChatMessageLength = 180;
    static constexpr double ChatMinimumIntervalSeconds = 0.25;
    static constexpr double ChatBurstWindowSeconds = 5.0;
    static constexpr uint8 ChatBurstMessageLimit = 6;
    static constexpr double ChatViolationWindowSeconds = 30.0;

    static bool IsValidChatChannel(EASChatChannel Channel);
    bool CanAcceptChatMessage(double ServerTime, EASChatPolicyViolation& OutViolationReason);
    void PrepareChatRateLimitClock(double ServerTime);
    void RecordChatPolicyViolation(double ServerTime, EASChatPolicyViolation Reason);
    void ResetChatRateLimitState();

    // Scalar, bounded server state: no per-message containers and no client-provided timestamps.
    double LastAcceptedChatServerTime = -1.0;
    double ChatBurstWindowStartServerTime = -1.0;
    double ChatViolationWindowStartServerTime = -1.0;
    double LastObservedChatServerTime = -1.0;
    uint8 AcceptedChatMessagesInBurst = 0;
    uint8 ChatViolationsInWindow = 0;
    uint16 TotalChatPolicyViolations = 0;
};
