#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Pawn.h"
#include "ASVehiclePawn.generated.h"
class UASHealthComponent;

UCLASS(Abstract)
class ARABIASTRIKEWORLDWAR_API AASVehiclePawn : public APawn
{
    GENERATED_BODY()
public:
    AASVehiclePawn();
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly) bool ReserveSeat(APlayerState* PlayerState, int32 SeatIndex);
    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly) void ReleaseSeatsFor(APlayerState* PlayerState);

protected:
    UPROPERTY(VisibleAnywhere, BlueprintReadOnly) TObjectPtr<UASHealthComponent> Health;
    UPROPERTY(EditDefaultsOnly, Category="Seats") int32 SeatCount = 4;
    UPROPERTY(Replicated) TArray<TObjectPtr<APlayerState>> Occupants;
};
