[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\RealMannySafeArgV3"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "REAL_MANNY_SAFEARG_V3=STOPPED" -ForegroundColor Red
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

foreach ($Required in @($ProjectFile,$EditorCmd,$CharacterCpp,$PackageScript)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

$MeshFile = Join-Path $ProjectRoot "Content\Characters\Mannequins\Meshes\SKM_Manny_Simple.uasset"
$AnimFile = Join-Path $ProjectRoot "Content\Characters\Mannequins\Anims\Unarmed\ABP_Unarmed.uasset"

$MeshPhysical = Test-Path -LiteralPath $MeshFile -PathType Leaf
$AnimPhysical = Test-Path -LiteralPath $AnimFile -PathType Leaf

Write-Host "COPIED_MANNY_MESH_FILE_PRESENT=$MeshPhysical"
Write-Host "COPIED_MANNY_ABP_FILE_PRESENT=$AnimPhysical"
Write-Host "MANNY_MESH_FILE=$MeshFile"
Write-Host "MANNY_ABP_FILE=$AnimFile"

if (-not $MeshPhysical -or -not $AnimPhysical) {
    Stop-Gate "COPIED_MANNY_PRIMARY_FILES_NOT_PRESENT" 12
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$SessionRoot = Join-Path $EvidenceRoot $Stamp
New-Item -ItemType Directory -Force -Path $SessionRoot | Out-Null

$PyFile = Join-Path $SessionRoot "verify_safe_project_arg.py"
$StdOut = Join-Path $SessionRoot "verify_safe_project_arg.stdout.log"
$StdErr = Join-Path $SessionRoot "verify_safe_project_arg.stderr.log"

$Python = @'
import unreal

registry = unreal.AssetRegistryHelpers.get_asset_registry()

try:
    registry.search_all_assets(True)
except Exception as exc:
    print(f"ASWW_SAFE_SEARCH_ALL_ERROR={exc}")

try:
    registry.scan_paths_synchronous(["/Game/Characters"], True)
    print("ASWW_SAFE_FORCE_SCAN=PASS")
except Exception as exc:
    print(f"ASWW_SAFE_FORCE_SCAN=SKIPPED:{exc}")

project_dir = unreal.Paths.project_dir()
content_dir = unreal.Paths.project_content_dir()

print(f"ASWW_SAFE_PROJECT_DIR={project_dir}")
print(f"ASWW_SAFE_CONTENT_DIR={content_dir}")

try:
    game_assets = registry.get_assets_by_path("/Game", recursive=True)
    print(f"ASWW_SAFE_GAME_ASSET_COUNT={len(game_assets)}")
except Exception as exc:
    print(f"ASWW_SAFE_GAME_ASSET_COUNT=-1")
    print(f"ASWW_SAFE_GAME_COUNT_ERROR={exc}")
    game_assets = []

for wanted in ("SKM_Manny_Simple", "ABP_Unarmed"):
    for ad in game_assets:
        try:
            if str(ad.asset_name) == wanted:
                print(f"ASWW_SAFE_REGISTRY_MATCH|{wanted}|PACKAGE={ad.package_name}|CLASS={ad.asset_class_path.asset_name}")
        except Exception:
            pass

mesh_path = "/Game/Characters/Mannequins/Meshes/SKM_Manny_Simple"
abp_path = "/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed"

mesh_exists = unreal.EditorAssetLibrary.does_asset_exist(mesh_path)
abp_exists = unreal.EditorAssetLibrary.does_asset_exist(abp_path)

mesh = unreal.EditorAssetLibrary.load_asset(mesh_path) if mesh_exists else None
abp = unreal.EditorAssetLibrary.load_asset(abp_path) if abp_exists else None

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

print(f"ASWW_SAFE_MESH_EXISTS={mesh_exists}")
print(f"ASWW_SAFE_MESH_LOAD={mesh is not None}")
print(f"ASWW_SAFE_MESH_CLASS={mesh_cls}")
print(f"ASWW_SAFE_ABP_EXISTS={abp_exists}")
print(f"ASWW_SAFE_ABP_LOAD={abp is not None}")
print(f"ASWW_SAFE_ABP_CLASS={abp_cls}")
print(f"ASWW_SAFE_MESH_SKELETON={mesh_skel_path}")
print(f"ASWW_SAFE_ABP_SKELETON={abp_skel_path}")
print(f"ASWW_SAFE_MANNY_COMPATIBLE={compatible}")

for path in (
    "/ACLPlugin/ACLAnimCurveCompressionSettings",
    "/ControlRig/Controls/ControlRigGizmoMaterial",
):
    obj = unreal.EditorAssetLibrary.load_asset(path)
    print(f"ASWW_SAFE_PLUGIN_ASSET|{path}|LOAD={obj is not None}")
'@

[IO.File]::WriteAllText($PyFile, $Python, [Text.UTF8Encoding]::new($false))
$PyForward = $PyFile.Replace('\','/')

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SAFE PROJECT-ARG UNREAL VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "NOTE=Using direct PowerShell call operator so the .uproject path with spaces stays one argument." -ForegroundColor Yellow

$Args = @(
    $ProjectFile
    "-unattended"
    "-nop4"
    "-nosplash"
    "-NullRHI"
    "-stdout"
    "-FullStdOutLogOutput"
    "-ExecutePythonScript=$PyForward"
)

# IMPORTANT: direct invocation preserves the project path as a single argument.
& $EditorCmd @Args 1> $StdOut 2> $StdErr
$VerifyExit = $LASTEXITCODE

Write-Host "SAFE_UNREAL_EDITOR_CMD_EXIT=$VerifyExit"

$VerifyText = ""
if (Test-Path -LiteralPath $StdOut) {
    $VerifyText += Get-Content -Raw -LiteralPath $StdOut
    Select-String -LiteralPath $StdOut -Pattern "ASWW_SAFE_" |
        ForEach-Object { Write-Host $_.Line }
}
if (Test-Path -LiteralPath $StdErr) {
    $VerifyText += "`n" + (Get-Content -Raw -LiteralPath $StdErr)
}

$ProjectRootForward = ($ProjectRoot.Replace('\','/').TrimEnd('/') + '/')
$ProjectDirPass =
    $VerifyText.Replace('\','/').Contains("ASWW_SAFE_PROJECT_DIR=$ProjectRootForward")

$MeshLoadPass = $VerifyText -match "ASWW_SAFE_MESH_LOAD=True"
$ABPLoadPass = $VerifyText -match "ASWW_SAFE_ABP_LOAD=True"
$CompatPass = $VerifyText -match "ASWW_SAFE_MANNY_COMPATIBLE=True"
$ACLPass = $VerifyText -match 'ASWW_SAFE_PLUGIN_ASSET\|/ACLPlugin/ACLAnimCurveCompressionSettings\|LOAD=True'
$ControlRigPass = $VerifyText -match 'ASWW_SAFE_PLUGIN_ASSET\|/ControlRig/Controls/ControlRigGizmoMaterial\|LOAD=True'
$PythonError = $VerifyText -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$Fatal = $VerifyText -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

Write-Host ""
Write-Host "SAFE_PROJECT_DIR_MATCH=$ProjectDirPass"
Write-Host "SAFE_MANNY_MESH_LOAD_PASS=$MeshLoadPass"
Write-Host "SAFE_MANNY_ABP_LOAD_PASS=$ABPLoadPass"
Write-Host "SAFE_MANNY_COMPATIBILITY_PASS=$CompatPass"
Write-Host "SAFE_ACL_LOAD_PASS=$ACLPass"
Write-Host "SAFE_CONTROLRIG_LOAD_PASS=$ControlRigPass"
Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "FATAL_ERROR_SEEN=$Fatal"

if ($VerifyExit -ne 0 -or $PythonError -or $Fatal) {
    Stop-Gate "SAFE_UNREAL_VERIFY_PROCESS_FAILED" $(if ($VerifyExit -gt 0) { $VerifyExit } else { 20 })
}

if (-not $ProjectDirPass) {
    Stop-Gate "UNREAL_DID_NOT_OPEN_ASWW_PROJECT_EVEN_WITH_SAFE_ARGUMENT_PASSING" 21
}

if (-not $MeshLoadPass -or -not $ABPLoadPass -or -not $CompatPass) {
    Write-Host ""
    Write-Host "SAFEARG_DIAGNOSIS=ASWW_PROJECT_IS_LOADED_BUT_COPIED_PACKAGES_ARE_NOT_DISCOVERABLE_OR_LOADABLE" -ForegroundColor Red
    Write-Host "NEXT_GATE=USE_UNREAL_ASSETTOOLS_MIGRATION_FROM_TEMPLATE_INSTEAD_OF_RAW_FILE_COPY" -ForegroundColor Yellow
    Stop-Gate "COPIED_MANNY_PACKAGES_NOT_LOADABLE_AFTER_FORCE_SCAN" 22
}

if (-not $ACLPass -or -not $ControlRigPass) {
    Stop-Gate "REQUIRED_PLUGIN_ASSET_LOAD_REGRESSED" 23
}

Write-Host ""
Write-Host "SAFEARG_MANNY_VERIFY=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=PATCH_ASCHARACTER_AND_PACKAGE" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PATCH ASCHARACTER: REMOVE CUBE, ASSIGN REAL MANNY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\RealMannySafeArgBackup_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
Copy-Item -LiteralPath $CharacterCpp -Destination (Join-Path $BackupRoot "ASCharacter.cpp") -Force
Write-Host "ASCHARACTER_BACKUP=$BackupRoot"

$Text = Get-Content -Raw -LiteralPath $CharacterCpp

if ($Text -match 'ASWW_REAL_PLAYER_MANNY') {
    Stop-Gate "REAL_MANNY_PATCH_ALREADY_PRESENT_REVIEW_BEFORE_REAPPLY" 30
}

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

foreach ($Inc in @(
    '#include "Components/SkeletalMeshComponent.h"',
    '#include "Engine/SkeletalMesh.h"',
    '#include "Animation/AnimInstance.h"',
    '#include "UObject/ConstructorHelpers.h"'
)) {
    if (-not $Text.Contains($Inc)) {
        $Text = $Text.Replace($IncludeAnchor, $IncludeAnchor + [Environment]::NewLine + $Inc)
    }
}

$AttachRx = [regex]::new(
    'FollowCamera->SetupAttachment\s*\(\s*CameraBoom\s*,\s*USpringArmComponent::SocketName\s*\)\s*;',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

if (-not $AttachRx.IsMatch($Text)) {
    Stop-Gate "FOLLOW_CAMERA_ATTACHMENT_PATTERN_NOT_FOUND" 33
}

$MannyBlock = @'

    static ConstructorHelpers::FObjectFinder<USkeletalMesh> PlayerMeshAsset(
        TEXT("/Game/Characters/Mannequins/Meshes/SKM_Manny_Simple.SKM_Manny_Simple"));
    if (PlayerMeshAsset.Succeeded())
    {
        GetMesh()->SetSkeletalMeshAsset(PlayerMeshAsset.Object);
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
$RealMarker = $Patched.Contains("ASWW_REAL_PLAYER_MANNY")
$CubeStillPresent = $Patched.Contains("ASWW_VISUAL_PROOF") -or $Patched.Contains("ASWW_PlayerVisualProof")

Write-Host "REAL_MANNY_MARKER_PRESENT=$RealMarker"
Write-Host "TEMP_CUBE_STILL_PRESENT=$CubeStillPresent"

if (-not $RealMarker -or $CubeStillPresent) {
    Stop-Gate "ASCHARACTER_REAL_MANNY_PATCH_VERIFY_FAILED" 34
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 35
}

Write-Host ""
Write-Host "REAL_MANNY_SOURCE_INTEGRATION=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=BUILD_COOK_PACKAGE" -ForegroundColor Green

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
Write-Host "REAL_MANNY_SAFEARG_V3=PASS" -ForegroundColor Green
Write-Host "REAL_MANNY_PACKAGE=PASS" -ForegroundColor Green
Write-Host "PACKAGED_EXE=$PackagedExe" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_REAL_MANNY_PACKAGED_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
