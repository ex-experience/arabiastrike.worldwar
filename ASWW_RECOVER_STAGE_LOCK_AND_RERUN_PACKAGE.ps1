[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "STAGE_LOCK_RECOVERY=STOPPED" -ForegroundColor Red
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

$Pipeline = Join-Path $ProjectRoot "ASWW_PATCH_PIE_WRAPPER_AND_PACKAGE_WIN64.ps1"
if (-not (Test-Path -LiteralPath $Pipeline -PathType Leaf)) {
    Stop-Gate "MISSING_$Pipeline" 11
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY NO ACTIVE UNREAL PACKAGING PROCESSES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Names = @(
    "UnrealEditor",
    "UnrealEditor-Cmd",
    "UnrealPak",
    "ShaderCompileWorker",
    "CrashReportClient"
)

$Active = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $Names -contains $_.ProcessName })
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "UNREAL_PROCESS_STILL_RUNNING_CLOSE_IT_FIRST" 12
}

Write-Host "UNREAL_PACKAGING_PROCESSES=NONE" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " QUARANTINE LOCKED STAGING DIRECTORY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$StageDir = Join-Path $ProjectRoot "Saved\StagedBuilds\Windows"
$QuarantineRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\StageQuarantine"
New-Item -ItemType Directory -Force -Path $QuarantineRoot | Out-Null

if (Test-Path -LiteralPath $StageDir -PathType Container) {
    $Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $Quarantine = Join-Path $QuarantineRoot "Windows_failed_stage_$Stamp"

    Write-Host "STAGE_DIR=$StageDir"
    Write-Host "QUARANTINE_TARGET=$Quarantine"

    try {
        Move-Item -LiteralPath $StageDir -Destination $Quarantine -Force
        Write-Host "STAGE_DIR_QUARANTINED=True" -ForegroundColor Green
        Write-Host "STAGE_QUARANTINE=$Quarantine"
    }
    catch {
        Write-Host "STAGE_DIR_QUARANTINED=False" -ForegroundColor Red
        Write-Host "MOVE_ERROR=$($_.Exception.Message)" -ForegroundColor Red

        $OneDrive = @(Get-Process OneDrive -ErrorAction SilentlyContinue)
        if ($OneDrive.Count -gt 0) {
            Write-Host "ONEDRIVE_PROCESS=RUNNING" -ForegroundColor Yellow
            Write-Host "ACTION_REQUIRED=PAUSE_ONEDRIVE_SYNC_THEN_RERUN_THIS_SCRIPT" -ForegroundColor Yellow
        } else {
            Write-Host "ONEDRIVE_PROCESS=NOT_RUNNING"
        }

        Stop-Gate "STAGING_DIRECTORY_STILL_LOCKED" 20
    }
}
else {
    Write-Host "STAGE_DIR_NOT_PRESENT=CONTINUE" -ForegroundColor Green
}

if (Test-Path -LiteralPath $StageDir) {
    Stop-Gate "STAGE_DIRECTORY_STILL_EXISTS_AFTER_QUARANTINE" 21
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " GIT WHITESPACE GATE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 22
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RERUN WIN64 PACKAGE PIPELINE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "NOTE=INCREMENTAL_BUILD_COOK_MAY_REUSE_PREVIOUS_WORK"
Write-Host "PIPELINE=$Pipeline"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Pipeline
$Exit = $LASTEXITCODE

Write-Host ""
Write-Host "PACKAGE_PIPELINE_RERUN_EXIT=$Exit"

if ($Exit -ne 0) {
    Stop-Gate "PACKAGE_PIPELINE_RERUN_FAILED_EXIT_$Exit" $(if ($Exit -gt 0) { $Exit } else { 30 })
}

Write-Host ""
Write-Host "STAGE_LOCK_RECOVERY=PASS" -ForegroundColor Green
Write-Host "WIN64_PACKAGE_PIPELINE=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=PACKAGED_RUNTIME_STARTUP_SMOKE" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
