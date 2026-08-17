#pragma once
#include "CoreMinimal.h"
#include "ASCombatTypes.generated.h"

UENUM(BlueprintType)
enum class EASWeaponSlot : uint8 { Primary, Secondary, Heavy, Gadget };
UENUM(BlueprintType)
enum class EASFireMode : uint8 { Semi, Auto, Burst, Projectile };
UENUM(BlueprintType)
enum class EASDamageClass : uint8 { Ballistic, Explosive, Fire, EMP };

USTRUCT(BlueprintType)
struct FASAmmoState
{
    GENERATED_BODY()
    UPROPERTY(EditAnywhere, BlueprintReadWrite) int32 Magazine = 30;
    UPROPERTY(EditAnywhere, BlueprintReadWrite) int32 Reserve = 120;
};
