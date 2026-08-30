#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASTrafficVehicleAgent.generated.h"
class AASTrafficRoute;
class UStaticMeshComponent;
UENUM(BlueprintType) enum class EASTrafficBehavior : uint8 { Normal, Yielding, Evacuating, Stopped };

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASTrafficVehicleAgent : public AActor
{
    GENERATED_BODY()
public:
    AASTrafficVehicleAgent();
    virtual void BeginPlay() override;
    virtual void Tick(float DeltaSeconds) override;

    UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category="Traffic")
    TObjectPtr<UStaticMeshComponent> VehicleMesh;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Traffic") float CruiseSpeedCmPerSecond = 1400.0f;
    UPROPERTY(BlueprintReadOnly, Category="Traffic") TObjectPtr<AASTrafficRoute> AssignedRoute;
    UPROPERTY(Replicated, BlueprintReadOnly, Category="Traffic") EASTrafficBehavior TrafficBehavior=EASTrafficBehavior::Normal;
    UFUNCTION(BlueprintCallable,BlueprintAuthorityOnly,Category="Traffic") void SetTrafficBehavior(EASTrafficBehavior NewBehavior);

    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly, Category="Traffic") void AssignRoute(AASTrafficRoute* Route, float InitialDistance = 0.0f);

protected:
    UPROPERTY(Replicated, BlueprintReadOnly, Category="Traffic") float DistanceAlongRoute = 0.0f;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
};
