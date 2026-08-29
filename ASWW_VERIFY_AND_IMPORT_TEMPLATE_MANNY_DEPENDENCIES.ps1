[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\TemplateMannyImport"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "TEMPLATE_MANNY_DEPENDENCY_IMPORT=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
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
$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"

if (-not (Test-Path -LiteralPath $EditorCmd -PathType Leaf)) {
    Stop-Gate "UNREALEDITOR_CMD_NOT_FOUND" 11
}
if (-not (Test-Path -LiteralPath $ProjectFile -PathType Leaf)) {
    Stop-Gate "ASWW_UPROJECT_NOT_FOUND" 12
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$SessionRoot = Join-Path $EvidenceRoot $Stamp
New-Item -ItemType Directory -Force -Path $SessionRoot | Out-Null

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " DISCOVER THIRD PERSON TEMPLATE PROJECTS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$TemplateRoot = Join-Path $UERoot "Templates"
$TemplateProjects = @()

if (Test-Path -LiteralPath $TemplateRoot -PathType Container) {
    $TemplateProjects = @(Get-ChildItem -LiteralPath $TemplateRoot -File -Recurse -Filter "*.uproject" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '(?i)ThirdPerson|TP_' } |
        Sort-Object FullName -Unique)
}

if ($TemplateProjects.Count -eq 0) {
    Stop-Gate "NO_THIRDPERSON_TEMPLATE_PROJECT_FOUND" 13
}

foreach ($Proj in $TemplateProjects) {
    Write-Host "TEMPLATE_PROJECT_CANDIDATE=$($Proj.FullName)"
}

$ProbePy = Join-Path $SessionRoot "probe_template.py"

$ProbePython = @'
import unreal
import json
import os

out_path = os.environ.get("ASWW_TEMPLATE_PROBE_OUT", "")
registry = unreal.AssetRegistryHelpers.get_asset_registry()

try:
    registry.search_all_assets(True)
except Exception:
    pass

assets = registry.get_assets_by_path("/Game", recursive=True)

mesh_candidates = []
abp_candidates = []

for ad in assets:
    name = str(ad.asset_name)
    pkg = str(ad.package_name)
    cls = ""
    try:
        cls = str(ad.asset_class_path.asset_name)
    except Exception:
        try:
            cls = str(ad.asset_class)
        except Exception:
            cls = ""

    if cls == "SkeletalMesh" and name in ("SKM_Manny", "SKM_Manny_Simple"):
        obj = ad.get_asset()
        skel = None
        try:
            skel = obj.get_editor_property("skeleton")
        except Exception:
            pass
        mesh_candidates.append({
            "name": name,
            "package": pkg,
            "object_path": f"{pkg}.{name}",
            "skeleton": skel.get_path_name() if skel else "NONE"
        })

    if cls == "AnimBlueprint" and (
        "Manny" in name or
        "ThirdPerson" in name or
        "Unarmed" in name or
        "Locomotion" in name
    ):
        obj = ad.get_asset()
        skel = None
        for prop in ("target_skeleton", "skeleton"):
            try:
                skel = obj.get_editor_property(prop)
                if skel:
                    break
            except Exception:
                pass
        abp_candidates.append({
            "name": name,
            "package": pkg,
            "object_path": f"{pkg}.{name}",
            "skeleton": skel.get_path_name() if skel else "NONE"
        })

pairs = []
for m in mesh_candidates:
    for a in abp_candidates:
        compat = (
            m["skeleton"] != "NONE"
            and a["skeleton"] != "NONE"
            and m["skeleton"] == a["skeleton"]
        )
        pairs.append({
            "mesh": m,
            "abp": a,
            "compatible": compat
        })

best = None
for p in pairs:
    if p["compatible"]:
        best = p
        if p["mesh"]["name"] == "SKM_Manny_Simple":
            break

result = {
    "mesh_candidates": mesh_candidates,
    "abp_candidates": abp_candidates,
    "pairs": pairs,
    "best": best
}

if out_path:
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

print(f"ASWW_TEMPLATE_MESH_COUNT={len(mesh_candidates)}")
print(f"ASWW_TEMPLATE_ABP_COUNT={len(abp_candidates)}")
print(f"ASWW_TEMPLATE_COMPATIBLE_PAIR={'YES' if best else 'NO'}")
if best:
    print(f"ASWW_TEMPLATE_BEST_MESH={best['mesh']['package']}")
    print(f"ASWW_TEMPLATE_BEST_ABP={best['abp']['package']}")
    print(f"ASWW_TEMPLATE_BEST_SKELETON={best['mesh']['skeleton']}")
'@

[IO.File]::WriteAllText($ProbePy, $ProbePython, [Text.UTF8Encoding]::new($false))
$ProbePyForward = $ProbePy.Replace('\','/')

$SelectedProject = $null
$SelectedProbe = $null

foreach ($Proj in $TemplateProjects) {
    $SafeName = ($Proj.BaseName -replace '[^A-Za-z0-9_-]', '_')
    $ProbeJson = Join-Path $SessionRoot "probe_$SafeName.json"
    $StdOut = Join-Path $SessionRoot "probe_$SafeName.stdout.log"
    $StdErr = Join-Path $SessionRoot "probe_$SafeName.stderr.log"

    $env:ASWW_TEMPLATE_PROBE_OUT = $ProbeJson

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

    Write-Host "PROBED_TEMPLATE=$($Proj.FullName)"
    Write-Host "TEMPLATE_PROBE_EXIT=$($Proc.ExitCode)"

    if (Test-Path -LiteralPath $StdOut) {
        Select-String -LiteralPath $StdOut -Pattern "ASWW_TEMPLATE_" |
            ForEach-Object { Write-Host $_.Line }
    }

    if ($Proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $ProbeJson -PathType Leaf)) {
        $Probe = Get-Content -Raw -LiteralPath $ProbeJson | ConvertFrom-Json
        if ($null -ne $Probe.best) {
            $SelectedProject = $Proj
            $SelectedProbe = $Probe
            break
        }
    }
}

Remove-Item Env:\ASWW_TEMPLATE_PROBE_OUT -ErrorAction SilentlyContinue

if (-not $SelectedProject -or -not $SelectedProbe) {
    Stop-Gate "NO_TEMPLATE_PROJECT_WITH_COMPATIBLE_MANNY_MESH_AND_ABP" 20
}

$BestMeshPackage = [string]$SelectedProbe.best.mesh.package
$BestABPPackage = [string]$SelectedProbe.best.abp.package
$BestSkeleton = [string]$SelectedProbe.best.mesh.skeleton

Write-Host ""
Write-Host "SELECTED_TEMPLATE_PROJECT=$($SelectedProject.FullName)" -ForegroundColor Green
Write-Host "BEST_TEMPLATE_MESH=$BestMeshPackage" -ForegroundColor Green
Write-Host "BEST_TEMPLATE_ABP=$BestABPPackage" -ForegroundColor Green
Write-Host "BEST_TEMPLATE_SKELETON=$BestSkeleton" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ENUMERATE RECURSIVE /GAME DEPENDENCIES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$DepsPy = Join-Path $SessionRoot "collect_dependencies.py"
$DepsJson = Join-Path $SessionRoot "dependencies.json"
$DepsStdOut = Join-Path $SessionRoot "dependencies.stdout.log"
$DepsStdErr = Join-Path $SessionRoot "dependencies.stderr.log"

$DepsPython = @"
import unreal
import json
import os

roots = [
    "$BestMeshPackage",
    "$BestABPPackage"
]

out_path = os.environ.get("ASWW_TEMPLATE_DEPS_OUT", "")
registry = unreal.AssetRegistryHelpers.get_asset_registry()

try:
    registry.search_all_assets(True)
except Exception:
    pass

def deps_for(pkg):
    try:
        return [str(x) for x in registry.get_dependencies(pkg)]
    except Exception:
        try:
            opts = unreal.AssetRegistryDependencyOptions()
            for prop in ("include_hard_package_references", "include_soft_package_references",
                         "include_searchable_names", "include_soft_management_references",
                         "include_hard_management_references"):
                try:
                    opts.set_editor_property(prop, True)
                except Exception:
                    pass
            return [str(x) for x in registry.get_dependencies(pkg, opts)]
        except Exception:
            return []

visited = set()
queue = list(roots)

while queue:
    pkg = queue.pop(0)
    if pkg in visited:
        continue
    visited.add(pkg)

    for dep in deps_for(pkg):
        if dep not in visited:
            queue.append(dep)

game_pkgs = sorted([p for p in visited if p.startswith("/Game/")])
engine_pkgs = sorted([p for p in visited if p.startswith("/Engine/")])
other_pkgs = sorted([p for p in visited if not p.startswith("/Game/") and not p.startswith("/Engine/")])

result = {
    "roots": roots,
    "game_packages": game_pkgs,
    "engine_packages": engine_pkgs,
    "other_packages": other_pkgs
}

if out_path:
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

print(f"ASWW_DEP_GAME_COUNT={len(game_pkgs)}")
print(f"ASWW_DEP_ENGINE_COUNT={len(engine_pkgs)}")
print(f"ASWW_DEP_OTHER_COUNT={len(other_pkgs)}")
for p in other_pkgs[:80]:
    print(f"ASWW_DEP_OTHER={p}")
"@

[IO.File]::WriteAllText($DepsPy, $DepsPython, [Text.UTF8Encoding]::new($false))
$DepsPyForward = $DepsPy.Replace('\','/')
$env:ASWW_TEMPLATE_DEPS_OUT = $DepsJson

$Args = @(
    $SelectedProject.FullName,
    "-unattended",
    "-nop4",
    "-nosplash",
    "-NullRHI",
    "-stdout",
    "-FullStdOutLogOutput",
    "-ExecutePythonScript=$DepsPyForward"
)

$Proc = Start-Process `
    -FilePath $EditorCmd `
    -ArgumentList $Args `
    -WorkingDirectory $SelectedProject.Directory.FullName `
    -PassThru `
    -Wait `
    -RedirectStandardOutput $DepsStdOut `
    -RedirectStandardError $DepsStdErr

Remove-Item Env:\ASWW_TEMPLATE_DEPS_OUT -ErrorAction SilentlyContinue

Write-Host "DEPENDENCY_SCAN_EXIT=$($Proc.ExitCode)"
if ($Proc.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $DepsJson -PathType Leaf)) {
    Stop-Gate "DEPENDENCY_SCAN_FAILED" 21
}

if (Test-Path -LiteralPath $DepsStdOut) {
    Select-String -LiteralPath $DepsStdOut -Pattern "ASWW_DEP_" |
        ForEach-Object { Write-Host $_.Line }
}

$Deps = Get-Content -Raw -LiteralPath $DepsJson | ConvertFrom-Json

if (@($Deps.other_packages).Count -gt 0) {
    Write-Host "NON_ENGINE_NON_GAME_DEPENDENCIES_DETECTED=True" -ForegroundColor Yellow
    @($Deps.other_packages) | Select-Object -First 80 | ForEach-Object {
        Write-Host "OTHER_DEPENDENCY=$_"
    }
    Stop-Gate "TEMPLATE_MANNY_DEPENDS_ON_NON_GAME_PLUGIN_PACKAGES" 22
}

$TemplateContent = Join-Path $SelectedProject.Directory.FullName "Content"
if (-not (Test-Path -LiteralPath $TemplateContent -PathType Container)) {
    Stop-Gate "SELECTED_TEMPLATE_CONTENT_DIRECTORY_NOT_FOUND" 23
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY SOURCE FILES FOR DEPENDENCY SET" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$CopyPlan = @()
$Missing = @()

foreach ($Pkg in @($Deps.game_packages)) {
    $Rel = $Pkg.Substring("/Game/".Length) -replace '/', '\'
    $Base = Join-Path $TemplateContent $Rel

    $FoundPrimary = $false
    foreach ($Ext in @(".uasset",".umap")) {
        $Candidate = "$Base$Ext"
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            $FoundPrimary = $true
            $CopyPlan += [PSCustomObject]@{
                Package = $Pkg
                SourceBase = $Base
                Primary = $Candidate
                RelativeBase = $Rel
            }
            break
        }
    }

    if (-not $FoundPrimary) {
        $Missing += $Pkg
    }
}

Write-Host "DEPENDENCY_GAME_PACKAGE_COUNT=$(@($Deps.game_packages).Count)"
Write-Host "DEPENDENCY_COPY_PLAN_COUNT=$($CopyPlan.Count)"
Write-Host "DEPENDENCY_MISSING_SOURCE_COUNT=$($Missing.Count)"

if ($Missing.Count -gt 0) {
    $Missing | Select-Object -First 100 | ForEach-Object { Write-Host "MISSING_SOURCE_PACKAGE=$_" }
    Stop-Gate "DEPENDENCY_SOURCE_FILES_MISSING" 24
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COPY VERIFIED DEPENDENCY SET INTO ASWW /GAME" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\TemplateMannyImportBackup_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

$ProjectContent = Join-Path $ProjectRoot "Content"
$CopiedFileCount = 0
$OverwrittenFileCount = 0

foreach ($Item in $CopyPlan) {
    $RelDir = Split-Path -Parent $Item.RelativeBase
    $LeafBase = Split-Path -Leaf $Item.RelativeBase
    $SrcDir = Split-Path -Parent $Item.SourceBase
    $DstDir = if ([string]::IsNullOrWhiteSpace($RelDir)) {
        $ProjectContent
    } else {
        Join-Path $ProjectContent $RelDir
    }

    New-Item -ItemType Directory -Force -Path $DstDir | Out-Null

    foreach ($Ext in @(".uasset",".umap",".uexp",".ubulk",".uptnl")) {
        $Src = Join-Path $SrcDir ($LeafBase + $Ext)
        if (-not (Test-Path -LiteralPath $Src -PathType Leaf)) {
            continue
        }

        $Dst = Join-Path $DstDir ($LeafBase + $Ext)

        if (Test-Path -LiteralPath $Dst -PathType Leaf) {
            $BackupFile = Join-Path $BackupRoot (($Dst.Substring($ProjectRoot.Length).TrimStart('\')) -replace ':','_')
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $BackupFile) | Out-Null
            Copy-Item -LiteralPath $Dst -Destination $BackupFile -Force
            $OverwrittenFileCount++
        }

        Copy-Item -LiteralPath $Src -Destination $Dst -Force
        $CopiedFileCount++
    }
}

Write-Host "COPIED_DEPENDENCY_FILE_COUNT=$CopiedFileCount"
Write-Host "OVERWRITTEN_EXISTING_FILE_COUNT=$OverwrittenFileCount"
Write-Host "IMPORT_BACKUP_ROOT=$BackupRoot"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY IMPORTED ASSETS INSIDE ASWW" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$VerifyPy = Join-Path $SessionRoot "verify_asww_import.py"
$VerifyStdOut = Join-Path $SessionRoot "verify_asww_import.stdout.log"
$VerifyStdErr = Join-Path $SessionRoot "verify_asww_import.stderr.log"

$VerifyPython = @"
import unreal

mesh_pkg = "$BestMeshPackage"
abp_pkg = "$BestABPPackage"

def load_from_pkg(pkg):
    name = pkg.rsplit("/", 1)[-1]
    return unreal.EditorAssetLibrary.load_asset(pkg) or unreal.EditorAssetLibrary.load_asset(f"{pkg}.{name}")

mesh = load_from_pkg(mesh_pkg)
abp = load_from_pkg(abp_pkg)

mesh_cls = mesh.get_class().get_name() if mesh else "NONE"
abp_cls = abp.get_class().get_name() if abp else "NONE"

mesh_skel = None
abp_skel = None

if mesh:
    try:
        mesh_skel = mesh.get_editor_property("skeleton")
    except Exception:
        pass

if abp:
    for prop in ("target_skeleton", "skeleton"):
        try:
            abp_skel = abp.get_editor_property(prop)
            if abp_skel:
                break
        except Exception:
            pass

mesh_skel_path = mesh_skel.get_path_name() if mesh_skel else "NONE"
abp_skel_path = abp_skel.get_path_name() if abp_skel else "NONE"

compatible = (
    mesh is not None
    and abp is not None
    and mesh_cls == "SkeletalMesh"
    and abp_cls == "AnimBlueprint"
    and mesh_skel_path != "NONE"
    and mesh_skel_path == abp_skel_path
)

print(f"ASWW_IMPORTED_MESH_LOAD={mesh is not None}")
print(f"ASWW_IMPORTED_MESH_CLASS={mesh_cls}")
print(f"ASWW_IMPORTED_ABP_LOAD={abp is not None}")
print(f"ASWW_IMPORTED_ABP_CLASS={abp_cls}")
print(f"ASWW_IMPORTED_MESH_SKELETON={mesh_skel_path}")
print(f"ASWW_IMPORTED_ABP_SKELETON={abp_skel_path}")
print(f"ASWW_IMPORTED_PAIR_COMPATIBLE={compatible}")
"@

[IO.File]::WriteAllText($VerifyPy, $VerifyPython, [Text.UTF8Encoding]::new($false))
$VerifyPyForward = $VerifyPy.Replace('\','/')

$Args = @(
    $ProjectFile,
    "-unattended",
    "-nop4",
    "-nosplash",
    "-NullRHI",
    "-stdout",
    "-FullStdOutLogOutput",
    "-ExecutePythonScript=$VerifyPyForward"
)

$Proc = Start-Process `
    -FilePath $EditorCmd `
    -ArgumentList $Args `
    -WorkingDirectory $ProjectRoot `
    -PassThru `
    -Wait `
    -RedirectStandardOutput $VerifyStdOut `
    -RedirectStandardError $VerifyStdErr

Write-Host "ASWW_IMPORT_VERIFY_EXIT=$($Proc.ExitCode)"

if (Test-Path -LiteralPath $VerifyStdOut) {
    Select-String -LiteralPath $VerifyStdOut -Pattern "ASWW_IMPORTED_" |
        ForEach-Object { Write-Host $_.Line }
}

$VerifyText = ""
if (Test-Path -LiteralPath $VerifyStdOut) {
    $VerifyText += Get-Content -Raw -LiteralPath $VerifyStdOut
}
if (Test-Path -LiteralPath $VerifyStdErr) {
    $VerifyText += "`n" + (Get-Content -Raw -LiteralPath $VerifyStdErr)
}

$PythonError = $VerifyText -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$Fatal = $VerifyText -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$CompatPass = $VerifyText -match "ASWW_IMPORTED_PAIR_COMPATIBLE=True"

Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "FATAL_ERROR_SEEN=$Fatal"

if ($Proc.ExitCode -ne 0 -or $PythonError -or $Fatal -or -not $CompatPass) {
    Write-Host "TEMPLATE_MANNY_DEPENDENCY_IMPORT=PARTIAL_COPY_VERIFY_FAILED" -ForegroundColor Red
    Write-Host "IMPORT_BACKUP_ROOT=$BackupRoot"
    Write-Host "DO_NOT_COMMIT" -ForegroundColor Yellow
    exit 30
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED_AFTER_IMPORT" 31
}

Write-Host ""
Write-Host "TEMPLATE_MANNY_DEPENDENCY_IMPORT=PASS" -ForegroundColor Green
Write-Host "SELECTED_TEMPLATE_PROJECT=$($SelectedProject.FullName)" -ForegroundColor Green
Write-Host "IMPORTED_MANNY_MESH=$BestMeshPackage" -ForegroundColor Green
Write-Host "IMPORTED_MANNY_ABP=$BestABPPackage" -ForegroundColor Green
Write-Host "IMPORTED_MANNY_SKELETON=$BestSkeleton" -ForegroundColor Green
Write-Host "NEXT_GATE=INTEGRATE_IMPORTED_MANNY_IN_ASCHARACTER_AND_PACKAGE" -ForegroundColor Green
Write-Host "KEEP_TEMP_VISUAL_PROOF_UNTIL_REAL_MANNY_PACKAGE_PASSES" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_VISUAL_PROOF_OR_TELEMETRY" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
