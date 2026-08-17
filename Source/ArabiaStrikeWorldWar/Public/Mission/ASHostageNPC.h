#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "Interaction/ASInteractable.h"
#include "ASHostageNPC.generated.h"
class AASMissionDirector;
UCLASS()
class ARABIASTRIKEWORLDWAR_API AASHostageNPC : public ACharacter, public IASInteractable
{
    GENERATED_BODY()
public:
    AASHostageNPC();
    virtual FText GetInteractionLabel_Implementation(APawn* InteractingPawn) const override;
    virtual bool Interact_Implementation(APawn* InteractingPawn) override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
    UFUNCTION(BlueprintPure) bool IsRescued() const { return bRescued; }
protected:
    UPROPERTY(EditInstanceOnly,BlueprintReadOnly) TObjectPtr<AASMissionDirector> MissionDirector;
    UPROPERTY(ReplicatedUsing=OnRep_Rescued,BlueprintReadOnly) bool bRescued=false;
    UFUNCTION() void OnRep_Rescued();
};
