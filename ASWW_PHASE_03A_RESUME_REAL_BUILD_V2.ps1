[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$StageRoot = "D:\ASWW_STAGE",
    [string]$ArchiveRoot = "D:\ASWW_ARCHIVE\CombatPlayerV1",
    [string]$Phase03BackupRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar\Saved\Verification\CombatPlayerV1_20260829_024216"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_03A_RESUME_REAL_BUILD_V2=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_SOURCE_CHANGES_MADE_BY_THIS_SCRIPT" -ForegroundColor Green
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
$BackupH = Join-Path $Phase03BackupRoot "ASPlayerCharacterV2.h.before_combat_v1"

foreach ($Required in @($ProjectFile,$BuildBat,$RunUAT,$V2H,$V2Cpp,$BackupH)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\CombatPlayerV1RealBuildV2_$Stamp"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY CURRENT CPP-ONLY COMBAT STATE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$BackupHeaderHash = (Get-FileHash -LiteralPath $BackupH -Algorithm SHA256).Hash
$CurrentHeaderHash = (Get-FileHash -LiteralPath $V2H -Algorithm SHA256).Hash
$HeaderExact = $BackupHeaderHash -eq $CurrentHeaderHash

$HeaderText = Get-Content -Raw -LiteralPath $V2H
$CppText = Get-Content -Raw -LiteralPath $V2Cpp

$HeaderCombatMarker = $HeaderText -match "ASWW_COMBAT_PLAYER_V1_BEGIN"
$CppOnlyMarker = $CppText -match "ASWW_COMBAT_PLAYER_V1_CPP_ONLY_BEGIN"
$RifleABP = $CppText -match "/Game/Variant_Shooter/Anims/ABP_TP_Rifle"
$RifleMesh = $CppText -match "/Game/Weapons/Rifle/Meshes/SKM_Rifle"
$RightGrip = $CppText -match 'SetupAttachment\(GetMesh\(\), TEXT\("HandGrip_R"\)\)'
$ShoulderCamera = $CppText -match 'SocketOffset = FVector\(0\.f, 55\.f, 52\.f\)'
$ADSFov = $CppText -match 'ADSCameraFOV = 68\.f'

Write-Host "HEADER_EXACT_PRE_PHASE03=$HeaderExact"
Write-Host "HEADER_COMBAT_MARKER_PRESENT=$HeaderCombatMarker"
Write-Host "CPP_ONLY_COMBAT_MARKER=$CppOnlyMarker"
Write-Host "TP_RIFLE_ABP_SELECTED=$RifleABP"
Write-Host "SKM_RIFLE_SELECTED=$RifleMesh"
Write-Host "HANDGRIP_R_ATTACH=$RightGrip"
Write-Host "SHOULDER_CAMERA=$ShoulderCamera"
Write-Host "ADS_FOV=$ADSFov"

if (-not $HeaderExact) {
    Stop-Gate "V2_HEADER_NO_LONGER_MATCHES_PRE_PHASE03_LOCAL_BACKUP" 12
}
if ($HeaderCombatMarker) {
    Stop-Gate "REFLECTED_PHASE03_HEADER_PATCH_STILL_PRESENT" 13
}
if (-not ($CppOnlyMarker -and $RifleABP -and $RifleMesh -and $RightGrip -and $ShoulderCamera -and $ADSFov)) {
    Stop-Gate "CPP_ONLY_COMBAT_PATCH_NOT_COMPLETE" 14
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 15
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PROCESS GATE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 16
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REAL EDITOR BUILD — SERIAL / NO UBA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$EditorLog = Join-Path $EvidenceRoot "editor_build_no_uba.log"
$EditorBuildArgs = @(
    "ArabiaStrikeWorldWarEditor",
    "Win64",
    "Development",
    "-Project=`"$ProjectFile`"",
    "-WaitMutex",
    "-NoHotReloadFromIDE",
    "-MaxParallelActions=1",
    "-NoUBA"
)

Write-Host "EDITOR_BUILD_COMMAND=`"$BuildBat`" $($EditorBuildArgs -join ' ')"
& $BuildBat @EditorBuildArgs 2>&1 | Tee-Object -FilePath $EditorLog | Out-Host
$EditorExit = $LASTEXITCODE
$EditorSucceeded = $false
if (Test-Path -LiteralPath $EditorLog) {
    $EditorSucceeded = (Get-Content -Raw -LiteralPath $EditorLog) -match "Result:\s*Succeeded"
}

Write-Host "EDITOR_BUILD_EXIT=$EditorExit"
Write-Host "EDITOR_RESULT_SUCCEEDED_SEEN=$EditorSucceeded"

if ($EditorExit -ne 0 -or -not $EditorSucceeded) {
    Write-Host "=== EDITOR BUILD FAILURE TAIL ===" -ForegroundColor Yellow
    if (Test-Path -LiteralPath $EditorLog) {
        Get-Content -LiteralPath $EditorLog -Tail 300
    }
    $StopCode = 20
    if ($EditorExit -gt 0) { $StopCode = $EditorExit }
    Stop-Gate "EDITOR_BUILD_NOT_PROVEN_SUCCESS_EXIT_$EditorExit" $StopCode
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REAL GAME BUILD — SERIAL / NO UBA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$GameLog = Join-Path $EvidenceRoot "game_build_no_uba.log"
$GameBuildArgs = @(
    "ArabiaStrikeWorldWar",
    "Win64",
    "Development",
    "-Project=`"$ProjectFile`"",
    "-WaitMutex",
    "-MaxParallelActions=1",
    "-NoUBA"
)

Write-Host "GAME_BUILD_COMMAND=`"$BuildBat`" $($GameBuildArgs -join ' ')"
& $BuildBat @GameBuildArgs 2>&1 | Tee-Object -FilePath $GameLog | Out-Host
$GameExit = $LASTEXITCODE
$GameSucceeded = $false
if (Test-Path -LiteralPath $GameLog) {
    $GameSucceeded = (Get-Content -Raw -LiteralPath $GameLog) -match "Result:\s*Succeeded"
}

Write-Host "GAME_BUILD_EXIT=$GameExit"
Write-Host "GAME_RESULT_SUCCEEDED_SEEN=$GameSucceeded"

if ($GameExit -ne 0 -or -not $GameSucceeded) {
    Write-Host "=== GAME BUILD FAILURE TAIL ===" -ForegroundColor Yellow
    if (Test-Path -LiteralPath $GameLog) {
        Get-Content -LiteralPath $GameLog -Tail 300
    }
    $StopCode = 21
    if ($GameExit -gt 0) { $StopCode = $GameExit }
    Stop-Gate "GAME_BUILD_NOT_PROVEN_SUCCESS_EXIT_$GameExit" $StopCode
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COOK + STAGE + PAK + PACKAGE — SKIP BUILD" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRE_REAL_BUILD_V2_$Stamp"
    try {
        Move-Item -LiteralPath $StageRoot -Destination $OldStage
        Write-Host "OLD_STAGE_MOVED=$OldStage"
    }
    catch {
        Stop-Gate "STAGE_ROOT_LOCKED_$($_.Exception.Message)" 22
    }
}

New-Item -ItemType Directory -Force -Path $ArchiveRoot | Out-Null

$PackageLog = Join-Path $EvidenceRoot "cook_stage_package.log"
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
Write-Host "PACKAGE_COMMAND=`"$RunUAT`" $($UATArgs -join ' ')"
& $RunUAT @UATArgs 2>&1 | Tee-Object -FilePath $PackageLog | Out-Host
$PackageExit = $LASTEXITCODE

Write-Host "PACKAGE_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Write-Host "=== PACKAGE FAILURE TAIL ===" -ForegroundColor Yellow
    if (Test-Path -LiteralPath $PackageLog) {
        Get-Content -LiteralPath $PackageLog -Tail 360
    }
    $StopCode = 22
    if ($PackageExit -gt 0) { $StopCode = $PackageExit }
    Stop-Gate "COOK_STAGE_PACKAGE_FAILED_EXIT_$PackageExit" $StopCode
}

$Containers = @(
    Get-ChildItem -LiteralPath $StageRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @(".pak",".utoc",".ucas") }
)

$Exes = @(
    Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
)

Write-Host "PACKAGED_CONTAINER_COUNT=$($Containers.Count)"
Write-Host "PACKAGED_EXE_COUNT=$($Exes.Count)"

if ($Exes.Count -eq 0) {
    Stop-Gate "PACKAGE_EXIT_ZERO_BUT_EXE_NOT_FOUND" 23
}
if ($Containers.Count -eq 0) {
    Stop-Gate "PACKAGE_EXIT_ZERO_BUT_NO_PAK_UTOC_UCAS_FOUND" 24
}

$Exe = $Exes[0]
$FreshExe = $Exe.LastWriteTime -ge $PackageStart.AddMinutes(-2)

Write-Host "PACKAGED_EXE=$($Exe.FullName)"
Write-Host "PACKAGED_EXE_FRESH=$FreshExe"

if (-not $FreshExe) {
    Stop-Gate "PACKAGED_EXE_NOT_FRESH" 25
}

Write-Host ""
Write-Host "PHASE_03A_RESUME_REAL_BUILD_V2=PASS" -ForegroundColor Green
Write-Host "CPP_ONLY_COMBAT_PATCH=VERIFIED" -ForegroundColor Green
Write-Host "V2_HEADER=EXACT_PRE_PHASE03" -ForegroundColor Green
Write-Host "EDITOR_BUILD_NO_UBA=PASS" -ForegroundColor Green
Write-Host "GAME_BUILD_NO_UBA=PASS" -ForegroundColor Green
Write-Host "COOK_STAGE_PACKAGE=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_PHASE_03B_COMBAT_PLAYER_V1_QA" -ForegroundColor Green
Write-Host "NO_SOURCE_CHANGES_MADE_BY_THIS_SCRIPT" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
