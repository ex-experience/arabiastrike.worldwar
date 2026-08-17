#include "Mission/ASObjectiveVolume.h"
#include "Mission/ASMissionDirector.h"
#include "Components/BoxComponent.h"
#include "GameFramework/Pawn.h"
AASObjectiveVolume::AASObjectiveVolume(){bReplicates=false;Volume=CreateDefaultSubobject<UBoxComponent>(TEXT("Volume"));RootComponent=Volume;Volume->SetBoxExtent(FVector(300));Volume->OnComponentBeginOverlap.AddDynamic(this,&AASObjectiveVolume::Enter);}
void AASObjectiveVolume::Enter(UPrimitiveComponent*,AActor*A,UPrimitiveComponent*,int32,bool,const FHitResult&){if(bUsed&&bOneShot)return;APawn*P=Cast<APawn>(A);if(!P||!P->IsPlayerControlled()||!Director||!Director->HasAuthority())return;bUsed=true;Director->AdvancePhase();}
