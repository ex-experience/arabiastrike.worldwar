[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$TemplateProject = "D:\UE_5.8\Templates\TP_ThirdPersonBP\TP_ThirdPersonBP.uproject",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\RealMannyIntegration"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "REAL_MANNY_INTEGRATION=STOPPED" -ForegroundColor Red
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

$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$CharacterCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"
$PackageScript = Join-Path $ProjectRoot "ASWW_REPAIR_STAGINGDIR_AND_PACKAGE.ps1"

foreach ($Required in @($ProjectFile,$EditorCmd,$TemplateProject,$CharacterCpp,$PackageScript)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

$TemplateContent = Join-Path (Split-Path -Parent $TemplateProject) "Content"
if (-not (Test-Path -LiteralPath $TemplateContent -PathType Container)) {
    Stop-Gate "TEMPLATE_CONTENT_NOT_FOUND" 12
}

$MeshPkg = "/Game/Characters/Mannequins/Meshes/SKM_Manny_Simple"
$AnimPkg = "/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed"
$SkeletonPkg = "/Game/Characters/Mannequins/Meshes/SK_Mannequin.SK_Mannequin"

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$SessionRoot = Join-Path $EvidenceRoot $Stamp
New-Item -ItemType Directory -Force -Path $SessionRoot | Out-Null

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RECOMPUTE TRUE THIRD PERSON /GAME DEPENDENCIES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$DepsPy = Join-Path $SessionRoot "collect_tp_deps.py"
$DepsJson = Join-Path $SessionRoot "tp_deps.json"
$DepsStdOut = Join-Path $SessionRoot "tp_deps.stdout.log"
$DepsStdErr = Join-Path $SessionRoot "tp_deps.stderr.log"

$DepsPython = @"
import unreal, json, os

roots = [
    "$MeshPkg",
    "$AnimPkg"
]

out_path = os.environ.get("ASWW_TP_DEPS_OUT", "")
registry = unreal.AssetRegistryHelpers.get_asset_registry()

try:
    registry.search_all_assets(True)
except Exception:
    pass

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
queue = list(roots)

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

game = sorted([x for x in seen if x.startswith("/Game/")])
plugin_content = sorted([
    x for x in seen
    if not x.startswith("/Game/")
    and not x.startswith("/Engine/")
    and not x.startswith("/Script/")
])

result = {
    "roots": roots,
    "game": game,
    "plugin_content": plugin_content,
}

if out_path:
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

print(f"ASWW_TP_GAME_DEP_COUNT={len(game)}")
print(f"ASWW_TP_PLUGIN_CONTENT_DEP_COUNT={len(plugin_content)}")
for x in plugin_content[:120]:
    print(f"ASWW_TP_PLUGIN_CONTENT_DEP={x}")
"@

[IO.File]::WriteAllText($DepsPy, $DepsPython, [Text.UTF8Encoding]::new($false))
$DepsPyForward = $DepsPy.Replace('\','/')
$env:ASWW_TP_DEPS_OUT = $DepsJson

$Args = @(
    $TemplateProject,
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
    -WorkingDirectory (Split-Path -Parent $TemplateProject) `
    -PassThru `
    -Wait `
    -RedirectStandardOutput $DepsStdOut `
    -RedirectStandardError $DepsStdErr

Remove-Item Env:\ASWW_TP_DEPS_OUT -ErrorAction SilentlyContinue

Write-Host "DEPENDENCY_SCAN_EXIT=$($Proc.ExitCode)"
if (Test-Path -LiteralPath $DepsStdOut) {
    Select-String -LiteralPath $DepsStdOut -Pattern "ASWW_TP_" |
        ForEach-Object { Write-Host $_.Line }
}

if ($Proc.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $DepsJson -PathType Leaf)) {
    Stop-Gate "THIRDPERSON_DEPENDENCY_SCAN_FAILED" 20
}

$Deps = Get-Content -Raw -LiteralPath $DepsJson | ConvertFrom-Json
$GameDeps = @($Deps.game)
$PluginDeps = @($Deps.plugin_content)

Write-Host "GAME_DEPENDENCY_COUNT=$($GameDeps.Count)"
Write-Host "PLUGIN_CONTENT_DEPENDENCY_COUNT=$($PluginDeps.Count)"

if ($GameDeps.Count -eq 0) {
    Stop-Gate "NO_GAME_DEPENDENCIES_FOUND" 21
}

# We already verified ControlRig + ACLPlugin are runtime-capable and mounted in ASWW.
# Refuse unexpected plugin-content roots beyond those two.
$UnexpectedPluginDeps = @($PluginDeps | Where-Object {
    $_ -notlike "/ControlRig/*" -and
    $_ -notlike "/ACLPlugin/*"
})

if ($UnexpectedPluginDeps.Count -gt 0) {
    $UnexpectedPluginDeps | Select-Object -First 100 | ForEach-Object {
        Write-Host "UNEXPECTED_PLUGIN_DEPENDENCY=$_"
    }
    Stop-Gate "UNEXPECTED_PLUGIN_CONTENT_DEPENDENCY" 22
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " BUILD VERIFIED COPY PLAN" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$CopyPlan = @()
$Missing = @()

foreach ($Pkg in $GameDeps) {
    $Rel = $Pkg.Substring("/Game/".Length) -replace '/', '\'
    $Base = Join-Path $TemplateContent $Rel

    $Primary = $null
    foreach ($Ext in @(".uasset",".umap")) {
        $Candidate = "$Base$Ext"
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            $Primary = $Candidate
            break
        }
    }

    if (-not $Primary) {
        $Missing += $Pkg
        continue
    }

    $CopyPlan += [PSCustomObject]@{
        Package = $Pkg
        RelativeBase = $Rel
        SourceBase = $Base
        Primary = $Primary
    }
}

Write-Host "COPY_PLAN_PACKAGE_COUNT=$($CopyPlan.Count)"
Write-Host "MISSING_SOURCE_PACKAGE_COUNT=$($Missing.Count)"

if ($Missing.Count -gt 0) {
    $Missing | Select-Object -First 100 | ForEach-Object {
        Write-Host "MISSING_SOURCE_PACKAGE=$_"
    }
    Stop-Gate "TEMPLATE_SOURCE_PACKAGE_MISSING" 23
}

$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\RealMannyImportBackup_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
$ProjectContent = Join-Path $ProjectRoot "Content"

$CopiedFiles = 0
$Overwritten = 0

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
            $RelBackup = $Dst.Substring($ProjectRoot.Length).TrimStart('\')
            $BackupFile = Join-Path $BackupRoot $RelBackup
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $BackupFile) | Out-Null
            Copy-Item -LiteralPath $Dst -Destination $BackupFile -Force
            $Overwritten++
        }

        Copy-Item -LiteralPath $Src -Destination $Dst -Force
        $CopiedFiles++
    }
}

