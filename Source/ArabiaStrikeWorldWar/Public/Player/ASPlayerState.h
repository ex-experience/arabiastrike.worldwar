#pragma once
#include "CoreMinimal.h"
#include "GameFramework/PlayerState.h"
#include "World/ASWorldTypes.h"
#include "ASPlayerState.generated.h"

UCLASS()
class ARABIASTRIKEWORLDWAR_API AASPlayerState : public APlayerState
{
    GENERATED_BODY()
public:
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

    UPROPERTY(Replicated, BlueprintReadOnly) int32 SquadId = 0;
    UPROPERTY(Replicated, BlueprintReadOnly) int32 TeamId = 0;
    UPROPERTY(Replicated, BlueprintReadOnly) int32 Kills = 0;
    UPROPERTY(Replicated, BlueprintReadOnly) int32 Deaths = 0;
    UPROPERTY(Replicated, BlueprintReadOnly) int32 XP = 0;
    UPROPERTY(Replicated, BlueprintReadOnly, Category="World") EASCityDistrict CurrentDistrict = EASCityDistrict::Corniche;
    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly, Category="World") void SetCurrentDistrict(EASCityDistrict NewDistrict) { CurrentDistrict = NewDistrict; ForceNetUpdate(); }
};
