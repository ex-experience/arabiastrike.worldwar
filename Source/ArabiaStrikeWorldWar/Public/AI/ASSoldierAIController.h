#pragma once
#include "CoreMinimal.h"
#include "AIController.h"
#include "ASSoldierAIController.generated.h"
UCLASS() class ARABIASTRIKEWORLDWAR_API AASSoldierAIController:public AAIController{GENERATED_BODY() public:AASSoldierAIController();virtual void Tick(float)override;protected:UPROPERTY(EditDefaultsOnly)float AcquireRadius=4500.f;UPROPERTY(EditDefaultsOnly)float FireDistance=2200.f;TWeakObjectPtr<APawn> Target;void AcquireTarget();};
