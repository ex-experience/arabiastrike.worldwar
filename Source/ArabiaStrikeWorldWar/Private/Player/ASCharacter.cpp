#include "Player/ASCharacter.h"
#include "Combat/ASHealthComponent.h"
#include "Combat/ASWeaponComponent.h"
#include "Camera/CameraComponent.h"
#include "GameFramework/SpringArmComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Components/InputComponent.h"
#include "Engine/World.h"

AASCharacter::AASCharacter()
{
    PrimaryActorTick.bCanEverTick = true;
    bReplicates = true;
    SetReplicateMovement(true);

    GetCharacterMovement()->MaxWalkSpeed = WalkSpeed;
    GetCharacterMovement()->bOrientRotationToMovement = false;
    bUseControllerRotationYaw = true;

    CameraBoom = CreateDefaultSubobject<USpringArmComponent>(TEXT("CameraBoom"));
    CameraBoom->SetupAttachment(RootComponent);
    CameraBoom->TargetArmLength = 360.f;
    CameraBoom->bUsePawnControlRotation = true;

    FollowCamera = CreateDefaultSubobject<UCameraComponent>(TEXT("FollowCamera"));
    FollowCamera->SetupAttachment(CameraBoom, USpringArmComponent::SocketName);
    FollowCamera->bUsePawnControlRotation = false;

    Health = CreateDefaultSubobject<UASHealthComponent>(TEXT("Health"));
    Weapon = CreateDefaultSubobject<UASWeaponComponent>(TEXT("Weapon"));
}

void AASCharacter::BeginPlay()
{
    Super::BeginPlay();
    GetCharacterMovement()->MaxWalkSpeed = WalkSpeed;
}

void AASCharacter::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    if (bFireHeld) FireOnce();
}

void AASCharacter::SetupPlayerInputComponent(UInputComponent* Input)
{
    Super::SetupPlayerInputComponent(Input);
    Input->BindAxis("MoveForward", this, &AASCharacter::MoveForward);
    Input->BindAxis("MoveRight", this, &AASCharacter::MoveRight);
    Input->BindAxis("Turn", this, &AASCharacter::Turn);
    Input->BindAxis("LookUp", this, &AASCharacter::LookUp);
    Input->BindAction("Jump", IE_Pressed, this, &ACharacter::Jump);
    Input->BindAction("Jump", IE_Released, this, &ACharacter::StopJumping);
    Input->BindAction("Sprint", IE_Pressed, this, &AASCharacter::SprintPressed);
    Input->BindAction("Sprint", IE_Released, this, &AASCharacter::SprintReleased);
    Input->BindAction("Fire", IE_Pressed, this, &AASCharacter::FirePressed);
    Input->BindAction("Fire", IE_Released, this, &AASCharacter::FireReleased);
    Input->BindAction("Dash", IE_Pressed, this, &AASCharacter::Dash);
}

void AASCharacter::MoveForward(float V) { if (Controller && V != 0.f) AddMovementInput(GetActorForwardVector(), V); }
void AASCharacter::MoveRight(float V) { if (Controller && V != 0.f) AddMovementInput(GetActorRightVector(), V); }
void AASCharacter::Turn(float V) { AddControllerYawInput(V); }
void AASCharacter::LookUp(float V) { AddControllerPitchInput(V); }
void AASCharacter::SprintPressed() { bSprintHeld = true; GetCharacterMovement()->MaxWalkSpeed = SprintSpeed; }
void AASCharacter::SprintReleased() { bSprintHeld = false; GetCharacterMovement()->MaxWalkSpeed = WalkSpeed; }
void AASCharacter::FirePressed() { bFireHeld = true; FireOnce(); }
void AASCharacter::FireReleased() { bFireHeld = false; }

void AASCharacter::Dash()
{
    if (!GetWorld()) return;
    const double Now = GetWorld()->GetTimeSeconds();
    if (Now - LastDashTime < DashCooldown) return;
    LastDashTime = Now;
    LaunchCharacter(GetActorForwardVector() * DashStrength + FVector(0,0,80.f), true, false);
}

void AASCharacter::FireOnce()
{
    if (!Weapon || !Controller) return;
    FVector ViewLoc; FRotator ViewRot;
    Controller->GetPlayerViewPoint(ViewLoc, ViewRot);
    Weapon->RequestFire(ViewLoc, ViewRot.Vector());
}
