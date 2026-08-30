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
    Write-Host "PHASE_03A_COMBAT_PLAYER_V1=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Write-Utf8Bom([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($true))
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
$BuildScript = Join-Path $ProjectRoot "BuildScripts\build_win64.ps1"
$V2H = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Player\ASPlayerCharacterV2.h"
$V2Cpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASPlayerCharacterV2.cpp"

foreach ($Required in @($ProjectFile,$EditorCmd,$BuildScript,$V2H,$V2Cpp)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TARGETED COMBAT ASSET CONTRACT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\CombatPlayerV1"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

$Py = Join-Path $EvidenceRoot "combat_player_v1_asset_gate_$Stamp.py"
$Out = Join-Path $EvidenceRoot "combat_player_v1_asset_gate_$Stamp.stdout.log"
$Err = Join-Path $EvidenceRoot "combat_player_v1_asset_gate_$Stamp.stderr.log"

$PyText = @'
import unreal

registry = unreal.AssetRegistryHelpers.get_asset_registry()
registry.scan_paths_synchronous(["/Game"], True)

targets = [
    "/Game/Variant_Shooter/Anims/ABP_TP_Rifle",
    "/Game/Weapons/Rifle/Meshes/SKM_Rifle",
]

opts = unreal.AssetRegistryDependencyOptions(
    include_soft_package_references=True,
    include_hard_package_references=True,
    include_searchable_names=False,
    include_soft_management_references=False,
    include_hard_management_references=False
)

def exists(pkg):
    try:
        return len(registry.get_assets_by_package_name(pkg)) > 0
    except Exception:
        return False

missing = set()
visited = set()
frontier = list(targets)

for _ in range(32):
    if not frontier:
        break
    nxt = []
    for owner in frontier:
        if owner in visited:
            continue
        visited.add(owner)

        if owner.startswith("/Game/") and not exists(owner):
            missing.add(owner)
            continue

        try:
            deps = registry.get_dependencies(owner, opts)
        except Exception as exc:
            print(f"ASWW_P03A_DEP_ENUM_ERROR|OWNER={owner}|ERR={exc}")
            continue

        for dep in deps:
            dep = str(dep)
            if not dep.startswith("/Game/"):
                continue
            if not exists(dep):
                missing.add(dep)
            elif dep not in visited:
                nxt.append(dep)
    frontier = nxt

abp = unreal.load_asset("/Game/Variant_Shooter/Anims/ABP_TP_Rifle.ABP_TP_Rifle")
rifle = unreal.load_asset("/Game/Weapons/Rifle/Meshes/SKM_Rifle.SKM_Rifle")
manny = unreal.load_asset("/Game/Characters/Mannequins/Meshes/SKM_Manny_Simple.SKM_Manny_Simple")

print(f"ASWW_P03A_ABP_LOAD={abp is not None}")
print(f"ASWW_P03A_RIFLE_LOAD={rifle is not None}")
print(f"ASWW_P03A_MANNY_LOAD={manny is not None}")
print(f"ASWW_P03A_RIFLE_CLASS={rifle.get_class().get_name() if rifle else 'NONE'}")
print(f"ASWW_P03A_MISSING_COUNT={len(missing)}")
for pkg in sorted(missing):
    print(f"ASWW_P03A_MISSING={pkg}")

if manny:
    comp = unreal.new_object(unreal.SkeletalMeshComponent)
    try:
        comp.set_skeletal_mesh_asset(manny)
    except Exception:
        try:
            comp.set_skeletal_mesh(manny)
        except Exception:
            pass
    names = {str(x).lower() for x in comp.get_all_socket_names()}
    print(f"ASWW_P03A_HANDGRIP_R={'handgrip_r' in names}")
    print(f"ASWW_P03A_HANDGRIP_L={'handgrip_l' in names}")
    print(f"ASWW_P03A_IK_HAND_GUN={'ik_hand_gun' in names}")
    print(f"ASWW_P03A_IK_HAND_L={'ik_hand_l' in names}")

print("ASWW_P03A_ASSET_GATE_DONE=True")
'@

[IO.File]::WriteAllText($Py, $PyText, [Text.UTF8Encoding]::new($false))
$PyForward = $Py.Replace('\','/')

& $EditorCmd `
    $ProjectFile `
    "-unattended" "-nop4" "-nosplash" "-NullRHI" "-stdout" "-FullStdOutLogOutput" `
    "-ExecutePythonScript=$PyForward" `
    1> $Out 2> $Err

$GateExit = $LASTEXITCODE
$Combined = ""
if (Test-Path -LiteralPath $Out) {
    $Combined += Get-Content -Raw -LiteralPath $Out
    Select-String -LiteralPath $Out -Pattern "ASWW_P03A_" | ForEach-Object { Write-Host $_.Line }
}
if (Test-Path -LiteralPath $Err) {
    $Combined += "`n" + (Get-Content -Raw -LiteralPath $Err)
}

$GateDone = $Combined -match "ASWW_P03A_ASSET_GATE_DONE=True"
$PythonError = $Combined -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$ExplicitFatal = $Combined -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$MissingMatch = [regex]::Match($Combined, "ASWW_P03A_MISSING_COUNT=(\d+)")
$MissingCount = if ($MissingMatch.Success) { [int]$MissingMatch.Groups[1].Value } else { -1 }

$ABPLoad = $Combined -match "ASWW_P03A_ABP_LOAD=True"
$RifleLoad = $Combined -match "ASWW_P03A_RIFLE_LOAD=True"
$MannyLoad = $Combined -match "ASWW_P03A_MANNY_LOAD=True"
$RifleSkeletal = $Combined -match "ASWW_P03A_RIFLE_CLASS=SkeletalMesh"
$RightGrip = $Combined -match "ASWW_P03A_HANDGRIP_R=True"
$LeftGrip = $Combined -match "ASWW_P03A_HANDGRIP_L=True"
$IKGun = $Combined -match "ASWW_P03A_IK_HAND_GUN=True"
$IKLeft = $Combined -match "ASWW_P03A_IK_HAND_L=True"

Write-Host "ASSET_GATE_EXIT=$GateExit"
Write-Host "ASSET_GATE_DONE=$GateDone"
Write-Host "ASSET_GATE_MISSING_COUNT=$MissingCount"

if (-not $GateDone -or $PythonError -or $ExplicitFatal) {
    Stop-Gate "TARGETED_ASSET_GATE_NOT_TRUSTWORTHY" 20
}
if (-not ($ABPLoad -and $RifleLoad -and $MannyLoad -and $RifleSkeletal -and $RightGrip -and $LeftGrip -and $IKGun -and $IKLeft)) {
    Stop-Gate "TARGETED_COMBAT_ASSET_CONTRACT_INCOMPLETE" 21
}
if ($MissingCount -ne 0) {
    Stop-Gate "TARGETED_COMBAT_ASSETS_HAVE_MISSING_DEPENDENCIES_$MissingCount" 22
}

Write-Host ""
Write-Host "TARGETED_COMBAT_ASSET_CONTRACT=PASS" -ForegroundColor Green
Write-Host "QUINN_AND_FIRSTPERSON_CHAIN=NOT_REQUIRED_FOR_THIS_COMBAT_PLAYER" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PATCH ASPLAYERCHARACTERV2 -> COMBAT PLAYER V1" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Header = Get-Content -Raw -LiteralPath $V2H
$Source = Get-Content -Raw -LiteralPath $V2Cpp

if ($Header -match "ASWW_COMBAT_PLAYER_V1_BEGIN" -or $Source -match "ASWW_COMBAT_PLAYER_V1_BEGIN") {
    Stop-Gate "COMBAT_PLAYER_V1_MARKER_ALREADY_PRESENT_REVIEW_BEFORE_RERUN" 23
}

$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\CombatPlayerV1_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
Copy-Item -LiteralPath $V2H -Destination (Join-Path $BackupRoot "ASPlayerCharacterV2.h.before_combat_v1") -Force
Copy-Item -LiteralPath $V2Cpp -Destination (Join-Path $BackupRoot "ASPlayerCharacterV2.cpp.before_combat_v1") -Force
Write-Host "BACKUP_ROOT=$BackupRoot"

if ($Header -notmatch "class USkeletalMeshComponent;") {
    $Header = $Header.Replace(
        '#include "ASPlayerCharacterV2.generated.h"',
        "#include `"ASPlayerCharacterV2.generated.h`"`r`n`r`nclass USkeletalMeshComponent;"
    )
}

$HeaderInsert = @'

    // ASWW_COMBAT_PLAYER_V1_BEGIN
    UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category="ASWW|Combat Player")
    TObjectPtr<USkeletalMeshComponent> TacticalRifleMesh;

    UFUNCTION(BlueprintPure, Category="ASWW|Combat Player")
    USkeletalMeshComponent* GetTacticalRifleMesh() const { return TacticalRifleMesh; }
    // ASWW_COMBAT_PLAYER_V1_END
'@

$LastBrace = $Header.LastIndexOf("};")
if ($LastBrace -lt 0) {
    Stop-Gate "COULD_NOT_FIND_CLASS_END_IN_V2_HEADER" 24
}
$Header = $Header.Insert($LastBrace, $HeaderInsert)

if ($Source -notmatch '#include "Components/SkeletalMeshComponent.h"') {
    $Source = $Source.Replace(
        '#include "Components/CapsuleComponent.h"',
        "#include `"Components/CapsuleComponent.h`"`r`n#include `"Components/SkeletalMeshComponent.h`"`r`n#include `"Engine/SkeletalMesh.h`""
    )
}

# Replace the temporary/proven unarmed presentation AnimBP with the verified
# third-person rifle AnimBP. Player V2 retains its own movement/camera/input code.
$Source = $Source.Replace(
    'TEXT("/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed")',
    'TEXT("/Game/Variant_Shooter/Anims/ABP_TP_Rifle")'
)

$CtorNeedle = "PrimaryActorTick.bCanEverTick = true;"
if ($Source -notmatch [regex]::Escape($CtorNeedle)) {
    Stop-Gate "V2_CONSTRUCTOR_TICK_MARKER_NOT_FOUND" 25
}

$CtorBlock = @'
PrimaryActorTick.bCanEverTick = true;

    // ASWW_COMBAT_PLAYER_V1_BEGIN
    static ConstructorHelpers::FObjectFinder<USkeletalMesh> TacticalRifleAsset(
        TEXT("/Game/Weapons/Rifle/Meshes/SKM_Rifle.SKM_Rifle"));

    TacticalRifleMesh = CreateDefaultSubobject<USkeletalMeshComponent>(TEXT("TacticalRifleMesh"));
    TacticalRifleMesh->SetupAttachment(GetMesh(), TEXT("HandGrip_R"));
    TacticalRifleMesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    TacticalRifleMesh->SetGenerateOverlapEvents(false);
    TacticalRifleMesh->SetRelativeLocation(FVector::ZeroVector);
    TacticalRifleMesh->SetRelativeRotation(FRotator::ZeroRotator);
    TacticalRifleMesh->SetRelativeScale3D(FVector(1.f));

    if (TacticalRifleAsset.Succeeded())
    {
        TacticalRifleMesh->SetSkeletalMeshAsset(TacticalRifleAsset.Object);
    }

    DefaultCameraFOV = 88.f;
    ADSCameraFOV = 68.f;
    CameraArmLength = 285.f;

    if (CameraBoom)
    {
        CameraBoom->TargetArmLength = CameraArmLength;
        CameraBoom->SocketOffset = FVector(0.f, 55.f, 52.f);
        CameraBoom->bEnableCameraLag = true;
        CameraBoom->CameraLagSpeed = 14.f;
        CameraBoom->bEnableCameraRotationLag = true;
        CameraBoom->CameraRotationLagSpeed = 18.f;
    }
    // ASWW_COMBAT_PLAYER_V1_END
'@

$Source = $Source.Replace($CtorNeedle, $CtorBlock)

# Add a runtime marker to the existing BeginPlay.
$BeginNeedle = "Super::BeginPlay();"
if ($Source -notmatch [regex]::Escape($BeginNeedle)) {
    Stop-Gate "V2_BEGINPLAY_SUPER_MARKER_NOT_FOUND" 26
}

$BeginBlock = @'
Super::BeginPlay();

    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_COMBAT_PLAYER_V1 anim=%s rifle=%s socket=HandGrip_R"),
        *GetNameSafe(GetMesh() ? GetMesh()->GetAnimClass() : nullptr),
        *GetNameSafe(TacticalRifleMesh ? TacticalRifleMesh->GetSkeletalMeshAsset() : nullptr));
'@

$Source = $Source.Replace($BeginNeedle, $BeginBlock)

Write-Utf8Bom $V2H $Header
Write-Utf8Bom $V2Cpp $Source

Write-Host "V2_HEADER_PATCHED=True"
Write-Host "V2_SOURCE_PATCHED=True"

$HeaderDisk = Get-Content -Raw -LiteralPath $V2H
$SourceDisk = Get-Content -Raw -LiteralPath $V2Cpp

$Checks = [ordered]@{
    COMBAT_MARKER_HEADER = $HeaderDisk -match "ASWW_COMBAT_PLAYER_V1_BEGIN"
    COMBAT_MARKER_SOURCE = $SourceDisk -match "ASWW_COMBAT_PLAYER_V1_BEGIN"
    TP_RIFLE_ABP_SELECTED = $SourceDisk -match "/Game/Variant_Shooter/Anims/ABP_TP_Rifle"
    SKELETAL_RIFLE_SELECTED = $SourceDisk -match "/Game/Weapons/Rifle/Meshes/SKM_Rifle"
    HANDGRIP_R_ATTACH = $SourceDisk -match 'SetupAttachment\(GetMesh\(\), TEXT\("HandGrip_R"\)\)'
    SHOULDER_CAMERA = $SourceDisk -match 'SocketOffset = FVector\(0\.f, 55\.f, 52\.f\)'
    ADS_FOV = $SourceDisk -match 'ADSCameraFOV = 68\.f'
}

foreach ($Pair in $Checks.GetEnumerator()) {
    Write-Host "$($Pair.Key)=$($Pair.Value)"
    if (-not $Pair.Value) {
        Stop-Gate "PATCH_VERIFICATION_FAILED_$($Pair.Key)" 27
    }
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 28
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " BUILD + COOK + PACKAGE COMBAT PLAYER V1" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 29
}

$PackageStart = Get-Date

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRE_COMBAT_PLAYER_V1_$Stamp"
    try {
        Move-Item -LiteralPath $StageRoot -Destination $OldStage
        Write-Host "OLD_STAGE_MOVED=$OldStage"
    }
    catch {
        Stop-Gate "STAGE_ROOT_LOCKED_$($_.Exception.Message)" 30
    }
}

