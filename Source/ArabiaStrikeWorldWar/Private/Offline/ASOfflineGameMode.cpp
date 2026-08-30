#include "Offline/ASOfflineGameMode.h"

#include "Engine/World.h"
#include "Kismet/GameplayStatics.h"
#include "Offline/ASOfflineDirector.h"
#include "Offline/ASOfflineHUD.h"
#include "Offline/ASOfflineLivingCityDirector.h"
#include "Player/ASPlayerCharacterV2.h"
#include "Player/ASPlayerController.h"

AASOfflineGameMode::AASOfflineGameMode()
{
    DefaultPawnClass = AASPlayerCharacterV2::StaticClass();
    PlayerControllerClass = AASPlayerController::StaticClass();
    HUDClass = AASOfflineHUD::StaticClass();
}

void AASOfflineGameMode::StartPlay()
{
    Super::StartPlay();
    if (!HasAuthority() || !GetWorld()) return;
    if (!UGameplayStatics::GetActorOfClass(this, AASOfflineDirector::StaticClass()))
    {
        GetWorld()->SpawnActor<AASOfflineDirector>(
            AASOfflineDirector::StaticClass(), FVector::ZeroVector, FRotator::ZeroRotator);
    }
    if (!UGameplayStatics::GetActorOfClass(this, AASOfflineLivingCityDirector::StaticClass()))
    {
        GetWorld()->SpawnActor<AASOfflineLivingCityDirector>(
            AASOfflineLivingCityDirector::StaticClass(), FVector::ZeroVector, FRotator::ZeroRotator);
    }
}
