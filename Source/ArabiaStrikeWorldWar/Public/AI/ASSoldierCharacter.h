#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "ASSoldierCharacter.generated.h"
class UASHealthComponent; class UASWeaponComponent;
UCLASS() class ARABIASTRIKEWORLDWAR_API AASSoldierCharacter:public ACharacter{GENERATED_BODY()public:AASSoldierCharacter();virtual void Tick(float)override;protected:UPROPERTY(VisibleAnywhere)TObjectPtr<UASHealthComponent>Health;UPROPERTY(VisibleAnywhere)TObjectPtr<UASWeaponComponent>Weapon;UPROPERTY(EditDefaultsOnly)float FireDistance=2200.f;double NextShot=0;};
