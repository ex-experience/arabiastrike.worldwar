#include "Player/ASPlayerController.h"
#include "Player/ASCharacter.h"
#include "Player/ASPlayerState.h"
#include "Game/ASGameMode.h"
#include "Combat/ASHealthComponent.h"
#include "Combat/ASWeaponComponent.h"
#include "Kismet/GameplayStatics.h"
void AASPlayerController::SendChat(const FString&M,EASChatChannel C){FString Clean=M.Left(180).TrimStartAndEnd();if(!Clean.IsEmpty())ServerSendChat(Clean,C);}
void AASPlayerController::ServerSendChat_Implementation(const FString&M,EASChatChannel C){FString Clean=M.Left(180).TrimStartAndEnd();if(Clean.IsEmpty())return;if(AASGameMode*GM=GetWorld()?GetWorld()->GetAuthGameMode<AASGameMode>():nullptr)GM->BroadcastChat(this,Clean,C);}
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
