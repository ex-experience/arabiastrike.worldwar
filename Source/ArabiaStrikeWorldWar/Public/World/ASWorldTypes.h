#pragma once
#include "CoreMinimal.h"
#include "ASWorldTypes.generated.h"

UENUM(BlueprintType)
enum class EASCityDistrict : uint8
{
    Corniche,
    AlBalad,
    Port,
    Industrial,
    Airport,
    DesertOutskirts
};

UENUM(BlueprintType)
enum class EASWeatherType : uint8
{
    Clear,
    Haze,
    Rain,
    Storm,
    Sandstorm,
    Fog
};

USTRUCT(BlueprintType)
struct FASWorldEnvironmentState
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, BlueprintReadWrite) float TimeOfDayHours = 17.5f;
    UPROPERTY(EditAnywhere, BlueprintReadWrite) EASWeatherType Weather = EASWeatherType::Clear;
    UPROPERTY(EditAnywhere, BlueprintReadWrite) float WeatherIntensity = 0.0f;
    UPROPERTY(EditAnywhere, BlueprintReadWrite) float VisibilityScalar = 1.0f;
    UPROPERTY(EditAnywhere, BlueprintReadWrite) float WindSpeedKph = 8.0f;
};

USTRUCT(BlueprintType)
struct FASDistrictRuntimeProfile
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, BlueprintReadWrite) EASCityDistrict District = EASCityDistrict::Corniche;
    UPROPERTY(EditAnywhere, BlueprintReadWrite) float TrafficDensity = 0.6f;
    UPROPERTY(EditAnywhere, BlueprintReadWrite) float CivilianDensity = 0.6f;
    UPROPERTY(EditAnywhere, BlueprintReadWrite) int32 ThreatModifier = 0;
};
