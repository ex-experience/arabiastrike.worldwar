#include "Offline/ASOfflineHUD.h"

#include "Combat/ASCombatTypes.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "EngineUtils.h"
#include "Offline/ASOfflineDirector.h"
#include "Offline/ASOfflineLivingCityDirector.h"
#include "Player/ASPlayerController.h"

void AASOfflineHUD::DrawHUD()
{
    Super::DrawHUD();
    if (!Canvas) return;

    AASPlayerController* PC = Cast<AASPlayerController>(PlayerOwner);
    if (!PC) return;

    AASOfflineDirector* Director = nullptr;
    for (TActorIterator<AASOfflineDirector> It(GetWorld()); It; ++It)
    {
        Director = *It;
        break;
    }

    AASOfflineLivingCityDirector* City = nullptr;
    for (TActorIterator<AASOfflineLivingCityDirector> It(GetWorld()); It; ++It)
    {
        City = *It;
        break;
    }

    const float Health = FMath::Clamp(PC->GetHealthRatio(), 0.f, 1.f) * 100.f;
    const FASAmmoState Ammo = PC->GetAmmoState();
    const FString Objective = Director ? Director->GetObjectiveText() : TEXT("OFFLINE OPERATION INITIALIZING");
    const int32 Hostiles = Director ? Director->GetLivingEnemyCount() : 0;
    const int32 Civilians = Director ? Director->GetCivilianCount() : 0;
    const int32 Traffic = Director ? Director->GetTrafficVehicleCount() : 0;
    const float Distance = Director ? Director->GetObjectiveDistance() : -1.f;

    UFont* Font = GEngine ? GEngine->GetSmallFont() : nullptr;
    if (!Font) return;

    DrawText(TEXT("ARABIA STRIKE  //  JEDDAH OFFLINE"), FLinearColor::White, 34.f, 30.f, Font, 1.18f, false);
    DrawText(Objective, FLinearColor(.95f, .78f, .24f, 1.f), 34.f, 57.f, Font, 1.f, false);
    DrawText(
        FString::Printf(TEXT("HEALTH %03.0f    AMMO %02d / %03d    HOSTILES %02d"), Health, Ammo.Magazine, Ammo.Reserve, Hostiles),
        FLinearColor::White, 34.f, 84.f, Font, 1.f, false);
    DrawText(
        FString::Printf(TEXT("CIVILIANS %02d    TRAFFIC %02d"), Civilians, Traffic),
        FLinearColor(.35f, .85f, .95f, 1.f), 34.f, 108.f, Font, 1.f, false);
    if (City)
    {
        DrawText(
            FString::Printf(
                TEXT("LIVING DISTRICT  |  BUILDINGS %02d  ROADS %02d  TIME %05.2f"),
                City->GetBuildingCount(), City->GetRoadCount(), City->GetTimeOfDayHours()),
            FLinearColor(.5f, .72f, 1.f, 1.f), 34.f, 132.f, Font, .9f, false);
    }
    if (Distance >= 0.f)
    {
        DrawText(
            FString::Printf(TEXT("OBJECTIVE DISTANCE %.0f m"), Distance / 100.f),
            FLinearColor(.35f, .95f, .55f, 1.f), 34.f, 156.f, Font, 1.f, false);
    }
    DrawText(
        TEXT("WASD MOVE  |  RMB AIM  |  LMB FIRE  |  R RELOAD  |  F VEHICLE  |  G GRENADE"),
        FLinearColor(.75f, .8f, .82f, 1.f), 34.f, Canvas->ClipY - 42.f, Font, .9f, false);

    const float CenterX = Canvas->ClipX * .5f;
    const float CenterY = Canvas->ClipY * .5f;
    const float Arm = 8.f;
    const float Gap = 4.f;
    const FLinearColor Crosshair(1.f, 1.f, 1.f, .9f);
    DrawLine(CenterX - Gap - Arm, CenterY, CenterX - Gap, CenterY, Crosshair, 1.2f);
    DrawLine(CenterX + Gap, CenterY, CenterX + Gap + Arm, CenterY, Crosshair, 1.2f);
    DrawLine(CenterX, CenterY - Gap - Arm, CenterX, CenterY - Gap, Crosshair, 1.2f);
    DrawLine(CenterX, CenterY + Gap, CenterX, CenterY + Gap + Arm, Crosshair, 1.2f);
}
