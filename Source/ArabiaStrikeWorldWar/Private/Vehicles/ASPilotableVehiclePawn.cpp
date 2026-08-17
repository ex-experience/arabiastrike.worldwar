#include "Vehicles/ASPilotableVehiclePawn.h"
#include "Components/StaticMeshComponent.h"
#include "GameFramework/FloatingPawnMovement.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerState.h"
AASPilotableVehiclePawn::AASPilotableVehiclePawn(){Body=CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Body"));Body->SetupAttachment(RootComponent);DriveMovement=CreateDefaultSubobject<UFloatingPawnMovement>(TEXT("DriveMovement"));DriveMovement->MaxSpeed=2200.f;}
void AASPilotableVehiclePawn::SetupPlayerInputComponent(UInputComponent*I){Super::SetupPlayerInputComponent(I);I->BindAxis("MoveForward",this,&AASPilotableVehiclePawn::Throttle);I->BindAxis("MoveRight",this,&AASPilotableVehiclePawn::Steer);I->BindAction("Interact",IE_Pressed,this,&AASPilotableVehiclePawn::ExitVehicle);}
void AASPilotableVehiclePawn::Throttle(float V){AddMovementInput(GetActorForwardVector(),V);} void AASPilotableVehiclePawn::Steer(float V){if(FMath::Abs(V)>.01f)AddActorLocalRotation(FRotator(0,V*TurnRate*GetWorld()->GetDeltaSeconds(),0));}
FText AASPilotableVehiclePawn::GetInteractionLabel_Implementation(APawn*)const{return FText::FromString(TEXT("DRIVE"));}
bool AASPilotableVehiclePawn::Interact_Implementation(APawn*P){if(!P)return false;if(HasAuthority())ServerEnter_Implementation(P);else ServerEnter(P);return true;}
void AASPilotableVehiclePawn::ServerEnter_Implementation(APawn*P){APlayerController*PC=Cast<APlayerController>(P->GetController());if(!PC||!ReserveSeat(PC->PlayerState,0))return;P->SetActorHiddenInGame(true);P->SetActorEnableCollision(false);PC->Possess(this);}
void AASPilotableVehiclePawn::ExitVehicle(){APlayerController*PC=Cast<APlayerController>(GetController());if(!PC)return;if(HasAuthority())ServerExit_Implementation(PC);else ServerExit(PC);}
void AASPilotableVehiclePawn::ServerExit_Implementation(APlayerController*PC){if(!PC||!PC->PlayerState)return;ReleaseSeatsFor(PC->PlayerState);/* GameMode/seat system owns character respawn/re-possession hook. */}
