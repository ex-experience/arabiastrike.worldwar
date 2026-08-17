#include "Online/ASOnlineReadiness.h"
#include "Engine/Engine.h"
bool UASOnlineReadiness::IsDedicatedServerRuntime() { return IsRunningDedicatedServer(); }
FString UASOnlineReadiness::ArchitectureStatus()
{
    return TEXT("UE5.8 | Server-authoritative baseline | EOS gated | Pixel Streaming 2 gated");
}
