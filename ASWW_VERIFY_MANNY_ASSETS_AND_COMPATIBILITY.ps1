[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\MannyAssetVerify"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "MANNY_ASSET_VERIFY=STOPPED" -ForegroundColor Red
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

$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"

if (-not (Test-Path -LiteralPath $ProjectFile -PathType Leaf)) {
    Stop-Gate "UPROJECT_NOT_FOUND" 11
}
if (-not (Test-Path -LiteralPath $EditorCmd -PathType Leaf)) {
    Stop-Gate "UNREALEDITOR_CMD_NOT_FOUND" 12
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$PyFile = Join-Path $EvidenceRoot "verify_manny_assets_$Stamp.py"
$StdOut = Join-Path $EvidenceRoot "verify_manny_assets_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "verify_manny_assets_$Stamp.stderr.log"

$Python = @'
import unreal

pairs = [
    (
        "MOVER_TESTS_FULL",
        "/MoverTests/Characters/Mannequins/Meshes/SKM_Manny",
        "/MoverTests/Characters/Mannequins/Animations/ABP_Manny"
    ),
    (
        "MOVER_TESTS_SIMPLE",
        "/MoverTests/Characters/Mannequins/Meshes/SKM_Manny_Simple",
        "/MoverTests/Characters/Mannequins/Animations/ABP_Manny"
    ),
    (
        "MOVER_EXAMPLES_SIMPLE",
        "/MoverExamples/Characters/Mannequins/Meshes/SKM_Manny_Simple",
        "/MoverExamples/Characters/Mannequins/Animations/ABP_Manny"
    ),
]

def safe_path(obj):
    try:
        return obj.get_path_name() if obj else "NONE"
    except Exception:
        return "ERROR"

def get_skeleton_from_mesh(mesh):
    for prop in ("skeleton",):
        try:
            value = mesh.get_editor_property(prop)
            if value:
                return value
        except Exception:
            pass
    try:
        return mesh.skeleton
    except Exception:
        return None

def get_target_skeleton_from_abp(abp):
    for prop in ("target_skeleton", "skeleton"):
        try:
            value = abp.get_editor_property(prop)
            if value:
                return value
        except Exception:
            pass
    return None

print("=== ASWW MANNY ASSET VERIFICATION ===")

best = None

for label, mesh_path, abp_path in pairs:
    mesh_exists = unreal.EditorAssetLibrary.does_asset_exist(mesh_path)
    abp_exists = unreal.EditorAssetLibrary.does_asset_exist(abp_path)

    mesh = unreal.EditorAssetLibrary.load_asset(mesh_path) if mesh_exists else None
    abp = unreal.EditorAssetLibrary.load_asset(abp_path) if abp_exists else None

    mesh_class = mesh.get_class().get_name() if mesh else "NONE"
    abp_class = abp.get_class().get_name() if abp else "NONE"

    mesh_skel = get_skeleton_from_mesh(mesh) if mesh else None
    abp_skel = get_target_skeleton_from_abp(abp) if abp else None

    mesh_skel_path = safe_path(mesh_skel)
    abp_skel_path = safe_path(abp_skel)

    compatible = (
        mesh is not None
        and abp is not None
        and mesh_skel is not None
        and abp_skel is not None
        and mesh_skel_path == abp_skel_path
    )

    mesh_is_skeletal = mesh_class == "SkeletalMesh"
    abp_is_anim_bp = abp_class == "AnimBlueprint"

    print(f"PAIR={label}")
    print(f"MESH_PATH={mesh_path}")
    print(f"MESH_EXISTS={mesh_exists}")
    print(f"MESH_LOAD={mesh is not None}")
    print(f"MESH_CLASS={mesh_class}")
    print(f"MESH_IS_SKELETAL={mesh_is_skeletal}")
    print(f"MESH_SKELETON={mesh_skel_path}")
    print(f"ABP_PATH={abp_path}")
    print(f"ABP_EXISTS={abp_exists}")
    print(f"ABP_LOAD={abp is not None}")
    print(f"ABP_CLASS={abp_class}")
    print(f"ABP_IS_ANIM_BLUEPRINT={abp_is_anim_bp}")
    print(f"ABP_TARGET_SKELETON={abp_skel_path}")
    print(f"SKELETON_COMPATIBLE={compatible}")
    print("---")

    if best is None and mesh_is_skeletal and abp_is_anim_bp and compatible:
        best = (label, mesh_path, abp_path, mesh_skel_path)

if best:
    print(f"BEST_PAIR={best[0]}")
    print(f"BEST_MESH={best[1]}")
    print(f"BEST_ANIM_BP={best[2]}")
    print(f"BEST_SKELETON={best[3]}")
    print("MANNY_ASSET_COMPATIBILITY=PASS")
else:
    print("BEST_PAIR=NONE")
    print("MANNY_ASSET_COMPATIBILITY=FAIL")

print("NO_ASSETS_WERE_MODIFIED=TRUE")
'@

[IO.File]::WriteAllText($PyFile, $Python, [Text.UTF8Encoding]::new($false))
$PyForward = $PyFile.Replace('\','/')

Write-Host "PYTHON_VERIFY_SCRIPT=$PyFile"
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RUN UNREAL ASSET VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Args = @(
    $ProjectFile,
    "-unattended",
    "-nop4",
    "-nosplash",
    "-NullRHI",
    "-stdout",
    "-FullStdOutLogOutput",
    "-ExecutePythonScript=$PyForward"
)

$Proc = Start-Process `
    -FilePath $EditorCmd `
    -ArgumentList $Args `
    -WorkingDirectory $ProjectRoot `
    -PassThru `
    -Wait `
    -RedirectStandardOutput $StdOut `
    -RedirectStandardError $StdErr

$Exit = $Proc.ExitCode
Write-Host "UNREAL_EDITOR_CMD_EXIT=$Exit"

$Out = if (Test-Path -LiteralPath $StdOut) { Get-Content -Raw -LiteralPath $StdOut } else { "" }
$Err = if (Test-Path -LiteralPath $StdErr) { Get-Content -Raw -LiteralPath $StdErr } else { "" }
$Text = $Out + "`n" + $Err

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " MANNY ASSET CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Lines = @($Text -split "`r?`n" | Where-Object {
    $_ -match '^(PAIR|MESH_PATH|MESH_EXISTS|MESH_LOAD|MESH_CLASS|MESH_IS_SKELETAL|MESH_SKELETON|ABP_PATH|ABP_EXISTS|ABP_LOAD|ABP_CLASS|ABP_IS_ANIM_BLUEPRINT|ABP_TARGET_SKELETON|SKELETON_COMPATIBLE|BEST_PAIR|BEST_MESH|BEST_ANIM_BP|BEST_SKELETON|MANNY_ASSET_COMPATIBILITY|NO_ASSETS_WERE_MODIFIED)='
})

foreach ($Line in $Lines) { Write-Host $Line }

$PythonError = $Text -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)|PythonScriptPlugin.*Error"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$CompatPass = $Text -match "MANNY_ASSET_COMPATIBILITY=PASS"

Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "FATAL_ERROR_SEEN=$Fatal"

if ($Exit -ne 0 -or $PythonError -or $Fatal) {
    Write-Host ""
    Write-Host "=== FAILURE TAIL ===" -ForegroundColor Yellow
    if (Test-Path -LiteralPath $StdOut) { Get-Content -LiteralPath $StdOut -Tail 180 }
    Stop-Gate "UNREAL_ASSET_VERIFY_FAILED" $(if ($Exit -gt 0) { $Exit } else { 20 })
}

if (-not $CompatPass) {
    Write-Host "MANNY_ASSET_VERIFY=FAIL_NO_COMPATIBLE_PAIR" -ForegroundColor Red
    Write-Host "NEXT_GATE=IMPORT_OR_COPY_COMPATIBLE_CHARACTER_ASSETS" -ForegroundColor Yellow
    Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit 30
}

Write-Host ""
Write-Host "MANNY_ASSET_VERIFY=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=INTEGRATE_SELECTED_MANNY_MESH_AND_ANIM_BP_THEN_REAL_PACKAGE_QA" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "KEEP_TEMP_VISUAL_PROOF_UNTIL_REAL_MESH_PACKAGE_PASSES" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_VISUAL_PROOF_OR_TELEMETRY" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
