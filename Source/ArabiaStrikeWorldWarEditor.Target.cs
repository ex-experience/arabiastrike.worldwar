using UnrealBuildTool;
using System.Collections.Generic;

public class ArabiaStrikeWorldWarEditorTarget : TargetRules
{
    public ArabiaStrikeWorldWarEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        ExtraModuleNames.Add("ArabiaStrikeWorldWar");
    }
}
