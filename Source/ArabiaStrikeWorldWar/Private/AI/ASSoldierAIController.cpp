#include "AI/ASSoldierAIController.h"
#include "Kismet/GameplayStatics.h"
#include "GameFramework/Character.h"
AASSoldierAIController::AASSoldierAIController(){PrimaryActorTick.bCanEverTick=true;}
void AASSoldierAIController::AcquireTarget(){Target=nullptr;float Best=AcquireRadius;TArray<AActor*>P;UGameplayStatics::GetAllActorsOfClass(this,ACharacter::StaticClass(),P);for(AActor*A:P){APawn*Pawn=Cast<APawn>(A);if(!Pawn||Pawn==GetPawn()||!Pawn->IsPlayerControlled())continue;float D=FVector::Dist(Pawn->GetActorLocation(),GetPawn()->GetActorLocation());if(D<Best){Best=D;Target=Pawn;}}}
void AASSoldierAIController::Tick(float D){Super::Tick(D);if(!HasAuthority()||!GetPawn())return;if(!Target.IsValid())AcquireTarget();if(!Target.IsValid())return;float Dist=FVector::Dist(Target->GetActorLocation(),GetPawn()->GetActorLocation());if(Dist>FireDistance)MoveToActor(Target.Get(),FireDistance*.7f);else StopMovement();SetFocus(Target.Get());}
