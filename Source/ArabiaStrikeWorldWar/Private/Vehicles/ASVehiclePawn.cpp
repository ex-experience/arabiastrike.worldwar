#include "Vehicles/ASVehiclePawn.h"
#include "Combat/ASHealthComponent.h"
#include "GameFramework/PlayerState.h"
#include "Net/UnrealNetwork.h"
AASVehiclePawn::AASVehiclePawn()
{
    bReplicates = true;
    SetReplicateMovement(true);
    Health = CreateDefaultSubobject<UASHealthComponent>(TEXT("Health"));
}
bool AASVehiclePawn::ReserveSeat(APlayerState* PS, int32 SeatIndex)
{
    if (!HasAuthority() || !PS || SeatIndex < 0 || SeatIndex >= SeatCount) return false;
    if (Occupants.Num() != SeatCount) Occupants.SetNum(SeatCount);
    if (Occupants[SeatIndex] != nullptr) return false;
    Occupants[SeatIndex] = PS; return true;
}
void AASVehiclePawn::ReleaseSeatsFor(APlayerState* PS)
{
    if (!HasAuthority() || !PS) return;
    for (TObjectPtr<APlayerState>& Occupant : Occupants) if (Occupant == PS) Occupant = nullptr;
}
void AASVehiclePawn::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME(AASVehiclePawn, Occupants);
}