Write-Host "COPIED_DEPENDENCY_FILE_COUNT=$CopiedFiles"
Write-Host "OVERWRITTEN_EXISTING_FILE_COUNT=$Overwritten"
Write-Host "IMPORT_BACKUP_ROOT=$BackupRoot"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY IMPORTED MANNY INSIDE ASWW" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$VerifyPy = Join-Path $SessionRoot "verify_asww_manny.py"
$VerifyStdOut = Join-Path $SessionRoot "verify_asww_manny.stdout.log"
$VerifyStdErr = Join-Path $SessionRoot "verify_asww_manny.stderr.log"

$VerifyPython = @"
import unreal

mesh_pkg = "$MeshPkg"
abp_pkg = "$AnimPkg"

mesh = unreal.EditorAssetLibrary.load_asset(mesh_pkg)
abp = unreal.EditorAssetLibrary.load_asset(abp_pkg)

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

print(f"ASWW_REAL_MANNY_MESH_LOAD={mesh is not None}")
print(f"ASWW_REAL_MANNY_MESH_CLASS={mesh_cls}")
print(f"ASWW_REAL_MANNY_ABP_LOAD={abp is not None}")
print(f"ASWW_REAL_MANNY_ABP_CLASS={abp_cls}")
print(f"ASWW_REAL_MANNY_MESH_SKELETON={mesh_skel_path}")
print(f"ASWW_REAL_MANNY_ABP_SKELETON={abp_skel_path}")
print(f"ASWW_REAL_MANNY_COMPATIBLE={compatible}")

checks = [
    "/ACLPlugin/ACLAnimCurveCompressionSettings",
    "/ControlRig/Controls/ControlRigGizmoMaterial",
]
for path in checks:
    obj = unreal.EditorAssetLibrary.load_asset(path)
    print(f"ASWW_REQUIRED_PLUGIN_ASSET|{path}|LOAD={obj is not None}")
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

