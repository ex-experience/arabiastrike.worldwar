[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "WIN64_PACKAGE_PIPELINE=STOPPED" -ForegroundColor Red
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
$PieWrapper = Join-Path $ProjectRoot "BuildScripts\run_jeddah_pie_smoke.ps1"
$BuildScript = Join-Path $ProjectRoot "BuildScripts\build_win64.ps1"
$PieRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\PIE"
$AuditRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\JeddahMap"
$PackageEvidence = Join-Path $ProjectRoot "Saved\RuntimeEvidence\Package"

foreach ($Required in @($ProjectFile,$PieWrapper,$BuildScript)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_$Required" 11
    }
}

$RunningEditors = @(Get-Process UnrealEditor,UnrealEditor-Cmd -ErrorAction SilentlyContinue)
if ($RunningEditors.Count -gt 0) {
    $RunningEditors | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ALL_UNREAL_EDITOR_PROCESSES_FIRST" 12
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PRE-PACKAGE EVIDENCE GATES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$LatestPie = Get-ChildItem -LiteralPath $PieRoot -Filter "pie_exact_*.log" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $LatestPie) {
    Stop-Gate "LATEST_EXACT_PIE_LOG_NOT_FOUND" 20
}

$PieText = Get-Content -Raw -LiteralPath $LatestPie.FullName
$PieMarker = $PieText -match "ASWW_PIE_SMOKE=PASS"
$PieFail = $PieText -match "Test Completed\. Result=\{Fail\}|RuntimeError: PIE did not load|LogPython:\s*Error"

Write-Host "LATEST_EXACT_PIE_LOG=$($LatestPie.FullName)"
Write-Host "PIE_SUCCESS_MARKER=$PieMarker"
Write-Host "PIE_FAILURE_MARKER=$PieFail"

if (-not $PieMarker -or $PieFail) {
    Stop-Gate "LATEST_EXACT_PIE_NOT_CLEAN_PASS" 21
}

$LatestAudit = Get-ChildItem -LiteralPath $AuditRoot -Filter "audit_duplicate_prototypes_*.log" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $LatestAudit) {
    Stop-Gate "LATEST_DUPLICATE_AUDIT_LOG_NOT_FOUND" 22
}

$AuditText = Get-Content -Raw -LiteralPath $LatestAudit.FullName
$AuditPass = $AuditText -match "ASWW_DUPLICATE_AUDIT=PASS"
$DuplicatesNone = $AuditText -match "ASWW_AUDIT_DUPLICATE_LABELS=NONE"
$MissingNone = $AuditText -match "ASWW_AUDIT_MISSING_LABELS=NONE"

Write-Host "LATEST_DUPLICATE_AUDIT=$($LatestAudit.FullName)"
Write-Host "DUPLICATE_AUDIT_PASS=$AuditPass"
Write-Host "DUPLICATE_LABELS_NONE=$DuplicatesNone"
Write-Host "MISSING_LABELS_NONE=$MissingNone"

