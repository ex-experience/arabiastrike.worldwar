#pragma once
#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "AI/ASSquadTypes.h"
#include "ASSquadComponent.generated.h"

DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FASTacticalStateChanged, EASTacticalState, State, float, Suppression);

UCLASS(ClassGroup=(AI), meta=(BlueprintSpawnableComponent))
class ARABIASTRIKEWORLDWAR_API UASSquadComponent : public UActorComponent
{
    GENERATED_BODY()
public:
    UASSquadComponent();
    virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

    UPROPERTY(BlueprintAssignable) FASTacticalStateChanged OnTacticalStateChanged;
    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly) void AddSuppression(float Amount);
    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly) void SetTacticalState(EASTacticalState NewState);
    UFUNCTION(BlueprintPure) float GetSuppression() const { return Suppression; }
    UFUNCTION(BlueprintPure) EASSquadRole GetRole() const { return Role; }
    UFUNCTION(BlueprintPure) EASTacticalState GetState() const { return TacticalState; }

protected:
    UPROPERTY(EditAnywhere, Replicated, BlueprintReadOnly, Category="Squad") int32 SquadId = 1;
    UPROPERTY(EditAnywhere, Replicated, BlueprintReadOnly, Category="Squad") EASSquadRole Role = EASSquadRole::Rifleman;
    UPROPERTY(ReplicatedUsing=OnRep_Tactical, BlueprintReadOnly, Category="Squad") EASTacticalState TacticalState = EASTacticalState::Advance;
    UPROPERTY(ReplicatedUsing=OnRep_Tactical, BlueprintReadOnly, Category="Squad") float Suppression = 0.f;
    UPROPERTY(EditDefaultsOnly, Category="Squad") float SuppressionDecayPerSecond = 0.22f;
    UFUNCTION() void OnRep_Tactical();
};
