[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$StageRoot = "D:\ASWW_STAGE"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "TP_RIFLE_TACTICAL_INTEGRATION=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Read-AssetStrings([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Asset file not found: $Path"
    }
    $Bytes = [IO.File]::ReadAllBytes($Path)
    return ([Text.Encoding]::ASCII.GetString($Bytes) + "`n" + [Text.Encoding]::Unicode.GetString($Bytes))
}

Set-Location $ProjectRoot
$env:GIT_PAGER = "cat"

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

$ProjectFile  = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$EditorCmd    = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$BuildScript  = Join-Path $ProjectRoot "BuildScripts\build_win64.ps1"
$CharacterCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"

$ShooterContentRoot = Join-Path $UERoot "Templates\TemplateResources\Standard\Variant_Shooter\Content"
$SourceABP = Join-Path $ShooterContentRoot "Anims\ABP_TP_Rifle.uasset"

foreach ($Required in @($ProjectFile,$EditorCmd,$BuildScript,$CharacterCpp,$ShooterContentRoot,$SourceABP)) {
    if (-not (Test-Path -LiteralPath $Required)) {
        Stop-Gate "MISSING_REQUIRED_PATH_$Required" 11
    }
}

$Original = Get-Content -Raw -LiteralPath $CharacterCpp

if ($Original -notmatch "ASWW_REAL_PLAYER_MANNY") {
    Stop-Gate "REAL_MANNY_MARKER_NOT_FOUND" 12
}
if ($Original -notmatch "ASWW_REAL_RIFLE_VISUAL_BEGIN") {
    Stop-Gate "REAL_RIFLE_VISUAL_BLOCK_NOT_FOUND" 13
}
if ($Original -match "ASWW_TP_RIFLE_TACTICAL_BEGIN") {
    Stop-Gate "TP_RIFLE_TACTICAL_ALREADY_PRESENT" 14
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SELECT THIRD-PERSON RIFLE ABP (NOT FIRST-PERSON)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Strings = Read-AssetStrings $SourceABP
$PathHints = @(
    [regex]::Matches($Strings, '/Game/[A-Za-z0-9_./-]*ABP_TP_Rifle') |
    ForEach-Object { $_.Value.TrimEnd([char]0,'.') } |
    Sort-Object -Unique
)

$InternalABPPath = $PathHints | Select-Object -First 1
if (-not $InternalABPPath) {
    Write-Host "ABP_TP_RIFLE_INTERNAL_PATH_HINT=NOT_FOUND"
    Stop-Gate "CANNOT_INFER_ABP_TP_RIFLE_INTERNAL_PACKAGE_PATH" 20
}

Write-Host "ABP_TP_RIFLE_INTERNAL_PATH_HINT=$InternalABPPath"

# Infer package prefix before /Anims/ABP_TP_Rifle.
$M = [regex]::Match($InternalABPPath, '^/Game/(.*?)(?:Anims/ABP_TP_Rifle)$')
if (-not $M.Success) {
    Stop-Gate "UNEXPECTED_ABP_TP_RIFLE_INTERNAL_PATH_$InternalABPPath" 21
}

$PackagePrefix = $M.Groups[1].Value.Trim('/')

if ([string]::IsNullOrWhiteSpace($PackagePrefix)) {
    $DestVariantRoot = Join-Path $ProjectRoot "Content"
    $ABPObjectPath = "/Game/Anims/ABP_TP_Rifle.ABP_TP_Rifle"
    $ABPPackagePath = "/Game/Anims/ABP_TP_Rifle"
}
else {
    $PrefixWin = $PackagePrefix.Replace('/','\')
    $DestVariantRoot = Join-Path $ProjectRoot ("Content\" + $PrefixWin)
    $ABPObjectPath = ("/Game/$PackagePrefix/Anims/ABP_TP_Rifle.ABP_TP_Rifle" -replace '//','/')
    $ABPPackagePath = ("/Game/$PackagePrefix/Anims/ABP_TP_Rifle" -replace '//','/')
}

Write-Host "VARIANT_SHOOTER_PACKAGE_PREFIX=$PackagePrefix"
Write-Host "VARIANT_SHOOTER_DEST_ROOT=$DestVariantRoot"
Write-Host "TP_RIFLE_ABP_OBJECT_PATH=$ABPObjectPath"
Write-Host "TP_RIFLE_ABP_PACKAGE_PATH=$ABPPackagePath"

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\TPRifleTacticalIntegration_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
Copy-Item -LiteralPath $CharacterCpp -Destination (Join-Path $BackupRoot "ASCharacter.cpp.before_tp_rifle") -Force

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COPY VARIANT_SHOOTER CONTENT WITHOUT OVERWRITING COLLISIONS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Manifest = Join-Path $BackupRoot "created_files.txt"
$Created = New-Object System.Collections.Generic.List[string]
$SkippedSame = 0

$SourceFiles = @(
    Get-ChildItem -LiteralPath $ShooterContentRoot -Recurse -File -ErrorAction Stop
)

Write-Host "VARIANT_SHOOTER_SOURCE_FILE_COUNT=$($SourceFiles.Count)"

foreach ($Source in $SourceFiles) {
    $Rel = $Source.FullName.Substring($ShooterContentRoot.Length).TrimStart('\','/')
    $Dest = Join-Path $DestVariantRoot $Rel
    $DestDir = Split-Path -Parent $Dest
    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

    if (Test-Path -LiteralPath $Dest -PathType Leaf) {
        $SrcHash = (Get-FileHash -LiteralPath $Source.FullName -Algorithm SHA256).Hash
        $DstHash = (Get-FileHash -LiteralPath $Dest -Algorithm SHA256).Hash

        if ($SrcHash -eq $DstHash) {
            $SkippedSame++
            continue
        }

        Stop-Gate "COLLISION_WITH_DIFFERENT_EXISTING_FILE_$Dest" 22
    }

    Copy-Item -LiteralPath $Source.FullName -Destination $Dest
    $Created.Add($Dest)
}

$Created | Set-Content -LiteralPath $Manifest -Encoding UTF8

Write-Host "VARIANT_SHOOTER_CREATED_FILE_COUNT=$($Created.Count)"
Write-Host "VARIANT_SHOOTER_IDENTICAL_EXISTING_FILE_COUNT=$SkippedSame"
Write-Host "CREATED_FILE_MANIFEST=$Manifest"

$ExpectedImportedABP = if ([string]::IsNullOrWhiteSpace($PackagePrefix)) {
    Join-Path $ProjectRoot "Content\Anims\ABP_TP_Rifle.uasset"
} else {
    Join-Path $ProjectRoot ("Content\" + $PackagePrefix.Replace('/','\') + "\Anims\ABP_TP_Rifle.uasset")
}

Write-Host "IMPORTED_TP_RIFLE_ABP_FILE_EXISTS=$(Test-Path -LiteralPath $ExpectedImportedABP -PathType Leaf)"
if (-not (Test-Path -LiteralPath $ExpectedImportedABP -PathType Leaf)) {
    Stop-Gate "IMPORTED_ABP_TP_RIFLE_FILE_NOT_FOUND" 23
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY ABP SKELETON + SOCKETS INSIDE UNREAL" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\TPRifleTacticalVerify"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

$Py = Join-Path $EvidenceRoot "verify_tp_rifle_tactical_$Stamp.py"
$Out = Join-Path $EvidenceRoot "verify_tp_rifle_tactical_$Stamp.stdout.log"
$Err = Join-Path $EvidenceRoot "verify_tp_rifle_tactical_$Stamp.stderr.log"

$PyText = @"
import unreal

MANNY = "/Game/Characters/Mannequins/Meshes/SKM_Manny_Simple.SKM_Manny_Simple"
ABP = r"$ABPObjectPath"

registry = unreal.AssetRegistryHelpers.get_asset_registry()
registry.scan_paths_synchronous(["/Game"], True)

mesh = unreal.load_asset(MANNY)
abp = unreal.load_asset(ABP)

print(f"ASWW_TP_RIFLE_MANNY_LOAD={mesh is not None}")
print(f"ASWW_TP_RIFLE_ABP_LOAD={abp is not None}")
print(f"ASWW_TP_RIFLE_ABP_CLASS={abp.get_class().get_name() if abp else 'NONE'}")

if not mesh or not abp:
    raise RuntimeError("Manny or ABP_TP_Rifle failed to load")

manny_skel = mesh.get_editor_property("skeleton")
try:
    target_skel = abp.get_editor_property("target_skeleton")
except Exception:
    target_skel = None

print(f"ASWW_TP_RIFLE_MANNY_SKELETON={manny_skel.get_path_name() if manny_skel else 'NONE'}")
print(f"ASWW_TP_RIFLE_TARGET_SKELETON={target_skel.get_path_name() if target_skel else 'NONE'}")
print(f"ASWW_TP_RIFLE_SAME_SKELETON={bool(manny_skel and target_skel and manny_skel.get_path_name() == target_skel.get_path_name())}")

# Compile if this UE Python build exposes KismetEditorUtilities.
compile_supported = hasattr(unreal, "KismetEditorUtilities")
print(f"ASWW_TP_RIFLE_COMPILE_API_AVAILABLE={compile_supported}")
if compile_supported:
    try:
        unreal.KismetEditorUtilities.compile_blueprint(abp)
        print("ASWW_TP_RIFLE_COMPILE_ATTEMPT=PASS")
    except Exception as exc:
        print(f"ASWW_TP_RIFLE_COMPILE_ATTEMPT=FAIL:{exc}")

comp = unreal.new_object(unreal.SkeletalMeshComponent)
try:
    comp.set_skeletal_mesh_asset(mesh)
except Exception:
    comp.set_skeletal_mesh(mesh)

names = [str(x) for x in comp.get_all_socket_names()]
lower = {x.lower() for x in names}

for n in ("hand_r","hand_l","ik_hand_gun","ik_hand_r","ik_hand_l","HandGrip_R","HandGrip_L","weapon_r_muzzle"):
    print(f"ASWW_TP_RIFLE_NAME_{n.upper()}={n.lower() in lower}")

# Distinguish actual sockets from bones using SkeletalMesh.find_socket.
for n in ("HandGrip_R","HandGrip_L","weapon_r_muzzle","hand_r","ik_hand_gun"):
    socket = None
    try:
        socket = mesh.find_socket(n)
    except Exception as exc:
        print(f"ASWW_TP_RIFLE_FIND_SOCKET_ERROR|NAME={n}|ERR={exc}")

    print(f"ASWW_TP_RIFLE_ACTUAL_SOCKET|NAME={n}|FOUND={socket is not None}")
    if socket:
        try:
            bone = socket.get_editor_property("bone_name")
        except Exception:
            bone = "UNKNOWN"
        try:
            loc = socket.get_editor_property("relative_location")
            rot = socket.get_editor_property("relative_rotation")
            scale = socket.get_editor_property("relative_scale")
            print(
                f"ASWW_TP_RIFLE_SOCKET_TRANSFORM|NAME={n}|BONE={bone}|"
                f"LOC={loc}|ROT={rot}|SCALE={scale}"
            )
        except Exception as exc:
            print(f"ASWW_TP_RIFLE_SOCKET_TRANSFORM_ERROR|NAME={n}|ERR={exc}")

# Inspect ABP package dependencies if API is available.
try:
    opts = unreal.AssetRegistryDependencyOptions(
        include_soft_package_references=True,
        include_hard_package_references=True,
        include_searchable_names=False,
        include_soft_management_references=False,
        include_hard_management_references=False
    )
    deps = registry.get_dependencies(r"$ABPPackagePath", opts)
    print(f"ASWW_TP_RIFLE_ABP_DEPENDENCY_COUNT={len(deps)}")
    for d in deps[:200]:
        print(f"ASWW_TP_RIFLE_ABP_DEP={d}")
except Exception as exc:
    print(f"ASWW_TP_RIFLE_DEPENDENCY_ENUM=UNAVAILABLE:{exc}")

print("ASWW_TP_RIFLE_VERIFY_DONE=True")
"@

[IO.File]::WriteAllText($Py, $PyText, [Text.UTF8Encoding]::new($false))
$PyForward = $Py.Replace('\','/')

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

& $EditorCmd @Args 1> $Out 2> $Err
$VerifyExit = $LASTEXITCODE

$Combined = ""
if (Test-Path -LiteralPath $Out) {
    $Combined += Get-Content -Raw -LiteralPath $Out
    Select-String -LiteralPath $Out -Pattern "ASWW_TP_RIFLE_" |
        ForEach-Object { Write-Host $_.Line }
}
if (Test-Path -LiteralPath $Err) {
    $Combined += "`n" + (Get-Content -Raw -LiteralPath $Err)
}

$PythonError = $Combined -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$Fatal = $Combined -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

Write-Host "TP_RIFLE_VERIFY_EDITOR_EXIT=$VerifyExit"
Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "FATAL_ERROR_SEEN=$Fatal"

if ($VerifyExit -ne 0 -or $PythonError -or $Fatal) {
    Stop-Gate "TP_RIFLE_UNREAL_VERIFY_FAILED" $(if ($VerifyExit -gt 0) { $VerifyExit } else { 30 })
}

$ABPLoad = $Combined -match "ASWW_TP_RIFLE_ABP_LOAD=True"
$ABPClass = $Combined -match "ASWW_TP_RIFLE_ABP_CLASS=AnimBlueprint"
$SameSkeleton = $Combined -match "ASWW_TP_RIFLE_SAME_SKELETON=True"
$HandGripRSocket = $Combined -match "ASWW_TP_RIFLE_ACTUAL_SOCKET\|NAME=HandGrip_R\|FOUND=True"
$HandGripLSocket = $Combined -match "ASWW_TP_RIFLE_ACTUAL_SOCKET\|NAME=HandGrip_L\|FOUND=True"
$IKGun = $Combined -match "ASWW_TP_RIFLE_NAME_IK_HAND_GUN=True"
$IKLeft = $Combined -match "ASWW_TP_RIFLE_NAME_IK_HAND_L=True"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFIED TACTICAL PREREQUISITES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TP_RIFLE_ABP_LOAD=$ABPLoad"
Write-Host "TP_RIFLE_ABP_IS_ANIMBLUEPRINT=$ABPClass"
Write-Host "TP_RIFLE_ABP_SAME_MANNY_SKELETON=$SameSkeleton"
Write-Host "HANDGRIP_R_ACTUAL_SOCKET=$HandGripRSocket"
Write-Host "HANDGRIP_L_ACTUAL_SOCKET=$HandGripLSocket"
Write-Host "IK_HAND_GUN_AVAILABLE=$IKGun"
Write-Host "IK_HAND_L_AVAILABLE=$IKLeft"

if (-not $ABPLoad -or -not $ABPClass -or -not $SameSkeleton) {
    Stop-Gate "ABP_TP_RIFLE_NOT_VERIFIED_COMPATIBLE_STOP_BEFORE_SOURCE_WRITE" 31
}
if (-not $HandGripRSocket) {
    Stop-Gate "HANDGRIP_R_IS_NOT_A_REAL_SOCKET_STOP_BEFORE_SOURCE_WRITE" 32
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PATCH ONLY: TP RIFLE ABP + HandGrip_R SOCKET" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Text = $Original

$UnarmedPath = "/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed"
$UnarmedCount = ([regex]::Matches($Text, [regex]::Escape($UnarmedPath))).Count
Write-Host "UNARMED_ABP_PATH_COUNT=$UnarmedCount"

if ($UnarmedCount -ne 1) {
    Stop-Gate "EXPECTED_ONE_UNARMED_ABP_PATH_FOUND_$UnarmedCount" 40
}

$Text = $Text.Replace($UnarmedPath, $ABPPackagePath)

$BlockPattern = '(?s)// ASWW_REAL_RIFLE_VISUAL_BEGIN.*?// ASWW_REAL_RIFLE_VISUAL_END'
$BlockMatch = [regex]::Match($Text, $BlockPattern)

if (-not $BlockMatch.Success) {
    Stop-Gate "REAL_RIFLE_VISUAL_BLOCK_NOT_FOUND_FOR_SOCKET_PATCH" 41
}

$Block = $BlockMatch.Value
$AttachMatches = [regex]::Matches($Block, 'SetupAttachment\(GetMesh\(\),\s*TEXT\("[^"]+"\)\)')
Write-Host "RIFLE_SETUPATTACHMENT_COUNT=$($AttachMatches.Count)"

if ($AttachMatches.Count -ne 1) {
    Stop-Gate "EXPECTED_ONE_RIFLE_SETUPATTACHMENT_FOUND_$($AttachMatches.Count)" 42
}

$Block = [regex]::Replace(
    $Block,
    'SetupAttachment\(GetMesh\(\),\s*TEXT\("[^"]+"\)\)',
    'SetupAttachment(GetMesh(), TEXT("HandGrip_R"))',
    1
)

$Block = $Block -replace 'socket=[A-Za-z0-9_]+', 'socket=HandGrip_R'

# Dedicated socket owns grip transform. Keep local transform identity.
$Block = [regex]::Replace(
    $Block,
    'RifleVisual->SetRelativeLocation\([^;]+;\s*RifleVisual->SetRelativeRotation\([^;]+;\s*RifleVisual->SetRelativeScale3D\([^;]+;',
    'RifleVisual->SetRelativeTransform(FTransform::Identity);',
    1,
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

$Text = $Text.Substring(0, $BlockMatch.Index) + $Block + $Text.Substring($BlockMatch.Index + $BlockMatch.Length)

$Marker = @"

    // ASWW_TP_RIFLE_TACTICAL_BEGIN
    // Third-person rifle AnimBlueprint: ABP_TP_Rifle.
    // Rifle visual attached to real Manny socket: HandGrip_R.
    // Manny provides ik_hand_gun / ik_hand_l chains.
    // Left-hand support grip remains visually gated; no false IK PASS is claimed here.
    // ASWW_TP_RIFLE_TACTICAL_END

"@

$MannyLogPattern = '(?m)^\s*UE_LOG\(LogTemp,\s*Warning,\s*$\r?\n^\s*TEXT\("ASWW_REAL_PLAYER_MANNY mesh=%s animClass=%s"\),'
$MannyAnchor = [regex]::Match($Text, $MannyLogPattern)
if (-not $MannyAnchor.Success) {
    Stop-Gate "MANNY_LOG_ANCHOR_NOT_FOUND_FOR_TACTICAL_MARKER" 43
}

$Text = $Text.Insert($MannyAnchor.Index, $Marker)

[IO.File]::WriteAllText($CharacterCpp, $Text, [Text.UTF8Encoding]::new($true))

$Disk = Get-Content -Raw -LiteralPath $CharacterCpp
$MarkerCount = ([regex]::Matches($Disk, "ASWW_TP_RIFLE_TACTICAL_BEGIN")).Count
$ABPCount = ([regex]::Matches($Disk, [regex]::Escape($ABPPackagePath))).Count
$GripCount = ([regex]::Matches($Disk, 'SetupAttachment\(GetMesh\(\),\s*TEXT\("HandGrip_R"\)\)')).Count

Write-Host "TP_RIFLE_TACTICAL_MARKER_COUNT=$MarkerCount"
Write-Host "TP_RIFLE_ABP_PATH_COUNT=$ABPCount"
Write-Host "HANDGRIP_R_ATTACH_COUNT=$GripCount"

if ($MarkerCount -ne 1 -or $ABPCount -ne 1 -or $GripCount -lt 1) {
    Stop-Gate "POST_PATCH_TACTICAL_SOURCE_VALIDATION_FAILED" 44
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 45
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLEAN BUILD + COOK + PACKAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 46
}

$PackageStart = Get-Date

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRETPRIFLE_$Stamp"
    try {
        Move-Item -LiteralPath $StageRoot -Destination $OldStage
        Write-Host "OLD_STAGE_MOVED=$OldStage"
    }
    catch {
        Stop-Gate "STAGE_ROOT_LOCKED_$($_.Exception.Message)" 47
    }
}

$PackageEvidence = Join-Path $ProjectRoot "Saved\RuntimeEvidence\TPRifleTacticalPackage"
New-Item -ItemType Directory -Force -Path $PackageEvidence | Out-Null
$PackageLog = Join-Path $PackageEvidence "tp_rifle_tactical_package_$Stamp.log"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BuildScript -UERoot $UERoot 2>&1 |
    Tee-Object -FilePath $PackageLog
$PackageExit = $LASTEXITCODE

Write-Host "PACKAGE_SCRIPT_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Write-Host ""
    Write-Host "=== PACKAGE FAILURE TAIL ===" -ForegroundColor Yellow
    Get-Content -LiteralPath $PackageLog -Tail 180
    Stop-Gate "BUILD_WIN64_FAILED_EXIT_$PackageExit" $(if ($PackageExit -gt 0) { $PackageExit } else { 50 })
}

$Exes = @(
    Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
)
if ($Exes.Count -eq 0) {
    Stop-Gate "PACKAGE_EXIT_ZERO_BUT_EXE_NOT_FOUND" 51
}

$Exe = $Exes[0]
$FreshExe = $Exe.LastWriteTime -ge $PackageStart.AddMinutes(-1)
$Containers = @(
    Get-ChildItem -LiteralPath $StageRoot -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @(".pak",".utoc",".ucas") }
)

Write-Host "PACKAGED_EXE=$($Exe.FullName)"
Write-Host "PACKAGED_EXE_FRESH=$FreshExe"
Write-Host "CONTAINER_FILE_COUNT=$($Containers.Count)"

if (-not $FreshExe -or $Containers.Count -eq 0) {
    Stop-Gate "PACKAGED_OUTPUT_NOT_FRESH_OR_NO_CONTAINERS" 52
}

Write-Host ""
Write-Host "TP_RIFLE_TACTICAL_INTEGRATION=PASS" -ForegroundColor Green
Write-Host "SELECTED_ABP=ABP_TP_Rifle" -ForegroundColor Green
Write-Host "ABP_SKELETON_COMPATIBILITY=PASS" -ForegroundColor Green
Write-Host "WEAPON_SOCKET=HandGrip_R" -ForegroundColor Green
Write-Host "IK_CHAIN_AVAILABLE=$($IKGun -and $IKLeft)" -ForegroundColor Green
Write-Host "LEFT_HAND_IK_RUNTIME=NOT_YET_VISUALLY_PROVEN" -ForegroundColor Yellow
Write-Host "CLEAN_PACKAGE_TP_RIFLE=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_TP_RIFLE_TACTICAL_VISUAL_QA_V2" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
