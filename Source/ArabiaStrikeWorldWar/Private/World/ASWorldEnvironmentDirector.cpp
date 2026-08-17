#include "World/ASWorldEnvironmentDirector.h"
#include "Net/UnrealNetwork.h"
#include "TimerManager.h"

AASWorldEnvironmentDirector::AASWorldEnvironmentDirector()
{
    bReplicates = true;
    bAlwaysRelevant = true;
    PrimaryActorTick.bCanEverTick = false;
}

void AASWorldEnvironmentDirector::BeginPlay()
{
    Super::BeginPlay();
    BroadcastEnvironmentState();
    if (HasAuthority())
    {
        GetWorldTimerManager().SetTimer(UpdateTimer, this, &AASWorldEnvironmentDirector::AuthorityUpdateEnvironment, UpdateIntervalSeconds, true);
    }
}

void AASWorldEnvironmentDirector::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME(AASWorldEnvironmentDirector, EnvironmentState);
}

void AASWorldEnvironmentDirector::AuthorityUpdateEnvironment()
{
    if (!HasAuthority() || !bAdvanceTime) return;
    EnvironmentState.TimeOfDayHours = FMath::Fmod(EnvironmentState.TimeOfDayHours + (GameMinutesPerRealSecond * UpdateIntervalSeconds / 60.0f), 24.0f);
    if (EnvironmentState.TimeOfDayHours < 0.0f) EnvironmentState.TimeOfDayHours += 24.0f;
    BroadcastEnvironmentState();
    ForceNetUpdate();
}

void AASWorldEnvironmentDirector::SetTimeOfDay(float Hours)
{
    if (!HasAuthority()) return;
    EnvironmentState.TimeOfDayHours = FMath::Fmod(FMath::Max(0.0f, Hours), 24.0f);
    BroadcastEnvironmentState();
    ForceNetUpdate();
}

void AASWorldEnvironmentDirector::SetWeather(EASWeatherType Weather, float Intensity)
{
    if (!HasAuthority()) return;
    EnvironmentState.Weather = Weather;
    EnvironmentState.WeatherIntensity = FMath::Clamp(Intensity, 0.0f, 1.0f);

    switch (Weather)
    {
        case EASWeatherType::Sandstorm:
            EnvironmentState.VisibilityScalar = FMath::Lerp(0.65f, 0.12f, EnvironmentState.WeatherIntensity);
            EnvironmentState.WindSpeedKph = FMath::Lerp(25.0f, 85.0f, EnvironmentState.WeatherIntensity);
            break;
        case EASWeatherType::Storm:
            EnvironmentState.VisibilityScalar = FMath::Lerp(0.85f, 0.35f, EnvironmentState.WeatherIntensity);
            EnvironmentState.WindSpeedKph = FMath::Lerp(20.0f, 70.0f, EnvironmentState.WeatherIntensity);
            break;
        case EASWeatherType::Fog:
            EnvironmentState.VisibilityScalar = FMath::Lerp(0.75f, 0.20f, EnvironmentState.WeatherIntensity);
            EnvironmentState.WindSpeedKph = 4.0f;
            break;
        case EASWeatherType::Rain:
            EnvironmentState.VisibilityScalar = FMath::Lerp(0.95f, 0.60f, EnvironmentState.WeatherIntensity);
            EnvironmentState.WindSpeedKph = FMath::Lerp(10.0f, 35.0f, EnvironmentState.WeatherIntensity);
            break;
        case EASWeatherType::Haze:
            EnvironmentState.VisibilityScalar = FMath::Lerp(0.90f, 0.55f, EnvironmentState.WeatherIntensity);
            EnvironmentState.WindSpeedKph = 6.0f;
            break;
        default:
            EnvironmentState.VisibilityScalar = 1.0f;
            EnvironmentState.WindSpeedKph = 8.0f;
            break;
    }

    BroadcastEnvironmentState();
    ForceNetUpdate();
}

float AASWorldEnvironmentDirector::GetSunPitchDegrees() const
{
    const float Normalized = EnvironmentState.TimeOfDayHours / 24.0f;
    return (Normalized * 360.0f) - 90.0f;
}

void AASWorldEnvironmentDirector::OnRep_EnvironmentState()
{
    BroadcastEnvironmentState();
}

void AASWorldEnvironmentDirector::BroadcastEnvironmentState()
{
    OnEnvironmentStateChanged.Broadcast(EnvironmentState);
    BP_ApplyEnvironmentState(EnvironmentState);
}
