#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASMissionDirector.generated.h"
UENUM(BlueprintType) enum class EASMissionPhase:uint8{Insertion,StreetCombat,Rescue,HummerAssault,CheckpointBreach,HelicopterPressure,CommandMech,Extraction,Complete};
DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FASMissionPhaseChanged,EASMissionPhase,OldPhase,EASMissionPhase,NewPhase);
UCLASS() class ARABIASTRIKEWORLDWAR_API AASMissionDirector:public AActor{GENERATED_BODY()public:AASMissionDirector();UPROPERTY(BlueprintAssignable)FASMissionPhaseChanged OnPhaseChanged;UFUNCTION(BlueprintCallable)void AdvancePhase();UFUNCTION(BlueprintPure)EASMissionPhase GetPhase()const{return Phase;}protected:UPROPERTY(ReplicatedUsing=OnRep_Phase)EASMissionPhase Phase=EASMissionPhase::Insertion;UFUNCTION()void OnRep_Phase(EASMissionPhase Old);virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>&)const override;};
