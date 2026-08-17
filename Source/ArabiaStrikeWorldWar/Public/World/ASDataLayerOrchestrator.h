#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASDataLayerOrchestrator.generated.h"
UENUM(BlueprintType)
enum class EASDataLayerIntent : uint8 { Unloaded, Loaded, Activated };
USTRUCT(BlueprintType)
struct FASDataLayerRequest
{
    GENERATED_BODY()
    UPROPERTY(EditAnywhere,BlueprintReadWrite) FName DataLayerName=NAME_None;
    UPROPERTY(EditAnywhere,BlueprintReadWrite) EASDataLayerIntent Intent=EASDataLayerIntent::Loaded;
};
UCLASS()
class ARABIASTRIKEWORLDWAR_API AASDataLayerOrchestrator : public AActor
{
    GENERATED_BODY()
public:
    AASDataLayerOrchestrator();
    UPROPERTY(EditAnywhere,BlueprintReadOnly,Category="World|DataLayers") TArray<FASDataLayerRequest> StartupLayers;
    UFUNCTION(BlueprintCallable,Category="World|DataLayers") void ApplyLayerIntent(FName DataLayerName,EASDataLayerIntent Intent);
    UFUNCTION(BlueprintCallable,Category="World|DataLayers") void ApplyStartupLayers();
protected:
    virtual void BeginPlay() override;
    UFUNCTION(BlueprintImplementableEvent,Category="World|DataLayers") void BP_ApplyRuntimeDataLayerState(FName DataLayerName,EASDataLayerIntent Intent);
};
