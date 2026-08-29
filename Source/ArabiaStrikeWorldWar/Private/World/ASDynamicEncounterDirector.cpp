#include "World/ASDynamicEncounterDirector.h"
#include "Game/ASGameState.h"
#include "Player/ASPlayerState.h"
#include "GameFramework/PlayerController.h"
#include "Engine/World.h"
#include "TimerManager.h"

AASDynamicEncounterDirector::AASDynamicEncounterDirector()
{
    PrimaryActorTick.bCanEverTick = false;
}

void AASDynamicEncounterDirector::BeginPlay()
{
    Super::BeginPlay();
    if (HasAuthority()) GetWorldTimerManager().SetTimer(EvaluateTimer, this, &AASDynamicEncounterDirector::EvaluateEncounterTimer, EvaluationIntervalSeconds, true, 5.0f);
}

const FASDynamicEncounterSpec* AASDynamicEncounterDirector::ChooseEncounter(EASCityDistrict District, int32 Threat) const
{
    float TotalWeight = 0.0f;
    for (const FASDynamicEncounterSpec& Spec : EncounterTable)
    {
        if (Spec.District == District && Spec.MinimumThreatLevel <= Threat && Spec.EncounterActorClass && Spec.Weight > 0.0f) TotalWeight += Spec.Weight;
    }
    if (TotalWeight <= 0.0f) return nullptr;

    float Pick = FMath::FRandRange(0.0f, TotalWeight);
    for (const FASDynamicEncounterSpec& Spec : EncounterTable)
    {
        if (Spec.District != District || Spec.MinimumThreatLevel > Threat || !Spec.EncounterActorClass || Spec.Weight <= 0.0f) continue;
        Pick -= Spec.Weight;
        if (Pick <= 0.0f) return &Spec;
    }
    return nullptr;
}

void AASDynamicEncounterDirector::EvaluateEncounterTimer()
{
    TryStartEncounter();
}
bool AASDynamicEncounterDirector::TryStartEncounter()
{
    if (!HasAuthority()) return false;
    ActiveEncounters.RemoveAll([](const TWeakObjectPtr<AActor>& A){ return !A.IsValid(); });
    if (ActiveEncounters.Num() >= MaxConcurrentEncounters) return false;

    UWorld* World = GetWorld();
    AASGameState* GS = World ? World->GetGameState<AASGameState>() : nullptr;
    if (!World || !GS) return false;

    TArray<APlayerController*> Candidates;
    for (FConstPlayerControllerIterator It = World->GetPlayerControllerIterator(); It; ++It)
    {
        if (APlayerController* PC = It->Get()) if (PC->GetPawn()) Candidates.Add(PC);
    }
    if (Candidates.IsEmpty()) return false;

    APlayerController* TargetPC = Candidates[FMath::RandRange(0, Candidates.Num()-1)];
    AASPlayerState* PS = TargetPC ? TargetPC->GetPlayerState<AASPlayerState>() : nullptr;
    if (!TargetPC || !PS || !TargetPC->GetPawn()) return false;

    const FASDynamicEncounterSpec* Spec = ChooseEncounter(PS->CurrentDistrict, GS->WorldThreatLevel);
    if (!Spec) return false;

    const FVector2D Direction2D = FMath::RandPointInCircle(1.0f).GetSafeNormal();
    const FVector SpawnLocation = TargetPC->GetPawn()->GetActorLocation() + FVector(Direction2D.X, Direction2D.Y, 0.0f) * SpawnDistanceFromPlayer;
    FActorSpawnParameters Params;
    Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn;
    if (AActor* Encounter = World->SpawnActor<AActor>(Spec->EncounterActorClass, SpawnLocation, FRotator::ZeroRotator, Params))
    {
        ActiveEncounters.Add(Encounter);
        GS->ActiveWorldEvent = Spec->WorldEvent;
        GS->ForceNetUpdate();
        return true;
    }
    return false;
}
