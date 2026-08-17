#include "AI/ASSquadComponent.h"
#include "Net/UnrealNetwork.h"

UASSquadComponent::UASSquadComponent()
{
    SetIsReplicatedByDefault(true);
    PrimaryComponentTick.bCanEverTick = true;
    PrimaryComponentTick.TickInterval = 0.1f;
}

void UASSquadComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
    Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
    if (!GetOwner() || !GetOwner()->HasAuthority() || Suppression <= 0.f) return;
    const float Old = Suppression;
    Suppression = FMath::Max(0.f, Suppression - SuppressionDecayPerSecond * DeltaTime);
    if (Old >= 0.65f && Suppression < 0.65f && TacticalState == EASTacticalState::Suppressed)
        SetTacticalState(EASTacticalState::Hold);
}

void UASSquadComponent::AddSuppression(float Amount)
{
    if (!GetOwner() || !GetOwner()->HasAuthority() || Amount <= 0.f) return;
    Suppression = FMath::Clamp(Suppression + Amount, 0.f, 1.f);
    if (Suppression >= 0.65f) TacticalState = EASTacticalState::Suppressed;
    OnRep_Tactical();
}

void UASSquadComponent::SetTacticalState(EASTacticalState NewState)
{
    if (!GetOwner() || !GetOwner()->HasAuthority()) return;
    TacticalState = NewState;
    OnRep_Tactical();
}

void UASSquadComponent::OnRep_Tactical()
{
    OnTacticalStateChanged.Broadcast(TacticalState, Suppression);
}

void UASSquadComponent::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME(UASSquadComponent, SquadId);
    DOREPLIFETIME(UASSquadComponent, Role);
    DOREPLIFETIME(UASSquadComponent, TacticalState);
    DOREPLIFETIME(UASSquadComponent, Suppression);
}