$PackageLog = Join-Path $EvidenceRoot "combat_player_v1_package_$Stamp.log"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BuildScript -UERoot $UERoot 2>&1 |
    Tee-Object -FilePath $PackageLog
$PackageExit = $LASTEXITCODE

Write-Host "PACKAGE_SCRIPT_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Write-Host "=== PACKAGE FAILURE TAIL ===" -ForegroundColor Yellow
    Get-Content -LiteralPath $PackageLog -Tail 240
    Stop-Gate "BUILD_WIN64_FAILED_EXIT_$PackageExit" $(if ($PackageExit -gt 0) { $PackageExit } else { 31 })
}

$Exes = @(
    Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
)

if ($Exes.Count -eq 0) {
    Stop-Gate "PACKAGE_EXIT_ZERO_BUT_EXE_NOT_FOUND" 32
}

$Exe = $Exes[0]
$FreshExe = $Exe.LastWriteTime -ge $PackageStart.AddMinutes(-1)

Write-Host "PACKAGED_EXE=$($Exe.FullName)"
Write-Host "PACKAGED_EXE_FRESH=$FreshExe"

if (-not $FreshExe) {
    Stop-Gate "PACKAGED_EXE_NOT_FRESH" 33
}

Write-Host ""
Write-Host "PHASE_03A_COMBAT_PLAYER_V1=PASS" -ForegroundColor Green
Write-Host "COMBAT_ANIM=ABP_TP_RIFLE" -ForegroundColor Green
Write-Host "RIFLE_MESH=SKM_Rifle" -ForegroundColor Green
Write-Host "RIFLE_ATTACH_SOCKET=HandGrip_R" -ForegroundColor Green
Write-Host "PLAYER_V2_INPUT_CAMERA_ARCHITECTURE=PRESERVED" -ForegroundColor Green
Write-Host "QUINN_DEPENDENCY=EXCLUDED_FROM_TARGETED_COMBAT_CONTRACT" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_PHASE_03B_COMBAT_PLAYER_V1_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
