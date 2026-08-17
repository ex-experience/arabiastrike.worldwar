#include "Vehicles/ASBoatPawn.h"
#include "Net/UnrealNetwork.h"
AASBoatPawn::AASBoatPawn(){ bReplicates=true; SetReplicateMovement(true); PrimaryActorTick.bCanEverTick=true; }
void AASBoatPawn::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const { Super::GetLifetimeReplicatedProps(OutLifetimeProps); DOREPLIFETIME(AASBoatPawn,RepThrottle); DOREPLIFETIME(AASBoatPawn,RepSteering); }
void AASBoatPawn::ServerSetBoatInput_Implementation(float Throttle,float Steering){ RepThrottle=FMath::Clamp(Throttle,-1.f,1.f); RepSteering=FMath::Clamp(Steering,-1.f,1.f); }
void AASBoatPawn::Tick(float DeltaSeconds){ Super::Tick(DeltaSeconds); if(!HasAuthority()) return; AddActorWorldRotation(FRotator(0.f,RepSteering*TurnRateDegreesPerSecond*DeltaSeconds,0.f)); AddActorWorldOffset(GetActorForwardVector()*RepThrottle*MaxSpeedCmPerSecond*DeltaSeconds,true); }
