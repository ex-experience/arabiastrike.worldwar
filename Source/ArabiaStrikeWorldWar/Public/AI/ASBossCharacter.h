#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "ASBossCharacter.generated.h"
class UASHealthComponent;

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASBossCharacter : public ACharacter
{
    GENERATED_BODY()
public:
    AASBossCharacter();
    virtual void Tick(float DeltaSeconds) override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
    UPROPERTY(Replicated, BlueprintReadOnly) int32 Phase = 1;
protected:
    UPROPERTY(VisibleAnywhere, BlueprintReadOnly) TObjectPtr<UASHealthComponent> Health;
    UPROPERTY(EditDefaultsOnly) int32 MaxPhases = 4;
};
