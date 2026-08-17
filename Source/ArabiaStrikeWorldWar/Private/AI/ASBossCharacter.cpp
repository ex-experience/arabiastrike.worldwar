#include "AI/ASBossCharacter.h"
#include "Combat/ASHealthComponent.h"
#include "Net/UnrealNetwork.h"
AASBossCharacter::AASBossCharacter()
{
    PrimaryActorTick.bCanEverTick = true;
    bReplicates = true;
    Health = CreateDefaultSubobject<UASHealthComponent>(TEXT("Health"));
}
void AASBossCharacter::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    if (!HasAuthority() || !Health) return;
    const float Ratio = Health->GetMaxHealth() > 0.f ? Health->GetHealth()/Health->GetMaxHealth() : 0.f;
    Phase = FMath::Clamp(1 + FMath::FloorToInt((1.f - Ratio) * MaxPhases), 1, MaxPhases);
}
void AASBossCharacter::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME(AASBossCharacter, Phase);
}
