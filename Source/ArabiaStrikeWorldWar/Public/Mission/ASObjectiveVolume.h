#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASObjectiveVolume.generated.h"

class UBoxComponent;
class AASMissionDirector;

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASObjectiveVolume : public AActor
{
    GENERATED_BODY()

public:
    AASObjectiveVolume();

protected:
    UPROPERTY(VisibleAnywhere)
    TObjectPtr<UBoxComponent> Volume;

    UPROPERTY(EditInstanceOnly)
    TObjectPtr<AASMissionDirector> Director;

    UPROPERTY(EditAnywhere)
    bool bOneShot = true;

    bool bUsed = false;

    UFUNCTION()
    void Enter(
        UPrimitiveComponent* OverlappedComponent,
        AActor* OtherActor,
        UPrimitiveComponent* OtherComp,
        int32 OtherBodyIndex,
        bool bFromSweep,
        const FHitResult& SweepResult
    );
};