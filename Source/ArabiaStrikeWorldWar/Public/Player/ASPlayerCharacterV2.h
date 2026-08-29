#pragma once

#include "CoreMinimal.h"
#include "Player/ASCharacter.h"
#include "ASPlayerCharacterV2.generated.h"

UENUM(BlueprintType)
enum class EASMovementStance : uint8
{
    Standing UMETA(DisplayName="Standing"),
    Crouched UMETA(DisplayName="Crouched"),
    Prone UMETA(DisplayName="Prone"),
    Sliding UMETA(DisplayName="Sliding")
};

UENUM(BlueprintType)
enum class EASCombatReadyState : uint8
{
    Relaxed UMETA(DisplayName="Relaxed"),
    LowReady UMETA(DisplayName="Low Ready"),
    HighReady UMETA(DisplayName="High Ready"),
    ADS UMETA(DisplayName="ADS")
};

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASPlayerCharacterV2 : public AASCharacter
{
    GENERATED_BODY()

public:
    AASPlayerCharacterV2(const FObjectInitializer& ObjectInitializer = FObjectInitializer::Get());

    virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;
    virtual void Tick(float DeltaSeconds) override;

    UFUNCTION(BlueprintPure, Category="ASWW|Player Foundation")
    EASMovementStance GetMovementStance() const { return MovementStance; }

    UFUNCTION(BlueprintPure, Category="ASWW|Player Foundation")
    EASCombatReadyState GetCombatReadyState() const { return CombatReadyState; }

    UFUNCTION(BlueprintPure, Category="ASWW|Player Foundation")
    bool IsAiming() const { return bAimHeld; }

    UFUNCTION(BlueprintPure, Category="ASWW|Player Foundation")
    bool IsSprintingV2() const { return bSprintHeldV2; }

protected:
    virtual void BeginPlay() override;

    void MoveForwardV2(float Value);
    void MoveRightV2(float Value);
    void TurnV2(float Value);
    void LookUpV2(float Value);

    void JumpOrMantlePressed();
    bool TryMantle();

    void SprintPressedV2();
    void SprintReleasedV2();
    void CrouchSlidePressed();
    void PronePressed();

    void AimPressed();
    void AimReleased();

    void FreeLookPressed();
    void FreeLookReleased();

    void CombatStancePressed();

    void FirePressedV2();
    void FireReleasedV2();
    void ReloadPressedV2();
    void InteractPressedV2();
    void VehicleInteractPressedV2();
    void GrenadePressedV2();
    void MeleePressedV2();
    void FireModePressedV2();

    void Weapon1PressedV2();
    void Weapon2PressedV2();
    void Weapon3PressedV2();
    void Weapon4PressedV2();

    void StartSlide();
    void StopSlide();
    void EnterProne();
    void ExitProne();
    void ExitCrouchIfNeeded();
    void UpdateMovementProfile();
    void UpdateCamera(float DeltaSeconds);

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Movement")
    float TacticalWalkSpeed = 360.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Movement")
    float CombatJogSpeed = 520.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Movement")
    float TacticalSprintSpeed = 760.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Movement")
    float CrouchMoveSpeed = 280.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Movement")
    float ProneMoveSpeed = 150.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Movement")
    float AimMoveSpeed = 340.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Slide")
    float SlideMinSpeed = 430.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Slide")
    float SlideImpulse = 520.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Slide")
    float SlideDuration = 0.65f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Prone")
    float ProneCapsuleHalfHeight = 44.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Mantle")
    float MantleForwardProbe = 95.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Mantle")
    float MantleLowHeight = 45.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Mantle")
    float MantleHighHeight = 125.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Camera")
    float DefaultCameraFOV = 90.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Camera")
    float ADSCameraFOV = 72.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Camera")
    float CameraFOVInterpSpeed = 12.f;

    UPROPERTY(EditDefaultsOnly, Category="ASWW|Camera")
    float CameraArmLength = 320.f;

    UPROPERTY(BlueprintReadOnly, Category="ASWW|Player Foundation")
    EASMovementStance MovementStance = EASMovementStance::Standing;

    UPROPERTY(BlueprintReadOnly, Category="ASWW|Player Foundation")
    EASCombatReadyState CombatReadyState = EASCombatReadyState::LowReady;

    bool bSprintHeldV2 = false;
    bool bAimHeld = false;
    bool bFreeLookHeld = false;

    float StandingCapsuleHalfHeight = 88.f;

    FTimerHandle SlideTimerHandle;
};