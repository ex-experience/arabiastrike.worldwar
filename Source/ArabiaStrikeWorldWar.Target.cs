using UnrealBuildTool;
using System.Collections.Generic;

public class ArabiaStrikeWorldWarTarget : TargetRules
{
    public ArabiaStrikeWorldWarTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;
        DefaultBuildSettings = BuildSettingsVersion.V7;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_8;
        ExtraModuleNames.Add("ArabiaStrikeWorldWar");
    }
}