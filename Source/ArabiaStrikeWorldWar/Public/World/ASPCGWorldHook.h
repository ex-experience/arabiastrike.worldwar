#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASPCGWorldHook.generated.h"
class UPCGComponent;

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASPCGWorldHook : public AActor
{
    GENERATED_BODY()
public:
    AASPCGWorldHook();
    UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category="PCG") TObjectPtr<UPCGComponent> PCGComponent;
    UFUNCTION(BlueprintCallable, Category="PCG") void GenerateWorldPatch(bool bForce = true);
};
