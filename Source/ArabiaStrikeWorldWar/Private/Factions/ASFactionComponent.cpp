#include "Factions/ASFactionComponent.h"
#include "Net/UnrealNetwork.h"
UASFactionComponent::UASFactionComponent(){ SetIsReplicatedByDefault(true); }
void UASFactionComponent::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{ Super::GetLifetimeReplicatedProps(OutLifetimeProps); DOREPLIFETIME(UASFactionComponent,Faction); }
EASFactionAttitude UASFactionComponent::GetAttitudeTo(const UASFactionComponent* Other) const
{
    if(!Other) return EASFactionAttitude::Neutral;
    if(Faction==Other->Faction) return EASFactionAttitude::Friendly;
    if(Faction==EASFaction::Civilian || Other->Faction==EASFaction::Civilian) return EASFactionAttitude::Neutral;
    if(Faction==EASFaction::Neutral || Other->Faction==EASFaction::Neutral) return EASFactionAttitude::Neutral;
    return EASFactionAttitude::Hostile;
}
bool UASFactionComponent::IsHostileTo(const UASFactionComponent* Other) const { return GetAttitudeTo(Other)==EASFactionAttitude::Hostile; }
