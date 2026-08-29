[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "DEEP_DUPLICATE_COMPARE=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_MAP_CHANGES_WERE_MADE" -ForegroundColor Green
    Write-Host "DO_NOT_DELETE_ANY_ACTOR_YET" -ForegroundColor Yellow
    Write-Host "DO_NOT_PACKAGE_YET" -ForegroundColor Yellow
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

Set-Location $ProjectRoot
$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$MapFile = Join-Path $ProjectRoot "Content\Maps\Jeddah_RedSea_Assault.umap"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\JeddahMap"

foreach ($Required in @($ProjectFile,$MapFile,$EditorCmd)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_$Required" 11
    }
}

$RunningEditors = @(Get-Process UnrealEditor,UnrealEditor-Cmd -ErrorAction SilentlyContinue)
if ($RunningEditors.Count -gt 0) {
    $RunningEditors | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ALL_UNREAL_EDITOR_PROCESSES_FIRST" 12
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Py = Join-Path $EvidenceRoot "deep_compare_duplicates_$Stamp.py"
$Log = Join-Path $EvidenceRoot "deep_compare_duplicates_$Stamp.log"

$Python = @'
import unreal
from collections import defaultdict

MAP = "/Game/Maps/Jeddah_RedSea_Assault"

DUPLICATE_LABELS = {
    "ASWW_CommandMech_Encounter",
    "ASWW_Extraction_Prototype",
    "ASWW_Ground",
    "ASWW_Helicopter_Encounter",
    "ASWW_Hummer_Test",
    "ASWW_MissionDirector",
    "ASWW_SpawnApron",
    "ASWW_WorldBootstrap",
}

def require(v, msg):
    if not v:
        raise RuntimeError(msg)

def safe_prop(obj, name):
    try:
        return obj.get_editor_property(name)
    except Exception:
        return "<unavailable>"

def vec(v):
    try:
        return (round(float(v.x),3), round(float(v.y),3), round(float(v.z),3))
    except Exception:
        return str(v)

def rot(r):
    try:
        return (round(float(r.pitch),3), round(float(r.yaw),3), round(float(r.roll),3))
    except Exception:
        return str(r)

def component_signature(actor):
    out = []
    try:
        comps = actor.get_components_by_class(unreal.ActorComponent)
    except Exception:
        comps = []
    for c in comps:
        item = {
            "class": c.get_class().get_name(),
            "name": c.get_name(),
            "auto_activate": str(safe_prop(c, "auto_activate")),
            "replicates": str(safe_prop(c, "replicates")),
        }
        try:
            if isinstance(c, unreal.SceneComponent):
                item["rel_loc"] = vec(safe_prop(c, "relative_location"))
                item["rel_rot"] = rot(safe_prop(c, "relative_rotation"))
                item["rel_scale"] = vec(safe_prop(c, "relative_scale3d"))
        except Exception:
            pass
        out.append(item)
    out.sort(key=lambda x: (str(x.get("class")), str(x.get("name"))))
    return out

def actor_signature(actor):
    return {
        "class": actor.get_class().get_name(),
        "location": vec(actor.get_actor_location()),
        "rotation": rot(actor.get_actor_rotation()),
        "scale": vec(actor.get_actor_scale3d()),
        "tags": str(safe_prop(actor, "tags")),
        "folder_path": str(safe_prop(actor, "folder_path")),
        "editor_only": str(safe_prop(actor, "is_editor_only_actor")),
        "spatial": str(safe_prop(actor, "is_spatially_loaded")),
        "components": component_signature(actor),
    }

def compare_dicts(a, b):
    diffs = []
    for key in sorted(set(a.keys()) | set(b.keys())):
        av = a.get(key, "<missing>")
        bv = b.get(key, "<missing>")
        if av != bv:
            diffs.append((key, av, bv))
    return diffs

def main():
    level_subsystem = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    actor_subsystem = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

    require(level_subsystem.load_level(MAP), "Failed to load Jeddah")

    descs = list(unreal.WorldPartitionBlueprintLibrary.get_actor_descs())
    by_label = defaultdict(list)
    for d in descs:
        label = str(d.label)
        if label in DUPLICATE_LABELS:
            by_label[label].append(d)

    for label in sorted(DUPLICATE_LABELS):
        items = by_label.get(label, [])
        unreal.log(f"ASWW_DEEP_COUNT={label}|count={len(items)}")
        require(len(items) == 2, f"{label} no longer has exactly 2 descriptors")

    guids = [d.guid for items in by_label.values() for d in items]
    unreal.WorldPartitionBlueprintLibrary.load_actors(guids)

    actors_by_label = defaultdict(list)
    for actor in actor_subsystem.get_all_level_actors():
        label = actor.get_actor_label()
        if label in DUPLICATE_LABELS:
            actors_by_label[label].append(actor)

    all_equivalent = True

    for label in sorted(DUPLICATE_LABELS):
        actors = actors_by_label[label]
        require(len(actors) == 2, f"{label} did not load exactly 2 actors")

        actors.sort(key=lambda a: a.get_path_name())
        a, b = actors
        sa = actor_signature(a)
        sb = actor_signature(b)

        unreal.log(f"ASWW_DEEP_PAIR={label}")
        unreal.log(f"ASWW_DEEP_A={a.get_path_name()}")
        unreal.log(f"ASWW_DEEP_B={b.get_path_name()}")

        diffs = compare_dicts(sa, sb)
        if diffs:
            all_equivalent = False
            unreal.log(f"ASWW_DEEP_EQUIVALENT={label}|False")
            for key, av, bv in diffs:
                unreal.log(f"ASWW_DEEP_DIFF={label}|field={key}|A={av}|B={bv}")
        else:
            unreal.log(f"ASWW_DEEP_EQUIVALENT={label}|True")

    unreal.log(f"ASWW_DEEP_ALL_EQUIVALENT={all_equivalent}")
    unreal.log("ASWW_DEEP_DUPLICATE_COMPARE=PASS")

if __name__ == "__main__":
    main()
'@

[IO.File]::WriteAllText($Py, $Python, [Text.UTF8Encoding]::new($false))

$ProjectForUE = $ProjectFile.Replace('\','/')
$PyForUE = $Py.Replace('\','/')

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " DEEP DUPLICATE EQUIVALENCE AUDIT — READ ONLY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "AUDIT_LOG=$Log"

$Args = @(
    $ProjectForUE,
    "-ExecutePythonScript=$PyForUE",
    "-Unattended",
    "-NoSplash",
    "-NoSound",
    "-NullRHI",
    "-NoSourceControl",
    "-stdout",
    "-FullStdOutLogOutput"
)

& $EditorCmd @Args 2>&1 | Tee-Object -FilePath $Log | Out-Null
$Exit = $LASTEXITCODE

Write-Host "EDITOR_EXIT_CODE=$Exit"

Write-Host ""
Write-Host "=== DEEP DUPLICATE SUMMARY ===" -ForegroundColor Yellow
Select-String -LiteralPath $Log `
    -Pattern "ASWW_DEEP_COUNT=|ASWW_DEEP_EQUIVALENT=|ASWW_DEEP_ALL_EQUIVALENT=|ASWW_DEEP_DUPLICATE_COMPARE=" |
    Select-Object -First 160

Write-Host ""
Write-Host "=== DEEP DIFFERENCES ===" -ForegroundColor Yellow
Select-String -LiteralPath $Log -Pattern "ASWW_DEEP_DIFF=" | Select-Object -First 200

if ($Exit -ne 0) {
    Stop-Gate "EDITOR_AUDIT_EXIT_$Exit" $Exit
}

$Text = Get-Content -Raw -LiteralPath $Log
if ($Text -notmatch "ASWW_DEEP_DUPLICATE_COMPARE=PASS") {
    Stop-Gate "DEEP_AUDIT_MARKER_MISSING" 20
}

Write-Host ""
Write-Host "DEEP_DUPLICATE_COMPARE=PASS" -ForegroundColor Green

if ($Text -match "ASWW_DEEP_ALL_EQUIVALENT=True") {
    Write-Host "CLASSIFICATION=EXACT_DUPLICATES_ON_AUDITED_RUNTIME_RELEVANT_FIELDS" -ForegroundColor Green
    Write-Host "NEXT_GATE=SAFE_SINGLE_COPY_CLEANUP_WITH_BACKUP_THEN_PIE" -ForegroundColor Green
} else {
    Write-Host "CLASSIFICATION=NONIDENTICAL_DUPLICATES_REQUIRE_MANUAL_REVIEW" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=REVIEW_DEEP_DIFFERENCES_BEFORE_ANY_DELETE" -ForegroundColor Yellow
}

Write-Host "NO_MAP_CHANGES_WERE_MADE" -ForegroundColor Green
Write-Host "DO_NOT_DELETE_ANY_ACTOR_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_PACKAGE_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
