#include "World/ASPCGWorldHook.h"
#include "PCGComponent.h"

AASPCGWorldHook::AASPCGWorldHook()
{
    PrimaryActorTick.bCanEverTick = false;
    PCGComponent = CreateDefaultSubobject<UPCGComponent>(TEXT("PCGWorldComponent"));
}

void AASPCGWorldHook::GenerateWorldPatch(bool bForce)
{
    if (PCGComponent) PCGComponent->Generate(bForce);
}
