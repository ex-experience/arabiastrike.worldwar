[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$StageRoot = "D:\ASWW_STAGE",
    [string]$ArchiveRoot = "D:\ASWW_ARCHIVE\CombatPlayerControlRecovery"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_03C_CONTROL_RECOVERY_AB=STOPPED" -ForegroundColor Red
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
$BuildBat = Join-Path $UERoot "Engine\Build\BatchFiles\Build.bat"
$RunUAT = Join-Path $UERoot "Engine\Build\BatchFiles\RunUAT.bat"
$V2H = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Player\ASPlayerCharacterV2.h"
$V2Cpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASPlayerCharacterV2.cpp"

foreach ($Required in @($ProjectFile,$BuildBat,$RunUAT,$V2H,$V2Cpp)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

$Header = Get-Content -Raw -LiteralPath $V2H
$Source = Get-Content -Raw -LiteralPath $V2Cpp

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY CURRENT CONTROL-REGRESSION BUILD SHAPE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$HeaderCombatMarker = $Header -match "ASWW_COMBAT_PLAYER_V1_BEGIN"
$CppOnlyMarker = $Source -match "ASWW_COMBAT_PLAYER_V1_CPP_ONLY_BEGIN"
$TPRifleABP = $Source -match "/Game/Variant_Shooter/Anims/ABP_TP_Rifle"
$RifleMesh = $Source -match "/Game/Weapons/Rifle/Meshes/SKM_Rifle"
$RightGrip = $Source -match 'SetupAttachment\(GetMesh\(\), TEXT\("HandGrip_R"\)\)'
$ShoulderCamera = $Source -match 'SocketOffset = FVector\(0\.f, 55\.f, 52\.f\)'
$ADSFov = $Source -match 'ADSCameraFOV = 68\.f'

Write-Host "HEADER_COMBAT_MARKER_PRESENT=$HeaderCombatMarker"
Write-Host "CPP_ONLY_COMBAT_MARKER=$CppOnlyMarker"
Write-Host "TP_RIFLE_ABP_SELECTED=$TPRifleABP"
Write-Host "SKM_RIFLE_SELECTED=$RifleMesh"
Write-Host "HANDGRIP_R_ATTACH=$RightGrip"
Write-Host "SHOULDER_CAMERA=$ShoulderCamera"
Write-Host "ADS_FOV=$ADSFov"

if ($HeaderCombatMarker) {
    Stop-Gate "REFLECTED_PHASE03_HEADER_PATCH_REAPPEARED" 12
}
if (-not ($CppOnlyMarker -and $TPRifleABP -and $RifleMesh -and $RightGrip -and $ShoulderCamera -and $ADSFov)) {
    Stop-Gate "CURRENT_CPP_ONLY_COMBAT_STATE_NOT_AS_EXPECTED" 13
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\ControlRecoveryAB_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
Copy-Item -LiteralPath $V2Cpp -Destination (Join-Path $BackupRoot "ASPlayerCharacterV2.cpp.before_control_recovery_ab") -Force
Write-Host "BACKUP_ROOT=$BackupRoot"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " A/B CHANGE: RESTORE PROVEN LOCOMOTION ANIMBP ONLY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$TPPath = 'TEXT("/Game/Variant_Shooter/Anims/ABP_TP_Rifle")'
$UnarmedPath = 'TEXT("/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed")'

if ($Source -notmatch [regex]::Escape($TPPath)) {
    Stop-Gate "TP_RIFLE_ANIMBP_PATH_NOT_FOUND" 20
}

$Source = $Source.Replace($TPPath, $UnarmedPath)

# Keep the runtime marker diagnostic explicit without changing gameplay behavior.
$OldMarker = 'TEXT("ASWW_COMBAT_PLAYER_V1_CPP_ONLY anim=%s rifleSubobject=ASWW_TacticalRifleMesh socket=HandGrip_R")'
$NewMarker = 'TEXT("ASWW_CONTROL_RECOVERY_AB_UNARMED anim=%s rifleSubobject=ASWW_TacticalRifleMesh socket=HandGrip_R")'
if ($Source -match [regex]::Escape($OldMarker)) {
    $Source = $Source.Replace($OldMarker, $NewMarker)
}

[IO.File]::WriteAllText($V2Cpp, $Source, [Text.UTF8Encoding]::new($true))

$After = Get-Content -Raw -LiteralPath $V2Cpp
$UnarmedSelected = $After -match "/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed"
$TPRemoved = -not ($After -match "/Game/Variant_Shooter/Anims/ABP_TP_Rifle")
$RifleStillPresent = $After -match "/Game/Weapons/Rifle/Meshes/SKM_Rifle"
$GripStillPresent = $After -match 'SetupAttachment\(GetMesh\(\), TEXT\("HandGrip_R"\)\)'
$CameraStillPresent = $After -match 'SocketOffset = FVector\(0\.f, 55\.f, 52\.f\)'
$ADSStillPresent = $After -match 'ADSCameraFOV = 68\.f'

Write-Host "AB_UNARMED_SELECTED=$UnarmedSelected"
Write-Host "AB_TP_RIFLE_REMOVED=$TPRemoved"
Write-Host "RIFLE_MESH_PRESERVED=$RifleStillPresent"
Write-Host "HANDGRIP_R_PRESERVED=$GripStillPresent"
Write-Host "SHOULDER_CAMERA_PRESERVED=$CameraStillPresent"
Write-Host "ADS_FOV_PRESERVED=$ADSStillPresent"

if (-not ($UnarmedSelected -and $TPRemoved -and $RifleStillPresent -and $GripStillPresent -and $CameraStillPresent -and $ADSStillPresent)) {
    Stop-Gate "AB_PATCH_POST_VERIFY_FAILED" 21
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 22
}

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 23
}

$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\ControlRecoveryAB_$Stamp"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " EDITOR BUILD — SERIAL / NO UBA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$EditorLog = Join-Path $EvidenceRoot "editor_build.log"
$EditorArgs = @(
    "ArabiaStrikeWorldWarEditor",
    "Win64",
    "Development",
    "-Project=`"$ProjectFile`"",
    "-WaitMutex",
    "-NoHotReloadFromIDE",
    "-MaxParallelActions=1",
    "-NoUBA"
)

& $BuildBat @EditorArgs 2>&1 | Tee-Object -FilePath $EditorLog | Out-Host
$EditorExit = $LASTEXITCODE
$EditorSucceeded = (Get-Content -Raw -LiteralPath $EditorLog) -match "Result:\s*Succeeded"

Write-Host "EDITOR_BUILD_EXIT=$EditorExit"
Write-Host "EDITOR_RESULT_SUCCEEDED_SEEN=$EditorSucceeded"

if ($EditorExit -ne 0 -or -not $EditorSucceeded) {
    Get-Content -LiteralPath $EditorLog -Tail 260
    $StopCode = 30
    if ($EditorExit -gt 0) { $StopCode = $EditorExit }
    Stop-Gate "EDITOR_BUILD_NOT_PROVEN_SUCCESS_EXIT_$EditorExit" $StopCode
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " GAME BUILD — SERIAL / NO UBA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$GameLog = Join-Path $EvidenceRoot "game_build.log"
$GameArgs = @(
    "ArabiaStrikeWorldWar",
    "Win64",
    "Development",
    "-Project=`"$ProjectFile`"",
    "-WaitMutex",
    "-MaxParallelActions=1",
    "-NoUBA"
)

& $BuildBat @GameArgs 2>&1 | Tee-Object -FilePath $GameLog | Out-Host
$GameExit = $LASTEXITCODE
$GameSucceeded = (Get-Content -Raw -LiteralPath $GameLog) -match "Result:\s*Succeeded"

Write-Host "GAME_BUILD_EXIT=$GameExit"
Write-Host "GAME_RESULT_SUCCEEDED_SEEN=$GameSucceeded"

if ($GameExit -ne 0 -or -not $GameSucceeded) {
    Get-Content -LiteralPath $GameLog -Tail 260
    $StopCode = 31
    if ($GameExit -gt 0) { $StopCode = $GameExit }
    Stop-Gate "GAME_BUILD_NOT_PROVEN_SUCCESS_EXIT_$GameExit" $StopCode
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COOK + STAGE + PACKAGE — SKIP BUILD" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRE_CONTROL_RECOVERY_AB_$Stamp"
    Move-Item -LiteralPath $StageRoot -Destination $OldStage
    Write-Host "OLD_STAGE_MOVED=$OldStage"
}

New-Item -ItemType Directory -Force -Path $ArchiveRoot | Out-Null

$PackageLog = Join-Path $EvidenceRoot "package.log"
$UATArgs = @(
    "BuildCookRun",
    "-project=`"$ProjectFile`"",
    "-noP4",
    "-platform=Win64",
    "-clientconfig=Development",
    "-skipbuild",
    "-cook",
    "-stage",
    "-stagingdirectory=`"$StageRoot`"",
    "-pak",
    "-package",
    "-archive",
    "-archivedirectory=`"$ArchiveRoot`"",
    "-utf8output"
)

$PackageStart = Get-Date
& $RunUAT @UATArgs 2>&1 | Tee-Object -FilePath $PackageLog | Out-Host
$PackageExit = $LASTEXITCODE
Write-Host "PACKAGE_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Get-Content -LiteralPath $PackageLog -Tail 320
    $StopCode = 32
    if ($PackageExit -gt 0) { $StopCode = $PackageExit }
    Stop-Gate "PACKAGE_FAILED_EXIT_$PackageExit" $StopCode
}

$Exes = @(
    Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
)
$Containers = @(
    Get-ChildItem -LiteralPath $StageRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @(".pak",".utoc",".ucas") }
)

if ($Exes.Count -eq 0) { Stop-Gate "PACKAGE_EXIT_ZERO_BUT_EXE_NOT_FOUND" 33 }
if ($Containers.Count -eq 0) { Stop-Gate "PACKAGE_EXIT_ZERO_BUT_NO_CONTAINERS_FOUND" 34 }

$Exe = $Exes[0]
$FreshExe = $Exe.LastWriteTime -ge $PackageStart.AddMinutes(-2)

Write-Host "PACKAGED_EXE=$($Exe.FullName)"
Write-Host "PACKAGED_EXE_FRESH=$FreshExe"
Write-Host "PACKAGED_CONTAINER_COUNT=$($Containers.Count)"

if (-not $FreshExe) { Stop-Gate "PACKAGED_EXE_NOT_FRESH" 35 }

Write-Host ""
Write-Host "PHASE_03C_CONTROL_RECOVERY_AB=PASS" -ForegroundColor Green
Write-Host "LOCOMOTION_ANIMBP=ABP_Unarmed_PROVEN_BASELINE" -ForegroundColor Green
Write-Host "RIFLE_MESH=SKM_Rifle_PRESERVED" -ForegroundColor Green
Write-Host "RIFLE_SOCKET=HandGrip_R_PRESERVED" -ForegroundColor Green
Write-Host "SHOULDER_CAMERA=PRESERVED" -ForegroundColor Green
Write-Host "ADS_CAMERA=PRESERVED" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_PHASE_03C_CONTROL_RECOVERY_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
