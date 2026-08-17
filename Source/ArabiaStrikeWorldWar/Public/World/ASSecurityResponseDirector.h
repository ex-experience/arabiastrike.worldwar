#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASSecurityResponseDirector.generated.h"
class APawn;

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASSecurityResponseDirector : public AActor
{
    GENERATED_BODY()
public:
    AASSecurityResponseDirector();
    virtual void BeginPlay() override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Security") TSubclassOf<APawn> SecurityUnitClass;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Security") TArray<TObjectPtr<AActor>> ReinforcementAnchors;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Security") int32 MaxActiveSecurityUnits = 12;
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Security") float ResponseIntervalSeconds = 5.f;
    UPROPERTY(ReplicatedUsing=OnRep_ResponseTier, BlueprintReadOnly, Category="Security") int32 ResponseTier = 0;
    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly, Category="Security") void SetResponseTier(int32 NewTier);
protected:
    UFUNCTION() void OnRep_ResponseTier();
    UFUNCTION(BlueprintImplementableEvent, Category="Security") void BP_OnResponseTierChanged(int32 NewTier);
    void AuthorityEvaluateResponse();
    int32 CountActiveSecurityUnits() const;
    FTimerHandle ResponseTimer;
};
