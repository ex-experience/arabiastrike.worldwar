#include "World/ASDestructibleStateActor.h"
#include "Net/UnrealNetwork.h"
AASDestructibleStateActor::AASDestructibleStateActor(){ bReplicates=true; SetReplicateMovement(true); }
void AASDestructibleStateActor::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const { Super::GetLifetimeReplicatedProps(OutLifetimeProps); DOREPLIFETIME(AASDestructibleStateActor,StructuralHealth); DOREPLIFETIME(AASDestructibleStateActor,DestructionState); }
void AASDestructibleStateActor::ApplyStructuralDamage(float DamageAmount){ if(!HasAuthority()||DamageAmount<=0.f||DestructionState==EASDestructionState::Destroyed)return; StructuralHealth=FMath::Clamp(StructuralHealth-DamageAmount,0.f,MaxStructuralHealth); AuthorityUpdateState(); OnRep_StructuralState(); }
void AASDestructibleStateActor::AuthorityUpdateState(){ const float R=MaxStructuralHealth>0?StructuralHealth/MaxStructuralHealth:0.f; DestructionState=R<=0.f?EASDestructionState::Destroyed:R<0.25f?EASDestructionState::Critical:R<0.65f?EASDestructionState::Damaged:EASDestructionState::Intact; }
void AASDestructibleStateActor::OnRep_StructuralState(){ BP_ApplyDestructionPresentation(DestructionState,MaxStructuralHealth>0?StructuralHealth/MaxStructuralHealth:0.f); }
