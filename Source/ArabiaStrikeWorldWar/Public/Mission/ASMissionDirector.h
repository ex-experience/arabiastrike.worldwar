#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ASMissionDirector.generated.h"
UENUM(BlueprintType) enum class EASMissionPhase:uint8{Insertion,StreetCombat,Rescue,HummerAssault,CheckpointBreach,HelicopterPressure,CommandMech,Extraction,Complete};
DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FASMissionPhaseChanged,EASMissionPhase,OldPhase,EASMissionPhase,NewPhase);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FASRescueProgressChanged,int32,Rescued,int32,Required);
UCLASS()
class ARABIASTRIKEWORLDWAR_API AASMissionDirector:public AActor
{
    GENERATED_BODY()
public:
    AASMissionDirector();
    UPROPERTY(BlueprintAssignable)FASMissionPhaseChanged OnPhaseChanged;
    UPROPERTY(BlueprintAssignable)FASRescueProgressChanged OnRescueProgressChanged;
    UFUNCTION(BlueprintCallable,BlueprintAuthorityOnly)void AdvancePhase();
    UFUNCTION(BlueprintCallable,BlueprintAuthorityOnly)void ReportHostageRescued();
    UFUNCTION(BlueprintPure)EASMissionPhase GetPhase()const{return Phase;}
    UFUNCTION(BlueprintPure)int32 GetRescuedHostages()const{return RescuedHostages;}
    UFUNCTION(BlueprintPure)int32 GetRequiredHostages()const{return RequiredHostages;}
protected:
    UPROPERTY(ReplicatedUsing=OnRep_Phase)EASMissionPhase Phase=EASMissionPhase::Insertion;
    UPROPERTY(EditAnywhere,ReplicatedUsing=OnRep_RescueProgress)int32 RequiredHostages=1;
    UPROPERTY(ReplicatedUsing=OnRep_RescueProgress)int32 RescuedHostages=0;
    UFUNCTION()void OnRep_Phase(EASMissionPhase Old);
    UFUNCTION()void OnRep_RescueProgress();
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>&)const override;
};
