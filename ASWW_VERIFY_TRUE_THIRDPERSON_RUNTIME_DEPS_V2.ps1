[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\ThirdPersonRuntimeDepsV2"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "THIRDPERSON_RUNTIME_DEPS_V2=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

Set-Location $ProjectRoot
$env:GIT_PAGER = "cat"

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
if (-not (Test-Path -LiteralPath $EditorCmd -PathType Leaf)) {
    Stop-Gate "UNREALEDITOR_CMD_NOT_FOUND" 11
}

$TemplateRoot = Join-Path $UERoot "Templates"
$Projects = @(
    Get-ChildItem -LiteralPath $TemplateRoot -File -Recurse -Filter "*.uproject" -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FullName -match '(?i)ThirdPerson' -and
        $_.FullName -notmatch '(?i)FirstPerson'
    } |
    Sort-Object FullName -Unique
)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TRUE THIRD PERSON TEMPLATE CANDIDATES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TRUE_THIRDPERSON_TEMPLATE_COUNT=$($Projects.Count)"
foreach ($Proj in $Projects) {
    Write-Host "TRUE_THIRDPERSON_TEMPLATE=$($Proj.FullName)"
}

if ($Projects.Count -eq 0) {
    Stop-Gate "NO_TRUE_THIRDPERSON_TEMPLATE_PROJECT_FOUND" 12
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$SessionRoot = Join-Path $EvidenceRoot $Stamp
New-Item -ItemType Directory -Force -Path $SessionRoot | Out-Null

$ProbePy = Join-Path $SessionRoot "probe_true_thirdperson.py"

$ProbePython = @'
import unreal, json, os

out_path = os.environ.get("ASWW_TP_OUT", "")

registry = unreal.AssetRegistryHelpers.get_asset_registry()
try:
    registry.search_all_assets(True)
except Exception:
    pass

assets = registry.get_assets_by_path("/Game", recursive=True)

meshes = []
abps = []

def cls_name(ad):
    try:
        return str(ad.asset_class_path.asset_name)
    except Exception:
        try:
            return str(ad.asset_class)
        except Exception:
            return ""

def get_skeleton(obj, props):
    for prop in props:
        try:
            v = obj.get_editor_property(prop)
            if v:
                return v.get_path_name()
        except Exception:
            pass
    return "NONE"

for ad in assets:
    name = str(ad.asset_name)
    pkg = str(ad.package_name)
    cls = cls_name(ad)

    if cls == "SkeletalMesh" and name in ("SKM_Manny", "SKM_Manny_Simple"):
        obj = ad.get_asset()
        meshes.append({
            "name": name,
            "package": pkg,
            "skeleton": get_skeleton(obj, ("skeleton",))
        })

    if cls == "AnimBlueprint":
        obj = ad.get_asset()
        skel = get_skeleton(obj, ("target_skeleton", "skeleton"))
        score = 0
        lname = name.lower()
        if "manny" in lname: score += 100
        if "thirdperson" in lname or "third_person" in lname: score += 90
        if "locomotion" in lname: score += 70
        if "unarmed" in lname: score += 50
        if score > 0:
            abps.append({
                "name": name,
                "package": pkg,
                "skeleton": skel,
                "score": score
            })

pairs = []
for m in meshes:
    for a in abps:
        compatible = (
            m["skeleton"] != "NONE"
            and a["skeleton"] != "NONE"
            and m["skeleton"] == a["skeleton"]
        )
        score = a["score"]
        if m["name"] == "SKM_Manny_Simple":
            score += 20
        pairs.append({
            "mesh": m,
            "abp": a,
            "compatible": compatible,
            "score": score
        })

compatible_pairs = [p for p in pairs if p["compatible"]]
compatible_pairs.sort(key=lambda x: x["score"], reverse=True)
best = compatible_pairs[0] if compatible_pairs else None

def runtime_deps(root_pkgs):
    opts = unreal.AssetRegistryDependencyOptions()
    for prop, value in (
        ("include_hard_package_references", True),
        ("include_soft_package_references", True),
        ("include_searchable_names", False),
        ("include_soft_management_references", False),
        ("include_hard_management_references", False),
    ):
        try:
            opts.set_editor_property(prop, value)
        except Exception:
            pass

    seen = set()
    queue = list(root_pkgs)

    while queue:
        pkg = queue.pop(0)
        if pkg in seen:
            continue
        seen.add(pkg)
        try:
            deps = registry.get_dependencies(pkg, opts)
        except Exception:
            deps = []
        for dep in deps:
            s = str(dep)
            if s not in seen:
                queue.append(s)
    return sorted(seen)

result = {
    "meshes": meshes,
    "abps": abps,
    "pairs": pairs,
    "best": best,
}

if best:
    deps = runtime_deps([best["mesh"]["package"], best["abp"]["package"]])
    game = [x for x in deps if x.startswith("/Game/")]
    engine = [x for x in deps if x.startswith("/Engine/")]
    scripts = [x for x in deps if x.startswith("/Script/")]
    plugin_content = [
        x for x in deps
        if not x.startswith("/Game/")
        and not x.startswith("/Engine/")
        and not x.startswith("/Script/")
    ]

    result["runtime_game"] = game
    result["runtime_engine"] = engine
    result["runtime_scripts"] = scripts
    result["runtime_plugin_content"] = plugin_content

    print(f"TP_BEST_MESH={best['mesh']['package']}")
    print(f"TP_BEST_ABP={best['abp']['package']}")
    print(f"TP_BEST_SKELETON={best['mesh']['skeleton']}")
    print(f"TP_RUNTIME_GAME_DEP_COUNT={len(game)}")
    print(f"TP_RUNTIME_ENGINE_DEP_COUNT={len(engine)}")
    print(f"TP_RUNTIME_SCRIPT_DEP_COUNT={len(scripts)}")
    print(f"TP_RUNTIME_PLUGIN_CONTENT_DEP_COUNT={len(plugin_content)}")

    for x in plugin_content[:120]:
        print(f"TP_RUNTIME_PLUGIN_CONTENT_DEP={x}")
else:
    print("TP_BEST_MESH=NONE")
    print("TP_BEST_ABP=NONE")
    print("TP_BEST_SKELETON=NONE")

print(f"TP_MESH_COUNT={len(meshes)}")
print(f"TP_ABP_COUNT={len(abps)}")
print(f"TP_COMPATIBLE_PAIR_COUNT={len(compatible_pairs)}")

if out_path:
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
'@

[IO.File]::WriteAllText($ProbePy, $ProbePython, [Text.UTF8Encoding]::new($false))
$ProbePyForward = $ProbePy.Replace('\','/')

$Selected = $null
$SelectedJson = $null
$SelectedText = ""

foreach ($Proj in $Projects) {
    $Safe = $Proj.BaseName -replace '[^A-Za-z0-9_-]', '_'
    $OutJson = Join-Path $SessionRoot "$Safe.json"
    $StdOut = Join-Path $SessionRoot "$Safe.stdout.log"
    $StdErr = Join-Path $SessionRoot "$Safe.stderr.log"

    $env:ASWW_TP_OUT = $OutJson

    $Args = @(
        $Proj.FullName,
        "-unattended",
        "-nop4",
        "-nosplash",
        "-NullRHI",
        "-stdout",
        "-FullStdOutLogOutput",
        "-ExecutePythonScript=$ProbePyForward"
    )

    $Proc = Start-Process `
        -FilePath $EditorCmd `
        -ArgumentList $Args `
        -WorkingDirectory $Proj.Directory.FullName `
        -PassThru `
        -Wait `
        -RedirectStandardOutput $StdOut `
        -RedirectStandardError $StdErr

    Write-Host ""
    Write-Host "PROBED_TRUE_THIRDPERSON=$($Proj.FullName)"
    Write-Host "PROBE_EXIT=$($Proc.ExitCode)"

    $Text = ""
    if (Test-Path -LiteralPath $StdOut) {
        $Text += Get-Content -Raw -LiteralPath $StdOut
        Select-String -LiteralPath $StdOut -Pattern "TP_" |
            ForEach-Object { Write-Host $_.Line }
    }
    if (Test-Path -LiteralPath $StdErr) {
        $Text += "`n" + (Get-Content -Raw -LiteralPath $StdErr)
    }

    if ($Proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $OutJson -PathType Leaf)) {
        $Data = Get-Content -Raw -LiteralPath $OutJson | ConvertFrom-Json
        if ($null -ne $Data.best) {
            if ($null -eq $Selected) {
                $Selected = $Proj
                $SelectedJson = $Data
                $SelectedText = $Text
            }
        }
    }
}

