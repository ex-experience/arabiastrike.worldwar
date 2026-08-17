#pragma once
#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "Combat/ASCombatTypes.h"
#include "ASWeaponDefinition.generated.h"

class AASProjectile;
UCLASS(BlueprintType)
class ARABIASTRIKEWORLDWAR_API UASWeaponDefinition : public UPrimaryDataAsset
{
    GENERATED_BODY()
public:
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly) FName WeaponId = "RIFLE_01";
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly) FText DisplayName;
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly) EASWeaponSlot Slot = EASWeaponSlot::Primary;
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly) EASFireMode FireMode = EASFireMode::Auto;
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly) float Damage = 24.f;
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly) float Range = 20000.f;
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly) float RoundsPerMinute = 720.f;
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly) float SpreadDegrees = 0.6f;
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly) int32 MagazineSize = 30;
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly) float ReloadSeconds = 1.8f;
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly) TSubclassOf<AASProjectile> ProjectileClass;
};
