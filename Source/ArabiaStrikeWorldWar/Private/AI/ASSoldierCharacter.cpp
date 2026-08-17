#include "AI/ASSoldierCharacter.h"
#include "AI/ASSoldierAIController.h"
#include "Combat/ASHealthComponent.h"
#include "Combat/ASWeaponComponent.h"
AASSoldierCharacter::AASSoldierCharacter(){PrimaryActorTick.bCanEverTick=true;bReplicates=true;Health=CreateDefaultSubobject<UASHealthComponent>(TEXT("Health"));Weapon=CreateDefaultSubobject<UASWeaponComponent>(TEXT("Weapon"));AIControllerClass=AASSoldierAIController::StaticClass();AutoPossessAI=EAutoPossessAI::PlacedInWorldOrSpawned;}
void AASSoldierCharacter::Tick(float D){Super::Tick(D);if(!HasAuthority()||!GetController()||!Weapon)return;FVector Loc;FRotator Rot;GetController()->GetPlayerViewPoint(Loc,Rot);if(GetWorld()->GetTimeSeconds()>=NextShot){NextShot=GetWorld()->GetTimeSeconds()+0.14;Weapon->RequestFire(Loc,Rot.Vector());}}