Remove-Item Env:\ASWW_TP_OUT -ErrorAction SilentlyContinue

if (-not $Selected -or -not $SelectedJson) {
    Stop-Gate "NO_COMPATIBLE_MANNY_PAIR_IN_TRUE_THIRDPERSON_TEMPLATE" 20
}

$PluginDeps = @($SelectedJson.runtime_plugin_content)
$ScriptDeps = @($SelectedJson.runtime_scripts)
$GameDeps = @($SelectedJson.runtime_game)
$EngineDeps = @($SelectedJson.runtime_engine)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TRUE THIRD PERSON RUNTIME DEP CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "SELECTED_TRUE_THIRDPERSON_PROJECT=$($Selected.FullName)"
Write-Host "BEST_TRUE_THIRDPERSON_MESH=$($SelectedJson.best.mesh.package)"
Write-Host "BEST_TRUE_THIRDPERSON_ABP=$($SelectedJson.best.abp.package)"
Write-Host "BEST_TRUE_THIRDPERSON_SKELETON=$($SelectedJson.best.mesh.skeleton)"
Write-Host "RUNTIME_GAME_DEP_COUNT=$($GameDeps.Count)"
Write-Host "RUNTIME_ENGINE_DEP_COUNT=$($EngineDeps.Count)"
Write-Host "RUNTIME_SCRIPT_DEP_COUNT=$($ScriptDeps.Count)"
Write-Host "RUNTIME_PLUGIN_CONTENT_DEP_COUNT=$($PluginDeps.Count)"

foreach ($Dep in $PluginDeps | Select-Object -First 120) {
    Write-Host "RUNTIME_PLUGIN_CONTENT_DEP=$Dep"
}

if ($PluginDeps.Count -eq 0) {
    Write-Host "THIRDPERSON_RUNTIME_DEP_CLASSIFICATION=CLEAN_GAME_ENGINE_SCRIPT_ONLY" -ForegroundColor Green
    Write-Host "NEXT_GATE=COPY_TRUE_THIRDPERSON_GAME_DEPENDENCY_SET_TO_ASWW" -ForegroundColor Green
}
else {
    Write-Host "THIRDPERSON_RUNTIME_DEP_CLASSIFICATION=PAIR_FOUND_WITH_RUNTIME_PLUGIN_CONTENT_DEPS" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=VERIFY_REQUIRED_RUNTIME_PLUGINS_OR_BUILD_MINIMAL_ASWW_ANIMBP" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "THIRDPERSON_RUNTIME_DEPS_V2=PASS" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
