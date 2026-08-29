[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\RealMannyV4"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "REAL_MANNY_V4=STOPPED" -ForegroundColor Red
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

Write-Host "MANNY_MESH_FILE_PRESENT=$(Test-Path -LiteralPath $MeshFile -PathType Leaf)"
Write-Host "MANNY_ABP_FILE_PRESENT=$(Test-Path -LiteralPath $AnimFile -PathType Leaf)"

if (-not (Test-Path -LiteralPath $MeshFile -PathType Leaf) -or
    -not (Test-Path -LiteralPath $AnimFile -PathType Leaf)) {
    Stop-Gate "IMPORTED_MANNY_PRIMARY_FILES_MISSING" 12
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$SessionRoot = Join-Path $EvidenceRoot $Stamp
New-Item -ItemType Directory -Force -Path $SessionRoot | Out-Null

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REVERIFY ASWW PROJECT + MANNY WITH ABSOLUTE PATH NORMALIZATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$PyFile = Join-Path $SessionRoot "verify_asww_manny_v4.py"
$StdOut = Join-Path $SessionRoot "verify_asww_manny_v4.stdout.log"
$StdErr = Join-Path $SessionRoot "verify_asww_manny_v4.stderr.log"

$Python = @'
import unreal
import os

expected_root = os.environ.get("ASWW_EXPECTED_PROJECT_ROOT", "")

def norm(p):
    return os.path.normcase(os.path.normpath(p))

project_dir_rel = unreal.Paths.project_dir()
project_dir_abs = unreal.Paths.convert_relative_path_to_full(project_dir_rel)
content_dir_abs = unreal.Paths.convert_relative_path_to_full(unreal.Paths.project_content_dir())

project_match = bool(expected_root) and norm(project_dir_abs).rstrip("\\/") == norm(expected_root).rstrip("\\/")

registry = unreal.AssetRegistryHelpers.get_asset_registry()
try:
    registry.search_all_assets(True)
except Exception:
    pass

try:
    registry.scan_paths_synchronous(["/Game/Characters"], True)
except Exception:
    pass

try:
    game_assets = registry.get_assets_by_path("/Game", recursive=True)
    game_count = len(game_assets)
except Exception:
    game_count = -1

mesh_path = "/Game/Characters/Mannequins/Meshes/SKM_Manny_Simple"
abp_path = "/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed"

mesh = unreal.EditorAssetLibrary.load_asset(mesh_path)
abp = unreal.EditorAssetLibrary.load_asset(abp_path)

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

acl = unreal.EditorAssetLibrary.load_asset("/ACLPlugin/ACLAnimCurveCompressionSettings")
cr = unreal.EditorAssetLibrary.load_asset("/ControlRig/Controls/ControlRigGizmoMaterial")

print(f"ASWW_V4_PROJECT_DIR_REL={project_dir_rel}")
print(f"ASWW_V4_PROJECT_DIR_ABS={project_dir_abs}")
print(f"ASWW_V4_CONTENT_DIR_ABS={content_dir_abs}")
print(f"ASWW_V4_PROJECT_MATCH={project_match}")
print(f"ASWW_V4_GAME_ASSET_COUNT={game_count}")
print(f"ASWW_V4_MESH_LOAD={mesh is not None}")
print(f"ASWW_V4_MESH_CLASS={mesh_cls}")
print(f"ASWW_V4_ABP_LOAD={abp is not None}")
print(f"ASWW_V4_ABP_CLASS={abp_cls}")
print(f"ASWW_V4_MESH_SKELETON={mesh_skel_path}")
print(f"ASWW_V4_ABP_SKELETON={abp_skel_path}")
print(f"ASWW_V4_MANNY_COMPATIBLE={compatible}")
print(f"ASWW_V4_ACL_LOAD={acl is not None}")
print(f"ASWW_V4_CONTROLRIG_LOAD={cr is not None}")
'@

[IO.File]::WriteAllText($PyFile, $Python, [Text.UTF8Encoding]::new($false))
$PyForward = $PyFile.Replace('\','/')
$env:ASWW_EXPECTED_PROJECT_ROOT = $ProjectRoot

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

& $EditorCmd @Args 1> $StdOut 2> $StdErr
$VerifyExit = $LASTEXITCODE
Remove-Item Env:\ASWW_EXPECTED_PROJECT_ROOT -ErrorAction SilentlyContinue

Write-Host "UNREAL_VERIFY_EXIT=$VerifyExit"

$VerifyText = ""
if (Test-Path -LiteralPath $StdOut) {
    $VerifyText += Get-Content -Raw -LiteralPath $StdOut
    Select-String -LiteralPath $StdOut -Pattern "ASWW_V4_" |
        ForEach-Object { Write-Host $_.Line }
}
if (Test-Path -LiteralPath $StdErr) {
    $VerifyText += "`n" + (Get-Content -Raw -LiteralPath $StdErr)
}

$ProjectMatch = $VerifyText -match "ASWW_V4_PROJECT_MATCH=True"
$MeshLoad = $VerifyText -match "ASWW_V4_MESH_LOAD=True"
$ABPLoad = $VerifyText -match "ASWW_V4_ABP_LOAD=True"
$Compat = $VerifyText -match "ASWW_V4_MANNY_COMPATIBLE=True"
$ACL = $VerifyText -match "ASWW_V4_ACL_LOAD=True"
$ControlRig = $VerifyText -match "ASWW_V4_CONTROLRIG_LOAD=True"
$PythonError = $VerifyText -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$Fatal = $VerifyText -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

Write-Host "PROJECT_MATCH=$ProjectMatch"
Write-Host "MANNY_MESH_LOAD=$MeshLoad"
Write-Host "MANNY_ABP_LOAD=$ABPLoad"
Write-Host "MANNY_COMPATIBILITY=$Compat"
Write-Host "ACL_LOAD=$ACL"
Write-Host "CONTROLRIG_LOAD=$ControlRig"
Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "FATAL_ERROR_SEEN=$Fatal"

if ($VerifyExit -ne 0 -or $PythonError -or $Fatal) {
    Stop-Gate "UNREAL_REVERIFY_PROCESS_FAILED" $(if ($VerifyExit -gt 0) { $VerifyExit } else { 20 })
}

if (-not $ProjectMatch -or -not $MeshLoad -or -not $ABPLoad -or -not $Compat -or -not $ACL -or -not $ControlRig) {
    Stop-Gate "REAL_MANNY_REVERIFY_FAILED" 21
}

Write-Host ""
Write-Host "REAL_MANNY_REVERIFY=PASS" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PATCH ASCHARACTER: TEMP CUBE -> REAL MANNY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\RealMannyV4Backup_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
Copy-Item -LiteralPath $CharacterCpp -Destination (Join-Path $BackupRoot "ASCharacter.cpp") -Force
Write-Host "ASCHARACTER_BACKUP=$BackupRoot"

$Text = Get-Content -Raw -LiteralPath $CharacterCpp

if ($Text -match 'ASWW_REAL_PLAYER_MANNY') {
    Write-Host "REAL_MANNY_PATCH_ALREADY_PRESENT=True" -ForegroundColor Yellow
}
else {
    $ProofPattern = '(?s)\s*// TEMPORARY QA VISUAL ONLY\. Do not commit as final player art\..*?UE_LOG\(LogTemp,\s*Warning,\s*TEXT\("ASWW_VISUAL_PROOF component=%s mesh=%s"\),\s*\*GetNameSafe\(VisualProof\),\s*\*GetNameSafe\(VisualProof->GetStaticMesh\(\)\)\s*\);\s*'
    $ProofRx = [regex]::new($ProofPattern)

    if ($ProofRx.IsMatch($Text)) {
        $Text = $ProofRx.Replace($Text, [Environment]::NewLine, 1)
        Write-Host "TEMP_CUBE_BLOCK_REMOVED=True" -ForegroundColor Green
    }
    elseif ($Text -match 'ASWW_VISUAL_PROOF|ASWW_PlayerVisualProof') {
        Stop-Gate "TEMP_CUBE_PRESENT_BUT_SAFE_REGEX_DID_NOT_MATCH" 30
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
        Stop-Gate "CAMERA_INCLUDE_ANCHOR_NOT_FOUND" 31
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
        Stop-Gate "FOLLOW_CAMERA_ATTACHMENT_PATTERN_NOT_FOUND" 32
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
}

$Patched = Get-Content -Raw -LiteralPath $CharacterCpp

$RealMarker = $Patched.Contains("ASWW_REAL_PLAYER_MANNY")
$MeshPathPresent = $Patched.Contains("/Game/Characters/Mannequins/Meshes/SKM_Manny_Simple.SKM_Manny_Simple")
$AnimPathPresent = $Patched.Contains("/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed")
$CubeStillPresent = $Patched.Contains("ASWW_VISUAL_PROOF") -or $Patched.Contains("ASWW_PlayerVisualProof")

Write-Host "REAL_MANNY_MARKER_PRESENT=$RealMarker"
Write-Host "REAL_MANNY_MESH_PATH_PRESENT=$MeshPathPresent"
Write-Host "REAL_MANNY_ABP_PATH_PRESENT=$AnimPathPresent"
Write-Host "TEMP_CUBE_STILL_PRESENT=$CubeStillPresent"

if (-not $RealMarker -or -not $MeshPathPresent -or -not $AnimPathPresent -or $CubeStillPresent) {
    Stop-Gate "ASCHARACTER_REAL_MANNY_PATCH_VERIFY_FAILED" 33
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 34
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
Write-Host "REAL_MANNY_V4=PASS" -ForegroundColor Green
Write-Host "REAL_MANNY_PACKAGE=PASS" -ForegroundColor Green
Write-Host "PACKAGED_EXE=$PackagedExe" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_REAL_MANNY_PACKAGED_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
