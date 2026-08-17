#pragma once
#include "CoreMinimal.h"
#include "UObject/Interface.h"
#include "ASInteractable.generated.h"
UINTERFACE(Blueprintable) class UASInteractable:public UInterface{GENERATED_BODY()};
class ARABIASTRIKEWORLDWAR_API IASInteractable{GENERATED_BODY() public: UFUNCTION(BlueprintNativeEvent,BlueprintCallable) FText GetInteractionLabel(APawn* Pawn) const; UFUNCTION(BlueprintNativeEvent,BlueprintCallable) bool Interact(APawn* Pawn);};
