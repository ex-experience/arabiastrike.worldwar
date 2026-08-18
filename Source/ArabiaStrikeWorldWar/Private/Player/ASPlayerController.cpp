#include "Player/ASPlayerController.h"
#include "Player/ASCharacter.h"
#include "Player/ASPlayerState.h"
#include "Game/ASGameMode.h"
#include "Combat/ASHealthComponent.h"
#include "Combat/ASWeaponComponent.h"
#include "Engine/World.h"
#include "GameFramework/GameStateBase.h"
#include "Kismet/GameplayStatics.h"
#include "Net/UnrealNetwork.h"

void AASPlayerController::SendChat(const FString& Message, EASChatChannel Channel)
{
    const FString CleanMessage = Message.Left(MaxChatMessageLength).TrimStartAndEnd();
    if (!CleanMessage.IsEmpty() && IsValidChatChannel(Channel))
    {
        ServerSendChat(CleanMessage, Channel);
    }
}

void AASPlayerController::ServerSendChat_Implementation(const FString& Message, EASChatChannel Channel)
{
    if (!HasAuthority())
    {
        return;
    }

    UWorld* World = GetWorld();
    if (!World)
    {
        return;
    }

    // UWorld real time is monotonic for this server world and cannot be supplied or altered by a client RPC.
    const double ServerTime = static_cast<double>(World->GetRealTimeSeconds());
    PrepareChatRateLimitClock(ServerTime);

    if (!IsValidChatChannel(Channel))
    {
        RecordChatPolicyViolation(ServerTime, EASChatPolicyViolation::InvalidChannel);
        return;
    }

    const FString CleanMessage = Message.Left(MaxChatMessageLength).TrimStartAndEnd();
    if (CleanMessage.IsEmpty())
    {
        RecordChatPolicyViolation(ServerTime, EASChatPolicyViolation::EmptyMessage);
        return;
    }

    EASChatPolicyViolation ViolationReason = EASChatPolicyViolation::Cooldown;
    if (!CanAcceptChatMessage(ServerTime, ViolationReason))
    {
        RecordChatPolicyViolation(ServerTime, ViolationReason);
        return;
    }

    AASGameMode* GameMode = World->GetAuthGameMode<AASGameMode>();
    if (!GameMode)
    {
        return;
    }

    GameMode->BroadcastChat(this, CleanMessage, Channel);
}

bool AASPlayerController::IsValidChatChannel(EASChatChannel Channel)
{
    switch (Channel)
    {
        case EASChatChannel::Global:
        case EASChatChannel::Squad:
        case EASChatChannel::Proximity:
            return true;
        default:
            return false;
    }
}

bool AASPlayerController::CanAcceptChatMessage(double ServerTime, EASChatPolicyViolation& OutViolationReason)
{
    if (ChatBurstWindowStartServerTime < 0.0
        || ServerTime - ChatBurstWindowStartServerTime >= ChatBurstWindowSeconds)
    {
        ChatBurstWindowStartServerTime = ServerTime;
        AcceptedChatMessagesInBurst = 0;
    }

    if (AcceptedChatMessagesInBurst >= ChatBurstMessageLimit)
    {
        OutViolationReason = EASChatPolicyViolation::BurstLimit;
        return false;
    }

    if (LastAcceptedChatServerTime >= 0.0
        && ServerTime - LastAcceptedChatServerTime < ChatMinimumIntervalSeconds)
    {
        OutViolationReason = EASChatPolicyViolation::Cooldown;
        return false;
    }

    LastAcceptedChatServerTime = ServerTime;
    ++AcceptedChatMessagesInBurst;
    return true;
}

void AASPlayerController::PrepareChatRateLimitClock(double ServerTime)
{
    if (LastObservedChatServerTime >= 0.0 && ServerTime < LastObservedChatServerTime)
    {
        // Seamless travel or world replacement can restart world time while retaining the controller.
        ResetChatRateLimitState();
    }

    LastObservedChatServerTime = ServerTime;
}

void AASPlayerController::RecordChatPolicyViolation(double ServerTime, EASChatPolicyViolation Reason)
{
    if (ChatViolationWindowStartServerTime < 0.0
        || ServerTime - ChatViolationWindowStartServerTime >= ChatViolationWindowSeconds)
    {
        ChatViolationWindowStartServerTime = ServerTime;
        ChatViolationsInWindow = 0;
    }

    if (ChatViolationsInWindow < MAX_uint8)
    {
        ++ChatViolationsInWindow;
    }
    if (TotalChatPolicyViolations < MAX_uint16)
    {
        ++TotalChatPolicyViolations;
    }

    HandleChatPolicyViolation(Reason, ChatViolationsInWindow, TotalChatPolicyViolations);
}

