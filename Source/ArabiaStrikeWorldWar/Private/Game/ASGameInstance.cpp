#include "Game/ASGameInstance.h"
void UASGameInstance::Init()
{
    Super::Init();
#if UE_BUILD_SHIPPING
    OnlineBackendMode = TEXT("ConfiguredAtDeployment");
#else
    OnlineBackendMode = TEXT("Null");
#endif
}
