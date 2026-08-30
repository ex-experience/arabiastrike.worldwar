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
    Write-Host "CLEAN_REAL_MANNY_PACKAGE=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Replace-ExactlyOnce {
    param(
        [string]$Label,
        [string]$Pattern,
        [string]$Replacement
    )

    $Rx = [regex]::new(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Multiline -bor
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $Count = $Rx.Matches($script:Text).Count
    Write-Host "${Label}_MATCH_COUNT=$Count"

    if ($Count -ne 1) {
        Stop-Gate "EXPECTED_EXACTLY_ONE_$Label`_FOUND_$Count" 20
    }

    $script:Text = $Rx.Replace($script:Text, $Replacement, 1)
}

Set-Location $ProjectRoot
$env:GIT_PAGER = "cat"

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

$CharacterCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"
$BuildScript = Join-Path $ProjectRoot "BuildScripts\build_win64.ps1"

foreach ($Required in @($CharacterCpp,$BuildScript)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

$Original = Get-Content -Raw -LiteralPath $CharacterCpp

$PreTelemetry = ([regex]::Matches($Original, "ASWW_TELEMETRY")).Count
$PreMoveState = ([regex]::Matches($Original, "ASWW_MOVE_STATE")).Count
$PreVisual = ([regex]::Matches($Original, "ASWW_VISUAL_PROOF|ASWW_PlayerVisualProof")).Count
$PreManny = ([regex]::Matches($Original, "ASWW_REAL_PLAYER_MANNY")).Count

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PRE-CLEANUP MARKER COUNTS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "ASWW_TELEMETRY_COUNT=$PreTelemetry"
Write-Host "ASWW_MOVE_STATE_COUNT=$PreMoveState"
Write-Host "TEMP_VISUAL_PROOF_COUNT=$PreVisual"
Write-Host "ASWW_REAL_PLAYER_MANNY_COUNT=$PreManny"

if ($PreTelemetry -ne 17) {
    Stop-Gate "UNEXPECTED_ASWW_TELEMETRY_COUNT_$PreTelemetry" 12
}
if ($PreMoveState -ne 5) {
    Stop-Gate "UNEXPECTED_ASWW_MOVE_STATE_COUNT_$PreMoveState" 13
}
if ($PreVisual -ne 0) {
    Stop-Gate "TEMP_VISUAL_PROOF_STILL_PRESENT_$PreVisual" 14
}
if ($PreManny -ne 1) {
    Stop-Gate "REAL_MANNY_MARKER_COUNT_NOT_ONE_$PreManny" 15
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\TempTelemetryCleanup_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
Copy-Item -LiteralPath $CharacterCpp -Destination (Join-Path $BackupRoot "ASCharacter.cpp.before_cleanup") -Force
Write-Host "CLEANUP_BACKUP=$BackupRoot"

$script:Text = $Original
$NL = [Environment]::NewLine

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REMOVE ONLY TEMPORARY QA TELEMETRY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# BeginPlay movement-state probe block.
Replace-ExactlyOnce `
    -Label "BEGINPLAY_MOVE_STATE" `
    -Pattern '^\s{4}\{\r?\n\s{8}const UCharacterMovementComponent\* ASWWMove = GetCharacterMovement\(\);\r?\n\s{8}UE_LOG\(LogTemp, Warning,\r?\n\s{12}TEXT\("ASWW_MOVE_STATE BEGIN.*?^\s{4}\}\r?\n' `
    -Replacement ""

# BeginPlay CHARACTER_BEGIN telemetry statement.
Replace-ExactlyOnce `
    -Label "BEGINPLAY_CHARACTER_TELEMETRY" `
    -Pattern '^\s{4}UE_LOG\(LogTemp, Warning, TEXT\("ASWW_TELEMETRY CHARACTER_BEGIN.*?^\s{8}\*GetActorLocation\(\)\.ToCompactString\(\)\);\r?\n' `
    -Replacement ""

# Tick one-shot controller telemetry block.
Replace-ExactlyOnce `
    -Label "TICK_CONTROLLER_TELEMETRY" `
    -Pattern '^\s{4}if \(Controller && !Tags\.Contains\(FName\(TEXT\("ASWW_Telemetry_ControllerSeen"\)\)\)\)\r?\n\s{4}\{\r?\n.*?^\s{4}\}\r?\n' `
    -Replacement ""

# SetupPlayerInputComponent log statement.
Replace-ExactlyOnce `
    -Label "INPUT_SETUP_TELEMETRY" `
    -Pattern '^\s{4}UE_LOG\(LogTemp, Warning, TEXT\("ASWW_TELEMETRY INPUT_SETUP.*?^\s{8}IsLocallyControlled\(\) \? 1 : 0, IsPlayerControlled\(\) \? 1 : 0\);\r?\n' `
    -Replacement ""

# MoveForward movement-state probe.
Replace-ExactlyOnce `
    -Label "MOVEFORWARD_MOVE_STATE" `
    -Pattern '^\s{4}if \(FMath::Abs\(Value\) > KINDA_SMALL_NUMBER && !Tags\.Contains\(FName\(TEXT\("ASWW_MoveState_MoveForward"\)\)\)\)\r?\n\s{4}\{\r?\n.*?^\s{4}\}\r?\n(?=\s{4}if \(FMath::Abs\(Value\) > KINDA_SMALL_NUMBER && !Tags\.Contains\(FName\(TEXT\("ASWW_Telemetry_AXIS_MOVEFORWARD"\)\)\)\))' `
    -Replacement ""

# MoveForward axis telemetry.
Replace-ExactlyOnce `
    -Label "MOVEFORWARD_AXIS_TELEMETRY" `
    -Pattern '^\s{4}if \(FMath::Abs\(Value\) > KINDA_SMALL_NUMBER && !Tags\.Contains\(FName\(TEXT\("ASWW_Telemetry_AXIS_MOVEFORWARD"\)\)\)\)\r?\n\s{4}\{\r?\n.*?^\s{4}\}\r?\n' `
    -Replacement ""

# MoveRight movement-state probe.
Replace-ExactlyOnce `
    -Label "MOVERIGHT_MOVE_STATE" `
    -Pattern '^\s{4}if \(FMath::Abs\(Value\) > KINDA_SMALL_NUMBER && !Tags\.Contains\(FName\(TEXT\("ASWW_MoveState_MoveRight"\)\)\)\)\r?\n\s{4}\{\r?\n.*?^\s{4}\}\r?\n(?=\s{4}if \(FMath::Abs\(Value\) > KINDA_SMALL_NUMBER && !Tags\.Contains\(FName\(TEXT\("ASWW_Telemetry_AXIS_MOVERIGHT"\)\)\)\))' `
    -Replacement ""

# MoveRight axis telemetry.
Replace-ExactlyOnce `
    -Label "MOVERIGHT_AXIS_TELEMETRY" `
    -Pattern '^\s{4}if \(FMath::Abs\(Value\) > KINDA_SMALL_NUMBER && !Tags\.Contains\(FName\(TEXT\("ASWW_Telemetry_AXIS_MOVERIGHT"\)\)\)\)\r?\n\s{4}\{\r?\n.*?^\s{4}\}\r?\n' `
    -Replacement ""

# Turn axis telemetry.
Replace-ExactlyOnce `
    -Label "TURN_AXIS_TELEMETRY" `
    -Pattern '^\s{4}if \(FMath::Abs\(Value\) > KINDA_SMALL_NUMBER && !Tags\.Contains\(FName\(TEXT\("ASWW_Telemetry_AXIS_TURN"\)\)\)\)\r?\n\s{4}\{\r?\n.*?^\s{4}\}\r?\n' `
    -Replacement ""

# LookUp axis telemetry.
Replace-ExactlyOnce `
    -Label "LOOKUP_AXIS_TELEMETRY" `
    -Pattern '^\s{4}if \(FMath::Abs\(Value\) > KINDA_SMALL_NUMBER && !Tags\.Contains\(FName\(TEXT\("ASWW_Telemetry_AXIS_LOOKUP"\)\)\)\)\r?\n\s{4}\{\r?\n.*?^\s{4}\}\r?\n' `
    -Replacement ""

# The capsule include was introduced only for movement telemetry.
# Remove it only if there is no remaining GetCapsuleComponent call.
if ($script:Text -notmatch 'GetCapsuleComponent\s*\(') {
    $Before = $script:Text
    $script:Text = [regex]::Replace(
        $script:Text,
        '(?m)^\s*#include "Components/CapsuleComponent\.h"\r?\n',
        '',
        1
    )
    Write-Host "CAPSULE_INCLUDE_REMOVED=$($Before -ne $script:Text)"
}
else {
    Write-Host "CAPSULE_INCLUDE_REMOVED=False"
    Write-Host "CAPSULE_INCLUDE_REASON=STILL_USED_OUTSIDE_TEMP_TELEMETRY"
}

$PostTelemetry = ([regex]::Matches($script:Text, "ASWW_TELEMETRY")).Count
$PostMoveState = ([regex]::Matches($script:Text, "ASWW_MOVE_STATE")).Count
$PostTelemetryTags = ([regex]::Matches($script:Text, "ASWW_Telemetry_")).Count
$PostMoveTags = ([regex]::Matches($script:Text, "ASWW_MoveState_")).Count
$PostVisual = ([regex]::Matches($script:Text, "ASWW_VISUAL_PROOF|ASWW_PlayerVisualProof")).Count
$PostManny = ([regex]::Matches($script:Text, "ASWW_REAL_PLAYER_MANNY")).Count

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " IN-MEMORY POST-CLEANUP VALIDATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "ASWW_TELEMETRY_COUNT=$PostTelemetry"
Write-Host "ASWW_MOVE_STATE_COUNT=$PostMoveState"
Write-Host "ASWW_TELEMETRY_TAG_COUNT=$PostTelemetryTags"
Write-Host "ASWW_MOVESTATE_TAG_COUNT=$PostMoveTags"
Write-Host "TEMP_VISUAL_PROOF_COUNT=$PostVisual"
Write-Host "ASWW_REAL_PLAYER_MANNY_COUNT=$PostManny"

if ($PostTelemetry -ne 0 -or
    $PostMoveState -ne 0 -or
    $PostTelemetryTags -ne 0 -or
    $PostMoveTags -ne 0 -or
    $PostVisual -ne 0 -or
    $PostManny -ne 1) {
    Stop-Gate "POST_CLEANUP_MARKER_VALIDATION_FAILED_NOT_WRITTEN" 30
}

[IO.File]::WriteAllText($CharacterCpp, $script:Text, [Text.UTF8Encoding]::new($true))

Write-Host "SOURCE_CLEANUP_WRITE=PASS" -ForegroundColor Green

# Re-read from disk.
$DiskText = Get-Content -Raw -LiteralPath $CharacterCpp

$DiskTemp = ([regex]::Matches(
    $DiskText,
    'ASWW_TELEMETRY|ASWW_MOVE_STATE|ASWW_Telemetry_|ASWW_MoveState_|ASWW_VISUAL_PROOF|ASWW_PlayerVisualProof'
)).Count
$DiskManny = ([regex]::Matches($DiskText, 'ASWW_REAL_PLAYER_MANNY')).Count

Write-Host "DISK_TEMP_QA_MARKER_COUNT=$DiskTemp"
Write-Host "DISK_REAL_MANNY_MARKER_COUNT=$DiskManny"

if ($DiskTemp -ne 0 -or $DiskManny -ne 1) {
    Stop-Gate "DISK_MARKER_VALIDATION_FAILED" 31
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED_AFTER_CLEANUP" 32
}

Write-Host ""
Write-Host "TEMP_QA_TELEMETRY_CLEANUP=PASS" -ForegroundColor Green
Write-Host "REAL_MANNY_KEPT=YES" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLEAN BUILD + COOK + PACKAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 33
}

$PackageStart = Get-Date

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRECLEAN_$Stamp"
    try {
        Move-Item -LiteralPath $StageRoot -Destination $OldStage
        Write-Host "OLD_STAGE_MOVED=$OldStage"
    }
    catch {
        Stop-Gate "STAGE_ROOT_LOCKED_$($_.Exception.Message)" 34
    }
}

