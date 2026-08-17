using UnrealBuildTool;
using System.Collections.Generic;

public class ArabiaStrikeWorldWarServerTarget : TargetRules
{
    public ArabiaStrikeWorldWarServerTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Server;
        ExtraModuleNames.Add("ArabiaStrikeWorldWar");
    }
}
