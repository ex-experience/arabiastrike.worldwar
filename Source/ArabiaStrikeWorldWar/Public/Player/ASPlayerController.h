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
    UPROPERTY(Transient, ReplicatedUsing=OnRep_RespawnState, BlueprintReadOnly, Category="Respawn")
    FASRespawnState RespawnState;

    UFUNCTION()
    void OnRep_RespawnState();
};
