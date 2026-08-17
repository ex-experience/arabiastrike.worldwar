#pragma once
#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "Online/ASChatTypes.h"
#include "Combat/ASCombatTypes.h"
#include "Mission/ASMissionDirector.h"
#include "ASPlayerController.generated.h"
class AASCharacter;
DECLARE_DYNAMIC_MULTICAST_DELEGATE_ThreeParams(FASChatReceived,FString,Sender,FString,Message,EASChatChannel,Channel);
UCLASS()
class ARABIASTRIKEWORLDWAR_API AASPlayerController : public APlayerController
{
    GENERATED_BODY()
public:
    UPROPERTY(BlueprintAssignable) FASChatReceived OnChatReceived;
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
};
