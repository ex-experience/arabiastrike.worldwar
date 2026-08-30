#include "World/ASCivilianCharacter.h"
#include "AIController.h"
#include "Animation/AnimInstance.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "NavigationSystem.h"
#include "Net/UnrealNetwork.h"
#include "TimerManager.h"
#include "UObject/ConstructorHelpers.h"
AASCivilianCharacter::AASCivilianCharacter()
{
    bReplicates=true;
    SetReplicateMovement(true);
    PrimaryActorTick.bCanEverTick = true;
    AutoPossessAI=EAutoPossessAI::PlacedInWorldOrSpawned;
    Tags.Add(TEXT("Civilian"));

    static ConstructorHelpers::FObjectFinder<USkeletalMesh> CivilianMesh(
        TEXT("/Game/Characters/Mannequins/Meshes/SKM_Quinn_Simple.SKM_Quinn_Simple"));
    static ConstructorHelpers::FClassFinder<UAnimInstance> CivilianAnim(
        TEXT("/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed"));
    if (USkeletalMeshComponent* Body = GetMesh())
    {
        if (CivilianMesh.Succeeded()) Body->SetSkeletalMeshAsset(CivilianMesh.Object);
        if (CivilianAnim.Succeeded()) Body->SetAnimInstanceClass(CivilianAnim.Class);
        Body->SetRelativeLocation(FVector(0.f, 0.f, -90.f));
        Body->SetRelativeRotation(FRotator(0.f, -90.f, 0.f));
        Body->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    }
}
void AASCivilianCharacter::BeginPlay(){ Super::BeginPlay(); HomeLocation=GetActorLocation(); if(HasAuthority()) GetWorldTimerManager().SetTimer(WanderTimer,this,&AASCivilianCharacter::ChooseNextDestination,RepathIntervalSeconds,true,0.5f); }
void AASCivilianCharacter::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    if (!HasAuthority() || FallbackDestination.IsNearlyZero()) return;
    FVector ToDestination = FallbackDestination - GetActorLocation();
    ToDestination.Z = 0.f;
    if (ToDestination.SizeSquared2D() <= FMath::Square(90.f))
    {
        FallbackDestination = FVector::ZeroVector;
        return;
    }
    const float Scale = Reaction == EASCivilianReaction::Flee || Reaction == EASCivilianReaction::Evacuate ? 1.f : .42f;
    AddMovementInput(ToDestination.GetSafeNormal(), Scale, true);
}
void AASCivilianCharacter::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const { Super::GetLifetimeReplicatedProps(OutLifetimeProps); DOREPLIFETIME(AASCivilianCharacter,Reaction); }
void AASCivilianCharacter::OnRep_Reaction(){ BP_OnReactionChanged(Reaction); }
void AASCivilianCharacter::NotifyThreat(FVector ThreatLocation,float Severity)
{
    if(!HasAuthority())return;
    LastThreatLocation=ThreatLocation;
    Reaction=Severity>=0.75f?EASCivilianReaction::Flee:Severity>=0.35f?EASCivilianReaction::Cower:EASCivilianReaction::Observe;
    OnRep_Reaction();
    if(Reaction==EASCivilianReaction::Flee)
    {
        const FVector Away=(GetActorLocation()-ThreatLocation).GetSafeNormal2D();
        FallbackDestination=GetActorLocation()+Away*PanicThreatDistance;
        if(AAIController* AI=Cast<AAIController>(GetController())) AI->MoveToLocation(FallbackDestination,100.f);
    }
}
void AASCivilianCharacter::BeginEvacuation(FVector EvacuationPoint)
{
    if(!HasAuthority())return;
    Reaction=EASCivilianReaction::Evacuate;
    FallbackDestination=EvacuationPoint;
    OnRep_Reaction();
    if(AAIController* AI=Cast<AAIController>(GetController())) AI->MoveToLocation(EvacuationPoint,100.f);
}
void AASCivilianCharacter::ReturnToRoutine()
{
    if(!HasAuthority())return;
    Reaction=EASCivilianReaction::Calm;
    LastThreatLocation=FVector::ZeroVector;
    FallbackDestination=FVector::ZeroVector;
    OnRep_Reaction();
    ChooseNextDestination();
}
void AASCivilianCharacter::ChooseNextDestination()
{
    if(!HasAuthority()||Reaction!=EASCivilianReaction::Calm)return;
    AAIController* AI=Cast<AAIController>(GetController());
    UNavigationSystemV1* Nav=FNavigationSystem::GetCurrent<UNavigationSystemV1>(GetWorld());
    FNavLocation Candidate;
    if(AI&&Nav&&Nav->GetRandomReachablePointInRadius(HomeLocation,WanderRadius,Candidate))
    {
        FallbackDestination=FVector::ZeroVector;
        AI->MoveToLocation(Candidate.Location,90.f,true,true,true,false,nullptr,true);
        return;
    }
    const FVector2D Offset=FMath::RandPointInCircle(WanderRadius);
    FallbackDestination=HomeLocation+FVector(Offset.X,Offset.Y,0.f);
}
