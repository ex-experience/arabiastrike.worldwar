using UnrealBuildTool;
using System.Collections.Generic;

public class ArabiaStrikeWorldWarTarget : TargetRules
{
    public ArabiaStrikeWorldWarTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;
        ExtraModuleNames.Add("ArabiaStrikeWorldWar");
    }
}
