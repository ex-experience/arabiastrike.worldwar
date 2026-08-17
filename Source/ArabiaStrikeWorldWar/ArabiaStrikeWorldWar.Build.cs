using UnrealBuildTool;
public class ArabiaStrikeWorldWar : ModuleRules
{
    public ArabiaStrikeWorldWar(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PublicDependencyModuleNames.AddRange(new string[]
        {
            "Core", "CoreUObject", "Engine", "InputCore", "EnhancedInput",
            "GameplayTags", "GameplayTasks", "AIModule", "NavigationSystem",
            "UMG", "Slate", "SlateCore", "NetCore", "PhysicsCore"
        });
        PrivateDependencyModuleNames.AddRange(new string[] { "Niagara" });
    }
}