$PackageEvidence = Join-Path $ProjectRoot "Saved\RuntimeEvidence\CleanRealMannyPackage"
New-Item -ItemType Directory -Force -Path $PackageEvidence | Out-Null
$PackageLog = Join-Path $PackageEvidence "clean_real_manny_package_$Stamp.log"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BuildScript -UERoot $UERoot 2>&1 |
    Tee-Object -FilePath $PackageLog
$PackageExit = $LASTEXITCODE

Write-Host "PACKAGE_SCRIPT_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Write-Host ""
    Write-Host "=== PACKAGE FAILURE TAIL ===" -ForegroundColor Yellow
    Get-Content -LiteralPath $PackageLog -Tail 180
    Stop-Gate "BUILD_WIN64_FAILED_EXIT_$PackageExit" $(if ($PackageExit -gt 0) { $PackageExit } else { 40 })
}

$Exes = @(
    Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
)

if ($Exes.Count -eq 0) {
    Stop-Gate "PACKAGE_EXIT_ZERO_BUT_EXE_NOT_FOUND" 41
}

$Exe = $Exes[0]
$FreshExe = $Exe.LastWriteTime -ge $PackageStart.AddMinutes(-1)

$Containers = @(
    Get-ChildItem -LiteralPath $StageRoot -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @(".pak",".utoc",".ucas") }
)

Write-Host "PACKAGED_EXE=$($Exe.FullName)"
Write-Host "PACKAGED_EXE_LASTWRITE=$($Exe.LastWriteTime.ToString("s"))"
Write-Host "PACKAGED_EXE_FRESH=$FreshExe"
Write-Host "CONTAINER_FILE_COUNT=$($Containers.Count)"

if (-not $FreshExe -or $Containers.Count -eq 0) {
    Stop-Gate "PACKAGED_OUTPUT_NOT_FRESH_OR_NO_CONTAINERS" 42
}

Write-Host ""
Write-Host "CLEAN_REAL_MANNY_PACKAGE=PASS" -ForegroundColor Green
Write-Host "TEMP_QA_TELEMETRY=REMOVED" -ForegroundColor Green
Write-Host "REAL_MANNY=KEPT" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_CLEAN_REAL_MANNY_PACKAGED_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
