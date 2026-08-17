#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "ASCharacter.generated.h"

class UASHealthComponent;
class UASWeaponComponent;
class USpringArmComponent;
class UCameraComponent;

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASCharacter : public ACharacter
{
    GENERATED_BODY()
public:
    AASCharacter();
    virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;
    virtual void Tick(float DeltaSeconds) override;
    UFUNCTION(BlueprintPure) UASHealthComponent* GetHealthComponent() const { return Health; }

protected:
    virtual void BeginPlay() override;

    UPROPERTY(VisibleAnywhere, BlueprintReadOnly) TObjectPtr<USpringArmComponent> CameraBoom;
    UPROPERTY(VisibleAnywhere, BlueprintReadOnly) TObjectPtr<UCameraComponent> FollowCamera;
    UPROPERTY(VisibleAnywhere, BlueprintReadOnly) TObjectPtr<UASHealthComponent> Health;
    UPROPERTY(VisibleAnywhere, BlueprintReadOnly) TObjectPtr<UASWeaponComponent> Weapon;

    UPROPERTY(EditDefaultsOnly, Category="Movement") float WalkSpeed = 520.f;
    UPROPERTY(EditDefaultsOnly, Category="Movement") float SprintSpeed = 820.f;
    UPROPERTY(EditDefaultsOnly, Category="Movement") float DashStrength = 1100.f;
    UPROPERTY(EditDefaultsOnly, Category="Movement") float DashCooldown = 1.0f;

    bool bSprintHeld = false;
    bool bFireHeld = false;
    double LastDashTime = -1000.0;

    void MoveForward(float Value);
    void MoveRight(float Value);
    void Turn(float Value);
    void LookUp(float Value);
    void SprintPressed();
    void SprintReleased();
    void FirePressed();
    void FireReleased();
    void Dash();
    void FireOnce();
};
