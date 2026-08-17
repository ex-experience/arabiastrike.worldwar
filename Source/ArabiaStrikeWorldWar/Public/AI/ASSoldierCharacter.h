#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "Combat/ASSuppressible.h"
#include "ASSoldierCharacter.generated.h"
class UASHealthComponent; class UASWeaponComponent; class UASSquadComponent;
UCLASS()
class ARABIASTRIKEWORLDWAR_API AASSoldierCharacter : public ACharacter, public IASSuppressible
{
    GENERATED_BODY()
public:
    AASSoldierCharacter();
    virtual void Tick(float DeltaSeconds) override;
    virtual void ApplySuppression_Implementation(float Amount, FVector SourceLocation) override;
    UFUNCTION(BlueprintPure) UASSquadComponent* GetSquadComponent() const { return Squad; }
    UFUNCTION(BlueprintPure) UASWeaponComponent* GetWeaponComponent() const { return Weapon; }
protected:
    UPROPERTY(VisibleAnywhere) TObjectPtr<UASHealthComponent> Health;
    UPROPERTY(VisibleAnywhere) TObjectPtr<UASWeaponComponent> Weapon;
    UPROPERTY(VisibleAnywhere) TObjectPtr<UASSquadComponent> Squad;
    UPROPERTY(EditDefaultsOnly) float FireDistance=2200.f;
    double NextShot=0;
};
