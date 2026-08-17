#pragma once
#include "CoreMinimal.h"
#include "Engine/TriggerBox.h"
#include "World/ASWorldTypes.h"
#include "ASDistrictVolume.generated.h"

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASDistrictVolume : public ATriggerBox
{
    GENERATED_BODY()
public:
    AASDistrictVolume();

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="District") FASDistrictRuntimeProfile Profile;

protected:
    virtual void BeginPlay() override;
    UFUNCTION() void HandleBeginOverlap(AActor* OverlappedActor, AActor* OtherActor);
};