$VerifyText = ""
if (Test-Path -LiteralPath $VerifyStdOut) {
    $VerifyText += Get-Content -Raw -LiteralPath $VerifyStdOut
    Select-String -LiteralPath $VerifyStdOut -Pattern "ASWW_REAL_MANNY_|ASWW_REQUIRED_PLUGIN_ASSET" |
        ForEach-Object { Write-Host $_.Line }
}
if (Test-Path -LiteralPath $VerifyStdErr) {
    $VerifyText += "`n" + (Get-Content -Raw -LiteralPath $VerifyStdErr)
}

$CompatPass = $VerifyText -match "ASWW_REAL_MANNY_COMPATIBLE=True"
$ACLPass = $VerifyText -match 'ASWW_REQUIRED_PLUGIN_ASSET\|/ACLPlugin/ACLAnimCurveCompressionSettings\|LOAD=True'
$ControlRigPass = $VerifyText -match 'ASWW_REQUIRED_PLUGIN_ASSET\|/ControlRig/Controls/ControlRigGizmoMaterial\|LOAD=True'
$PythonError = $VerifyText -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$Fatal = $VerifyText -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

if ($Proc.ExitCode -ne 0 -or $PythonError -or $Fatal -or -not $CompatPass -or -not $ACLPass -or -not $ControlRigPass) {
    Stop-Gate "ASWW_IMPORTED_MANNY_VERIFY_FAILED" 30
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PATCH ASCHARACTER: REMOVE CUBE, ASSIGN MANNY + ABP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$CharacterOriginal = Get-Content -Raw -LiteralPath $CharacterCpp
$SourceBackup = Join-Path $BackupRoot "ASCharacter.cpp.before_real_manny"
Copy-Item -LiteralPath $CharacterCpp -Destination $SourceBackup -Force
Write-Host "ASCHARACTER_SOURCE_BACKUP=$SourceBackup"

$Text = $CharacterOriginal

# Remove the temporary visual proof block only.
$ProofPattern = '(?s)\s*// TEMPORARY QA VISUAL ONLY\. Do not commit as final player art\..*?UE_LOG\(LogTemp,\s*Warning,\s*TEXT\("ASWW_VISUAL_PROOF component=%s mesh=%s"\),\s*\*GetNameSafe\(VisualProof\),\s*\*GetNameSafe\(VisualProof->GetStaticMesh\(\)\)\s*\);\s*'
$ProofRx = [regex]::new($ProofPattern)

if ($ProofRx.IsMatch($Text)) {
    $Text = $ProofRx.Replace($Text, [Environment]::NewLine, 1)
    Write-Host "TEMP_CUBE_BLOCK_REMOVED=True" -ForegroundColor Green
}
elseif ($Text -match 'ASWW_VISUAL_PROOF|ASWW_PlayerVisualProof') {
    Stop-Gate "TEMP_CUBE_PRESENT_BUT_SAFE_REGEX_DID_NOT_MATCH" 31
}
else {
    Write-Host "TEMP_CUBE_BLOCK_REMOVED=NOT_PRESENT" -ForegroundColor Yellow
}

# Remove now-unused temp cube includes.
foreach ($Inc in @(
    '#include "Components/StaticMeshComponent.h"',
    '#include "Engine/StaticMesh.h"'
)) {
    $Text = $Text.Replace($Inc + "`r`n", "")
    $Text = $Text.Replace($Inc + "`n", "")
}

$IncludeAnchor = '#include "Camera/CameraComponent.h"'
if (-not $Text.Contains($IncludeAnchor)) {
    Stop-Gate "CAMERA_INCLUDE_ANCHOR_NOT_FOUND" 32
}

$NeededIncludes = @(
    '#include "Components/SkeletalMeshComponent.h"',
    '#include "Engine/SkeletalMesh.h"',
    '#include "Animation/AnimInstance.h"',
    '#include "UObject/ConstructorHelpers.h"'
)

foreach ($Inc in $NeededIncludes) {
    if (-not $Text.Contains($Inc)) {
        $Text = $Text.Replace($IncludeAnchor, $IncludeAnchor + [Environment]::NewLine + $Inc)
    }
}

if ($Text -match 'ASWW_REAL_PLAYER_MANNY') {
    Stop-Gate "REAL_MANNY_PATCH_ALREADY_PRESENT" 33
}

$AttachRx = [regex]::new(
    'FollowCamera->SetupAttachment\s*\(\s*CameraBoom\s*,\s*USpringArmComponent::SocketName\s*\)\s*;',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

if (-not $AttachRx.IsMatch($Text)) {
    Stop-Gate "FOLLOW_CAMERA_ATTACHMENT_PATTERN_NOT_FOUND" 34
}

$MannyBlock = @'

    static ConstructorHelpers::FObjectFinder<USkeletalMesh> PlayerMeshAsset(
        TEXT("/Game/Characters/Mannequins/Meshes/SKM_Manny_Simple.SKM_Manny_Simple"));
    if (PlayerMeshAsset.Succeeded())
    {
        GetMesh()->SetSkeletalMesh(PlayerMeshAsset.Object);
        GetMesh()->SetRelativeLocation(FVector(0.f, 0.f, -90.f));
        GetMesh()->SetRelativeRotation(FRotator(0.f, -90.f, 0.f));
        GetMesh()->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    }

    static ConstructorHelpers::FClassFinder<UAnimInstance> PlayerAnimClass(
        TEXT("/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed"));
    if (PlayerAnimClass.Succeeded())
    {
        GetMesh()->SetAnimInstanceClass(PlayerAnimClass.Class);
    }

    UE_LOG(LogTemp, Warning,
        TEXT("ASWW_REAL_PLAYER_MANNY mesh=%s animClass=%s"),
        *GetNameSafe(GetMesh()->GetSkeletalMeshAsset()),
        *GetNameSafe(GetMesh()->GetAnimClass()));
'@

$Text = $AttachRx.Replace(
    $Text,
    [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        return $m.Value + $MannyBlock
    },
    1
)

[IO.File]::WriteAllText($CharacterCpp, $Text, [Text.UTF8Encoding]::new($true))

$Patched = Get-Content -Raw -LiteralPath $CharacterCpp

$Checks = @{
    "REAL_MANNY_MARKER" = "ASWW_REAL_PLAYER_MANNY"
    "REAL_MANNY_MESH_PATH" = "/Game/Characters/Mannequins/Meshes/SKM_Manny_Simple.SKM_Manny_Simple"
    "REAL_MANNY_ABP_PATH" = "/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed"
    "TEMP_CUBE_MARKER_REMOVED" = "ASWW_VISUAL_PROOF"
}

Write-Host "REAL_MANNY_MARKER_PRESENT=$($Patched.Contains($Checks["REAL_MANNY_MARKER"]))"
Write-Host "REAL_MANNY_MESH_PATH_PRESENT=$($Patched.Contains($Checks["REAL_MANNY_MESH_PATH"]))"
Write-Host "REAL_MANNY_ABP_PATH_PRESENT=$($Patched.Contains($Checks["REAL_MANNY_ABP_PATH"]))"
Write-Host "TEMP_CUBE_MARKER_STILL_PRESENT=$($Patched.Contains($Checks["TEMP_CUBE_MARKER_REMOVED"]))"

if (-not $Patched.Contains($Checks["REAL_MANNY_MARKER"]) -or
    -not $Patched.Contains($Checks["REAL_MANNY_MESH_PATH"]) -or
    -not $Patched.Contains($Checks["REAL_MANNY_ABP_PATH"]) -or
    $Patched.Contains($Checks["TEMP_CUBE_MARKER_REMOVED"])) {
    Stop-Gate "ASCHARACTER_REAL_MANNY_PATCH_VERIFY_FAILED" 35
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 36
}

Write-Host ""
Write-Host "REAL_MANNY_SOURCE_INTEGRATION=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=REAL_WIN64_BUILD_COOK_PACKAGE" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " BUILD + COOK + PACKAGE REAL MANNY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PackageScript
$PackageExit = $LASTEXITCODE
Write-Host "PACKAGE_PIPELINE_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Stop-Gate "REAL_MANNY_PACKAGE_FAILED_EXIT_$PackageExit" $(if ($PackageExit -gt 0) { $PackageExit } else { 40 })
}

$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe"
if (-not (Test-Path -LiteralPath $PackagedExe -PathType Leaf)) {
    Stop-Gate "PACKAGE_EXIT_ZERO_BUT_EXE_MISSING" 41
}

Write-Host ""
Write-Host "REAL_MANNY_PACKAGE=PASS" -ForegroundColor Green
Write-Host "PACKAGED_EXE=$PackagedExe" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_REAL_MANNY_PACKAGED_QA" -ForegroundColor Green
Write-Host "KEEP_MOVEMENT_TELEMETRY_UNTIL_REAL_MANNY_RUNTIME_QA_PASSES" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