if (-not $AuditPass -or -not $DuplicatesNone -or -not $MissingNone) {
    Stop-Gate "PREPACKAGE_DUPLICATE_GATE_NOT_CLEAN" 23
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PATCH PERMANENT PIE WRAPPER TO EXACT TEST" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$ExactTest = "Editor.Python.ArabiaStrikeWorldWar.test_asww_jeddah_pie"
$OldCommand = "Automation RunTest Group:ASWWPIE;Quit"
$NewCommand = "Automation RunTest $ExactTest;Quit"

$WrapperText = Get-Content -Raw -LiteralPath $PieWrapper
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ProjectRoot "Saved\Verification\FixBackups\PieWrapperExactTest_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $PieWrapper -Destination (Join-Path $BackupDir "run_jeddah_pie_smoke.ps1") -Force

if ($WrapperText.Contains($NewCommand)) {
    Write-Host "PIE_WRAPPER_PATCH=ALREADY_PRESENT" -ForegroundColor Green
}
elseif ($WrapperText.Contains($OldCommand)) {
    $Patched = $WrapperText.Replace($OldCommand, $NewCommand)
    [IO.File]::WriteAllText($PieWrapper, $Patched, [Text.UTF8Encoding]::new($true))
    Write-Host "PIE_WRAPPER_PATCH=APPLIED" -ForegroundColor Green
    Write-Host "PIE_WRAPPER_BACKUP=$BackupDir"
}
else {
    Stop-Gate "PIE_WRAPPER_EXPECTED_COMMAND_NOT_FOUND" 24
}

$PostWrapper = Get-Content -Raw -LiteralPath $PieWrapper
if (-not $PostWrapper.Contains($NewCommand)) {
    Stop-Gate "PIE_WRAPPER_EXACT_TEST_NOT_PRESENT_AFTER_PATCH" 25
}

Write-Host "PIE_WRAPPER_EXACT_TEST=$ExactTest"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " GIT WHITESPACE GATE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 26
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REAL WIN64 PACKAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $PackageEvidence | Out-Null
$PackageStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$PackageLog = Join-Path $PackageEvidence "build_win64_$PackageStamp.log"

Write-Host "BUILD_SCRIPT=$BuildScript"
Write-Host "PACKAGE_LOG=$PackageLog"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BuildScript 2>&1 |
    Tee-Object -FilePath $PackageLog
$PackageExit = $LASTEXITCODE

Write-Host ""
Write-Host "PACKAGE_SCRIPT_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Write-Host ""
    Write-Host "=== PACKAGE FAILURE TAIL ===" -ForegroundColor Yellow
    Get-Content -LiteralPath $PackageLog -Tail 180
    Stop-Gate "BUILD_WIN64_SCRIPT_FAILED_EXIT_$PackageExit" $(if ($PackageExit -gt 0) { $PackageExit } else { 30 })
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " LOCATE REAL PACKAGED EXE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$CandidateRoots = @(
    (Join-Path $ProjectRoot "Saved\StagedBuilds"),
    (Join-Path $ProjectRoot "Packaged"),
    (Join-Path $ProjectRoot "Build\Packages"),
    (Join-Path $ProjectRoot "Builds"),
    (Join-Path $ProjectRoot "Dist")
) | Where-Object { Test-Path -LiteralPath $_ -PathType Container }

$Candidates = @()
foreach ($Root in $CandidateRoots) {
    $Candidates += Get-ChildItem -LiteralPath $Root -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue
}

# Fallback: search the project, but explicitly reject ordinary development binaries.
if ($Candidates.Count -eq 0) {
    $Candidates = Get-ChildItem -LiteralPath $ProjectRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch "\\Binaries\\Win64\\" -and
            $_.FullName -notmatch "\\Intermediate\\"
        }
}

$Candidates = $Candidates |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Unique

foreach ($Exe in $Candidates) {
    Write-Host "PACKAGED_EXE_CANDIDATE=$($Exe.FullName)"
}

if ($Candidates.Count -eq 0) {
    Stop-Gate "PACKAGE_EXIT_0_BUT_PACKAGED_EXE_NOT_FOUND" 31
}

$PackagedExe = $Candidates | Select-Object -First 1

# A packaged layout should have a nearby Engine folder and/or Content\Paks.
$ExeDir = $PackagedExe.Directory.FullName
$LayoutRoot = Split-Path $ExeDir -Parent
$HasEngine = Test-Path -LiteralPath (Join-Path $LayoutRoot "Engine") -PathType Container
$HasPaksNearExe = Test-Path -LiteralPath (Join-Path $ExeDir "ArabiaStrikeWorldWar\Content\Paks") -PathType Container
$HasPaksAtRoot = Test-Path -LiteralPath (Join-Path $LayoutRoot "ArabiaStrikeWorldWar\Content\Paks") -PathType Container
$HasPackagedLayout = $HasEngine -or $HasPaksNearExe -or $HasPaksAtRoot

Write-Host "PACKAGED_EXE=$($PackagedExe.FullName)" -ForegroundColor Green
Write-Host "PACKAGED_LAYOUT_CONFIRMED=$HasPackagedLayout"

if (-not $HasPackagedLayout) {
    Stop-Gate "EXE_FOUND_BUT_PACKAGED_LAYOUT_NOT_CONFIRMED" 32
}

Write-Host ""
Write-Host "WIN64_PACKAGE=PASS" -ForegroundColor Green
Write-Host "PACKAGED_EXE_VERIFIED=YES" -ForegroundColor Green
Write-Host "NEXT_GATE=PACKAGED_RUNTIME_STARTUP_SMOKE" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