void AASPlayerController::HandleChatPolicyViolation(
    EASChatPolicyViolation Reason,
    uint8 ViolationsInWindow,
    uint16 TotalViolations)
{
    // Intentionally non-punitive: moderation services can override this hook without changing RPC behavior.
    static_cast<void>(Reason);
    static_cast<void>(ViolationsInWindow);
    static_cast<void>(TotalViolations);
}

void AASPlayerController::ResetChatRateLimitState()
{
    LastAcceptedChatServerTime = -1.0;
    ChatBurstWindowStartServerTime = -1.0;
    ChatViolationWindowStartServerTime = -1.0;
    LastObservedChatServerTime = -1.0;
    AcceptedChatMessagesInBurst = 0;
    ChatViolationsInWindow = 0;
    TotalChatPolicyViolations = 0;
}

void AASPlayerController::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
    ResetChatRateLimitState();
    Super::EndPlay(EndPlayReason);
}

void AASPlayerController::ClientReceiveChat_Implementation(const FString&S,const FString&M,EASChatChannel C){OnChatReceived.Broadcast(S,M,C);}
AASCharacter*AASPlayerController::GetASCharacter()const{return Cast<AASCharacter>(GetPawn());}
float AASPlayerController::GetHealthRatio()const{const AASCharacter*C=GetASCharacter();const UASHealthComponent*H=C?C->GetHealthComponent():nullptr;return H?H->GetHealthRatio():0.f;}
FASAmmoState AASPlayerController::GetAmmoState()const{const AASCharacter*C=GetASCharacter();const UASWeaponComponent*W=C?C->GetWeaponComponent():nullptr;return W?W->GetAmmo():FASAmmoState();}
bool AASPlayerController::IsPlayerDowned()const{const AASCharacter*C=GetASCharacter();return C&&C->IsDowned();}

static AASMissionDirector* AS_FindMissionDirector(const UObject* WorldContext){return WorldContext?Cast<AASMissionDirector>(UGameplayStatics::GetActorOfClass(WorldContext,AASMissionDirector::StaticClass())):nullptr;}
EASMissionPhase AASPlayerController::GetMissionPhase()const{const AASMissionDirector*D=AS_FindMissionDirector(this);return D?D->GetPhase():EASMissionPhase::Insertion;}
int32 AASPlayerController::GetRescuedHostageCount()const{const AASMissionDirector*D=AS_FindMissionDirector(this);return D?D->GetRescuedHostages():0;}
int32 AASPlayerController::GetRequiredHostageCount()const{const AASMissionDirector*D=AS_FindMissionDirector(this);return D?D->GetRequiredHostages():0;}

EASCityDistrict AASPlayerController::GetCurrentDistrict()const{const AASPlayerState*PS=GetPlayerState<AASPlayerState>();return PS?PS->CurrentDistrict:EASCityDistrict::Corniche;}

float AASPlayerController::GetRespawnTimeRemaining() const
{
    if (!RespawnState.bPending)
    {
        return 0.f;
    }

    const UWorld* World = GetWorld();
    const AGameStateBase* CurrentGameState = World ? World->GetGameState() : nullptr;
    const double ServerTime = CurrentGameState
        ? CurrentGameState->GetServerWorldTimeSeconds()
        : (World ? World->GetTimeSeconds() : 0.0);
    return static_cast<float>(FMath::Max(0.0, RespawnState.EndServerTime - ServerTime));
}

void AASPlayerController::SetRespawnState(bool bPending, double EndServerTime)
{
    if (!HasAuthority())
    {
        return;
    }

    const bool bChanged = RespawnState.bPending != bPending
        || !FMath::IsNearlyEqual(RespawnState.EndServerTime, EndServerTime);
    RespawnState.bPending = bPending;
    RespawnState.EndServerTime = bPending ? EndServerTime : 0.0;

    if (bChanged)
    {
        OnRep_RespawnState();
        ForceNetUpdate();
    }
}

void AASPlayerController::OnRep_RespawnState()
{
    OnRespawnStateChanged.Broadcast(RespawnState.bPending, GetRespawnTimeRemaining());
}

void AASPlayerController::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME(AASPlayerController, RespawnState);
}
