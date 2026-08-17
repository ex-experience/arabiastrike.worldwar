#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "World/ASWorldTypes.h"
#include "ASCivilianDirector.generated.h"
class AASCivilianCharacter;

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASCivilianDirector : public AActor
{
    GENERATED_BODY()
public:
    AASCivilianDirector();
    virtual void BeginPlay() override;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Civilian") EASCityDistrict District = EASCityDistrict::Corniche;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Civilian") TArray<TSubclassOf<AASCivilianCharacter>> CivilianClasses;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Civilian") TArray<TObjectPtr<AActor>> SpawnAnchors;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Civilian", meta=(ClampMin="0", ClampMax="200")) int32 MaxActiveCivilians = 24;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Civilian", meta=(ClampMin="100")) float SpawnRadius = 1200.0f;

private:
    FTimerHandle SpawnTimer;
    TArray<TWeakObjectPtr<AASCivilianCharacter>> ActiveCivilians;
    void AuthorityMaintainPopulation();
};
