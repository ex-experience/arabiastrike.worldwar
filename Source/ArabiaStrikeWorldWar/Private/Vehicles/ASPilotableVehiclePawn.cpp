#include "Vehicles/ASPilotableVehiclePawn.h"
#include "Vehicles/ASVehicleTurretComponent.h"
#include "Vehicles/ASVehicleDamageModelComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Camera/CameraComponent.h"
#include "Engine/StaticMesh.h"
#include "GameFramework/FloatingPawnMovement.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerState.h"
#include "GameFramework/SpringArmComponent.h"
#include "Combat/ASHealthComponent.h"
#include "UObject/ConstructorHelpers.h"
AASPilotableVehiclePawn::AASPilotableVehiclePawn()
{
    Body=CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Body"));
    RootComponent=Body;
    Body->SetCollisionProfileName(TEXT("Pawn"));
    Body->SetSimulatePhysics(false);
    static ConstructorHelpers::FObjectFinder<UStaticMesh> SportsCar(TEXT("/Game/Vehicles/SportsCar/SM_SportsCar.SM_SportsCar"));
    if(SportsCar.Succeeded())Body->SetStaticMesh(SportsCar.Object);
    else
    {
        Body->SetRelativeScale3D(FVector(2.8f,1.25f,.72f));
        static ConstructorHelpers::FObjectFinder<UStaticMesh> TacticalBody(TEXT("/Engine/BasicShapes/Cube.Cube"));
        if(TacticalBody.Succeeded())Body->SetStaticMesh(TacticalBody.Object);
    }

    CameraBoom=CreateDefaultSubobject<USpringArmComponent>(TEXT("CameraBoom"));
    CameraBoom->SetupAttachment(Body);
    CameraBoom->TargetArmLength=620.f;
    CameraBoom->SetRelativeLocation(FVector(0.f,0.f,145.f));
    CameraBoom->bUsePawnControlRotation=true;
    CameraBoom->bEnableCameraLag=true;
    CameraBoom->CameraLagSpeed=8.f;
    DriveCamera=CreateDefaultSubobject<UCameraComponent>(TEXT("DriveCamera"));
    DriveCamera->SetupAttachment(CameraBoom,USpringArmComponent::SocketName);

    DriveMovement=CreateDefaultSubobject<UFloatingPawnMovement>(TEXT("DriveMovement"));
    DriveMovement->MaxSpeed=2200.f;
    DriveMovement->Acceleration=4800.f;
    DriveMovement->Deceleration=6200.f;
    DriveMovement->SetUpdatedComponent(Body);
    Turret=CreateDefaultSubobject<UASVehicleTurretComponent>(TEXT("Turret"));
    DamageModel=CreateDefaultSubobject<UASVehicleDamageModelComponent>(TEXT("DamageModel"));
    Tags.Add(TEXT("Vehicle"));
    Tags.Add(TEXT("Tactical4x4"));
}
void AASPilotableVehiclePawn::SetupPlayerInputComponent(UInputComponent*I)
{
    Super::SetupPlayerInputComponent(I);
    I->BindAxis("MoveForward",this,&AASPilotableVehiclePawn::Throttle);
    I->BindAxis("MoveRight",this,&AASPilotableVehiclePawn::Steer);
    I->BindAxis("Turn",this,&AASPilotableVehiclePawn::AimTurret);
    I->BindAction("Fire",IE_Pressed,this,&AASPilotableVehiclePawn::FireTurret);
    I->BindAction("Interact",IE_Pressed,this,&AASPilotableVehiclePawn::ExitVehicle);
    I->BindAction("VehicleInteract",IE_Pressed,this,&AASPilotableVehiclePawn::ExitVehicle);
}
void AASPilotableVehiclePawn::Throttle(float V){if(DamageModel&&DamageModel->IsEngineDisabled())return;AddMovementInput(GetActorForwardVector(),V);}void AASPilotableVehiclePawn::Steer(float V){if(FMath::Abs(V)>.01f&&(!DamageModel||!DamageModel->IsEngineDisabled()))AddActorLocalRotation(FRotator(0,V*TurnRate*GetWorld()->GetDeltaSeconds(),0));}
void AASPilotableVehiclePawn::AimTurret(float){if(Turret&&Controller)Turret->RequestAim(Controller->GetControlRotation());}void AASPilotableVehiclePawn::FireTurret(){if(Turret&&Controller){Turret->RequestAim(Controller->GetControlRotation());Turret->RequestFire();}}
FText AASPilotableVehiclePawn::GetInteractionLabel_Implementation(APawn*)const{return FText::FromString(TEXT("DRIVE SPORTS CAR"));}
bool AASPilotableVehiclePawn::Interact_Implementation(APawn*P){if(!HasAuthority()||!P)return false;APlayerController*PC=Cast<APlayerController>(P->GetController());if(!PC||!ReserveSeat(PC->PlayerState,0))return false;StoredDriverPawn=P;P->SetActorHiddenInGame(true);P->SetActorEnableCollision(false);P->SetActorTickEnabled(false);PC->Possess(this);return true;}
void AASPilotableVehiclePawn::ExitVehicle(){APlayerController*PC=Cast<APlayerController>(GetController());if(!PC)return;if(HasAuthority())ServerExit_Implementation(PC);else ServerExit(PC);}
void AASPilotableVehiclePawn::ServerExit_Implementation(APlayerController*PC){if(!PC||!PC->PlayerState||!StoredDriverPawn)return;ReleaseSeatsFor(PC->PlayerState);APawn*Driver=StoredDriverPawn;StoredDriverPawn=nullptr;Driver->SetActorLocation(GetActorLocation()+GetActorRightVector()*220.f+FVector(0,0,80));Driver->SetActorHiddenInGame(false);Driver->SetActorEnableCollision(true);Driver->SetActorTickEnabled(true);PC->Possess(Driver);}
