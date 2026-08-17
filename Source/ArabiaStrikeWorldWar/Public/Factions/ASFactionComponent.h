#pragma once
#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "Factions/ASFactionTypes.h"
#include "ASFactionComponent.generated.h"

UCLASS(ClassGroup=(ASWW), meta=(BlueprintSpawnableComponent))
class ARABIASTRIKEWORLDWAR_API UASFactionComponent : public UActorComponent
{
    GENERATED_BODY()
public:
    UASFactionComponent();
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
    UPROPERTY(EditAnywhere, Replicated, BlueprintReadOnly, Category="Faction") EASFaction Faction = EASFaction::Neutral;
    UFUNCTION(BlueprintPure, Category="Faction") EASFactionAttitude GetAttitudeTo(const UASFactionComponent* Other) const;
    UFUNCTION(BlueprintPure, Category="Faction") bool IsHostileTo(const UASFactionComponent* Other) const;
};
