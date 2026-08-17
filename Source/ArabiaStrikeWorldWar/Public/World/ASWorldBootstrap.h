#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASWorldBootstrap.generated.h"

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASWorldBootstrap : public AActor
{
    GENERATED_BODY()
public:
    AASWorldBootstrap();
    virtual void BeginPlay() override;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="World") bool bRequireWorldPartition = true;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="World") TSubclassOf<AActor> EnvironmentDirectorClass;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="World") TSubclassOf<AActor> EncounterDirectorClass;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="World") TSubclassOf<AActor> WorldEventDirectorClass;

    UFUNCTION(BlueprintPure, Category="World") bool IsWorldPartitionActive() const;

private:
    void SpawnDirectorIfMissing(TSubclassOf<AActor> ActorClass);
};
