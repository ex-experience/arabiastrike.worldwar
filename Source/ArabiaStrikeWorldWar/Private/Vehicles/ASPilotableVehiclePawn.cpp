#include "Vehicles/ASPilotableVehiclePawn.h"
#include "Vehicles/ASVehicleTurretComponent.h"
#include "Vehicles/ASVehicleDamageModelComponent.h"
#include "Components/StaticMeshComponent.h"
#include "GameFramework/FloatingPawnMovement.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerState.h"
#include "Combat/ASHealthComponent.h"
AASPilotableVehiclePawn::AASPilotableVehiclePawn(){Body=CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Body"));RootComponent=Body;DriveMovement=CreateDefaultSubobject<UFloatingPawnMovement>(TEXT("DriveMovement"));DriveMovement->MaxSpeed=2200.f;Turret=CreateDefaultSubobject<UASVehicleTurretComponent>(TEXT("Turret"));DamageModel=CreateDefaultSubobject<UASVehicleDamageModelComponent>(TEXT("DamageModel"));}
void AASPilotableVehiclePawn::SetupPlayerInputComponent(UInputComponent*I){Super::SetupPlayerInputComponent(I);I->BindAxis("MoveForward",this,&AASPilotableVehiclePawn::Throttle);I->BindAxis("MoveRight",this,&AASPilotableVehiclePawn::Steer);I->BindAxis("Turn",this,&AASPilotableVehiclePawn::AimTurret);I->BindAction("Fire",IE_Pressed,this,&AASPilotableVehiclePawn::FireTurret);I->BindAction("Interact",IE_Pressed,this,&AASPilotableVehiclePawn::ExitVehicle);}
void AASPilotableVehiclePawn::Throttle(float V){if(DamageModel&&DamageModel->IsEngineDisabled())return;AddMovementInput(GetActorForwardVector(),V);}void AASPilotableVehiclePawn::Steer(float V){if(FMath::Abs(V)>.01f&&(!DamageModel||!DamageModel->IsEngineDisabled()))AddActorLocalRotation(FRotator(0,V*TurnRate*GetWorld()->GetDeltaSeconds(),0));}
void AASPilotableVehiclePawn::AimTurret(float){if(Turret&&Controller)Turret->RequestAim(Controller->GetControlRotation());}void AASPilotableVehiclePawn::FireTurret(){if(Turret&&Controller){Turret->RequestAim(Controller->GetControlRotation());Turret->RequestFire();}}
FText AASPilotableVehiclePawn::GetInteractionLabel_Implementation(APawn*)const{return FText::FromString(TEXT("DRIVE HUMMER"));}
bool AASPilotableVehiclePawn::Interact_Implementation(APawn*P){if(!HasAuthority()||!P)return false;APlayerController*PC=Cast<APlayerController>(P->GetController());if(!PC||!ReserveSeat(PC->PlayerState,0))return false;StoredDriverPawn=P;P->SetActorHiddenInGame(true);P->SetActorEnableCollision(false);P->SetActorTickEnabled(false);PC->Possess(this);return true;}
void AASPilotableVehiclePawn::ExitVehicle(){APlayerController*PC=Cast<APlayerController>(GetController());if(!PC)return;if(HasAuthority())ServerExit_Implementation(PC);else ServerExit(PC);}
void AASPilotableVehiclePawn::ServerExit_Implementation(APlayerController*PC){if(!PC||!PC->PlayerState||!StoredDriverPawn)return;ReleaseSeatsFor(PC->PlayerState);APawn*Driver=StoredDriverPawn;StoredDriverPawn=nullptr;Driver->SetActorLocation(GetActorLocation()+GetActorRightVector()*220.f+FVector(0,0,80));Driver->SetActorHiddenInGame(false);Driver->SetActorEnableCollision(true);Driver->SetActorTickEnabled(true);PC->Possess(Driver);}
