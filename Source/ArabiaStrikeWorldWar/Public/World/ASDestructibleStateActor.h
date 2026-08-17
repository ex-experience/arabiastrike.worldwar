#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASDestructibleStateActor.generated.h"
UENUM(BlueprintType)
enum class EASDestructionState : uint8 { Intact, Damaged, Critical, Destroyed };

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASDestructibleStateActor : public AActor
{
    GENERATED_BODY()
public:
    AASDestructibleStateActor();
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Destruction") float MaxStructuralHealth=1000.f;
    UPROPERTY(ReplicatedUsing=OnRep_StructuralState, BlueprintReadOnly, Category="Destruction") float StructuralHealth=1000.f;
    UPROPERTY(ReplicatedUsing=OnRep_StructuralState, BlueprintReadOnly, Category="Destruction") EASDestructionState DestructionState=EASDestructionState::Intact;
    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly, Category="Destruction") void ApplyStructuralDamage(float DamageAmount);
protected:
    UFUNCTION() void OnRep_StructuralState();
    UFUNCTION(BlueprintImplementableEvent, Category="Destruction") void BP_ApplyDestructionPresentation(EASDestructionState State,float NormalizedHealth);
    void AuthorityUpdateState();
};
