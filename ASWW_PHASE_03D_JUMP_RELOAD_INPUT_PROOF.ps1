[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$StageRoot = "D:\ASWW_STAGE",
    [string]$ArchiveRoot = "D:\ASWW_ARCHIVE\JumpReloadInputProof"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_03D_JUMP_RELOAD_INPUT_PROOF=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "QA_ONLY_TELEMETRY=DO_NOT_COMMIT" -ForegroundColor Yellow
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

Set-Location $ProjectRoot
$env:GIT_PAGER = "cat"

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch"
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$BuildBat = Join-Path $UERoot "Engine\Build\BatchFiles\Build.bat"
$RunUAT = Join-Path $UERoot "Engine\Build\BatchFiles\RunUAT.bat"
$V2Cpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASPlayerCharacterV2.cpp"

foreach ($Required in @($ProjectFile,$BuildBat,$RunUAT,$V2Cpp)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

$Source = Get-Content -Raw -LiteralPath $V2Cpp

Write-Host ""
Write-Host "============================================================"
Write-Host " VERIFY CURRENT CONTROL-RECOVERY BASELINE"
Write-Host "============================================================"

$Unarmed = $Source -match "/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed"
$Rifle = $Source -match "/Game/Weapons/Rifle/Meshes/SKM_Rifle"
$CppOnly = $Source -match "ASWW_COMBAT_PLAYER_V1_CPP_ONLY_BEGIN"
$OldQA = $Source -match "ASWW_QA_JUMP_INPUT|ASWW_QA_RELOAD_INPUT"

Write-Host "ABP_UNARMED_SELECTED=$Unarmed"
Write-Host "SKM_RIFLE_SELECTED=$Rifle"
Write-Host "CPP_ONLY_COMBAT_PATCH=$CppOnly"
Write-Host "OLD_QA_MARKERS_PRESENT=$OldQA"

if (-not ($Unarmed -and $Rifle -and $CppOnly)) {
    Stop-Gate "CURRENT_SOURCE_NOT_CONTROL_RECOVERY_BASELINE" 12
}
if ($OldQA) {
    Stop-Gate "QA_MARKERS_ALREADY_PRESENT_REVIEW_BEFORE_RERUN" 13
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\JumpReloadInputProof_$Stamp"
$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\JumpReloadInputProof_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
Copy-Item -LiteralPath $V2Cpp -Destination (Join-Path $BackupRoot "ASPlayerCharacterV2.cpp.before_jump_reload_qa") -Force
Write-Host "BACKUP_ROOT=$BackupRoot"

Write-Host ""
Write-Host "============================================================"
Write-Host " ADD NARROW QA-ONLY INPUT MARKERS"
Write-Host "============================================================"

$JumpNeedle = @'
void AASPlayerCharacterV2::JumpOrMantlePressed()
{
    if (IsDowned() || IsEliminated())
'@

$JumpReplacement = @'
void AASPlayerCharacterV2::JumpOrMantlePressed()
{
    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_QA_JUMP_INPUT stance=%d falling=%d velocityZ=%.2f"),
        static_cast<int32>(MovementStance),
        GetCharacterMovement() && GetCharacterMovement()->IsFalling() ? 1 : 0,
        GetVelocity().Z);

    if (IsDowned() || IsEliminated())
'@

if ($Source.IndexOf($JumpNeedle, [StringComparison]::Ordinal) -lt 0) {
    Stop-Gate "JUMP_WRAPPER_SHAPE_NOT_FOUND" 20
}
$Source = $Source.Replace($JumpNeedle, $JumpReplacement)

$ReloadNeedle = @'
void AASPlayerCharacterV2::ReloadPressedV2()
{
    Reload();
}
'@

$ReloadReplacement = @'
void AASPlayerCharacterV2::ReloadPressedV2()
{
    UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_RELOAD_INPUT"));
    Reload();
    UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_RELOAD_DISPATCHED"));
}
'@

if ($Source.IndexOf($ReloadNeedle, [StringComparison]::Ordinal) -lt 0) {
    Stop-Gate "RELOAD_WRAPPER_SHAPE_NOT_FOUND" 21
}
$Source = $Source.Replace($ReloadNeedle, $ReloadReplacement)

[IO.File]::WriteAllText($V2Cpp, $Source, [Text.UTF8Encoding]::new($true))

$After = Get-Content -Raw -LiteralPath $V2Cpp
$JumpMarker = $After -match "ASWW_QA_JUMP_INPUT"
$ReloadMarker = $After -match "ASWW_QA_RELOAD_INPUT"
$ReloadDispatch = $After -match "ASWW_QA_RELOAD_DISPATCHED"

Write-Host "JUMP_QA_MARKER_INSTALLED=$JumpMarker"
Write-Host "RELOAD_QA_MARKER_INSTALLED=$ReloadMarker"
Write-Host "RELOAD_DISPATCH_MARKER_INSTALLED=$ReloadDispatch"

if (-not ($JumpMarker -and $ReloadMarker -and $ReloadDispatch)) {
    Stop-Gate "QA_MARKER_INSTALL_VERIFY_FAILED" 22
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 23
}

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 24
}

Write-Host ""
Write-Host "============================================================"
Write-Host " EDITOR BUILD — SERIAL / NO UBA"
Write-Host "============================================================"

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
    $Code = 30
    if ($EditorExit -gt 0) { $Code = $EditorExit }
    Stop-Gate "EDITOR_BUILD_FAILED_EXIT_$EditorExit" $Code
}

Write-Host ""
Write-Host "============================================================"
Write-Host " GAME BUILD — SERIAL / NO UBA"
Write-Host "============================================================"

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
    $Code = 31
    if ($GameExit -gt 0) { $Code = $GameExit }
    Stop-Gate "GAME_BUILD_FAILED_EXIT_$GameExit" $Code
}

Write-Host ""
Write-Host "============================================================"
Write-Host " COOK + STAGE + PACKAGE"
Write-Host "============================================================"

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRE_JUMP_RELOAD_PROOF_$Stamp"
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

& $RunUAT @UATArgs 2>&1 | Tee-Object -FilePath $PackageLog | Out-Host
$PackageExit = $LASTEXITCODE
Write-Host "PACKAGE_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Get-Content -LiteralPath $PackageLog -Tail 320
    $Code = 32
    if ($PackageExit -gt 0) { $Code = $PackageExit }
    Stop-Gate "PACKAGE_FAILED_EXIT_$PackageExit" $Code
}

$Exe = Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $Exe) {
    Stop-Gate "PACKAGED_EXE_NOT_FOUND" 33
}

Write-Host "PACKAGED_EXE=$($Exe.FullName)"
Write-Host ""
Write-Host "PHASE_03D_JUMP_RELOAD_INPUT_PROOF=PASS" -ForegroundColor Green
Write-Host "QA_ONLY_MARKERS=INSTALLED" -ForegroundColor Yellow
Write-Host "NEXT_GATE=RUN_PHASE_03D_JUMP_RELOAD_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
