#include "Mission/ASHostageNPC.h"
#include "Mission/ASMissionDirector.h"
#include "Net/UnrealNetwork.h"
#include "GameFramework/CharacterMovementComponent.h"
AASHostageNPC::AASHostageNPC(){bReplicates=true;SetReplicateMovement(true);}
FText AASHostageNPC::GetInteractionLabel_Implementation(APawn*)const{return bRescued?FText::GetEmpty():FText::FromString(TEXT("RESCUE"));}
bool AASHostageNPC::Interact_Implementation(APawn*P){if(!HasAuthority()||bRescued||!P)return false;bRescued=true;OnRep_Rescued();if(MissionDirector)MissionDirector->ReportHostageRescued();return true;}
void AASHostageNPC::OnRep_Rescued(){if(bRescued){SetActorEnableCollision(false);GetCharacterMovement()->DisableMovement();}}
void AASHostageNPC::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>&Out)const{Super::GetLifetimeReplicatedProps(Out);DOREPLIFETIME(AASHostageNPC,bRescued);}
