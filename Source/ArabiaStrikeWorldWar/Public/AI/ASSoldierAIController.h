#pragma once
#include "CoreMinimal.h"
#include "AIController.h"
#include "ASSoldierAIController.generated.h"
UCLASS()
class ARABIASTRIKEWORLDWAR_API AASSoldierAIController : public AAIController
{
    GENERATED_BODY()
public:
    AASSoldierAIController();
    virtual void Tick(float DeltaSeconds) override;
protected:
    UPROPERTY(EditDefaultsOnly) float AcquireRadius=4500.f;
    UPROPERTY(EditDefaultsOnly) float FireDistance=2200.f;
    UPROPERTY(EditDefaultsOnly) float TacticalRepathSeconds=0.8f;
    UPROPERTY(EditDefaultsOnly) float FlankDistance=950.f;
    UPROPERTY(EditDefaultsOnly) float SuppressedFallbackDistance=700.f;
    TWeakObjectPtr<APawn> Target;
    double NextTacticalUpdate=0.0;
    void AcquireTarget();
    void UpdateTactics();
    bool MoveToTacticalOffset(const FVector& OffsetFromTarget, float AcceptanceRadius=120.f);
};
