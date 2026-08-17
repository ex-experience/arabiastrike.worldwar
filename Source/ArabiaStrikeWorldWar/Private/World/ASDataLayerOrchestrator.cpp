#include "World/ASDataLayerOrchestrator.h"
AASDataLayerOrchestrator::AASDataLayerOrchestrator(){ PrimaryActorTick.bCanEverTick=false; }
void AASDataLayerOrchestrator::BeginPlay(){ Super::BeginPlay(); ApplyStartupLayers(); }
void AASDataLayerOrchestrator::ApplyLayerIntent(FName DataLayerName,EASDataLayerIntent Intent){ if(DataLayerName.IsNone()) return; BP_ApplyRuntimeDataLayerState(DataLayerName,Intent); }
void AASDataLayerOrchestrator::ApplyStartupLayers(){ for(const FASDataLayerRequest& Request:StartupLayers) ApplyLayerIntent(Request.DataLayerName,Request.Intent); }
