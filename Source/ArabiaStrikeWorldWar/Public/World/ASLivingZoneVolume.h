#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Volume.h"
#include "ASLivingZoneVolume.generated.h"
UENUM(BlueprintType)
enum class EASLivingZoneType : uint8 { Exterior, Interior, Rooftop, Underground, Waterfront };
UCLASS()
class ARABIASTRIKEWORLDWAR_API AASLivingZoneVolume : public AVolume
{
    GENERATED_BODY()
public:
    AASLivingZoneVolume();
    UPROPERTY(EditAnywhere,BlueprintReadOnly,Category="Zone") EASLivingZoneType ZoneType=EASLivingZoneType::Exterior;
    UPROPERTY(EditAnywhere,BlueprintReadOnly,Category="Zone") FName ZoneId=NAME_None;
    UPROPERTY(EditAnywhere,BlueprintReadOnly,Category="Zone") FName DistrictId=NAME_None;
    UPROPERTY(EditAnywhere,BlueprintReadOnly,Category="Zone") bool bAllowsDynamicEncounters=true;
};
