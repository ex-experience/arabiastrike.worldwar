[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location $ProjectRoot

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    throw "WRONG_BRANCH_STOP"
}

$PieScript = Join-Path $ProjectRoot "BuildScripts\run_jeddah_pie_smoke.ps1"
if (-not (Test-Path -LiteralPath $PieScript -PathType Leaf)) {
    throw "PIE_SCRIPT_NOT_FOUND=$PieScript"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PIE EXIT 5 — SCRIPT LOGIC" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Select-String -LiteralPath $PieScript `
    -Pattern "exit\s+5|PIE_|SMOKE|MARKER|SUCCESS|FAIL|LogPath|RuntimeEvidence|ExecutePythonScript|UnrealEditor" `
    -Context 6,14 |
    Select-Object -First 160

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RECENT PIE / UNREAL LOG CANDIDATES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Roots = @(
    (Join-Path $ProjectRoot "Saved\RuntimeEvidence"),
    (Join-Path $ProjectRoot "Saved\Logs"),
    (Join-Path $ProjectRoot "Saved\Verification")
) | Where-Object { Test-Path -LiteralPath $_ -PathType Container }

$Candidates = @()
foreach ($Root in $Roots) {
    $Candidates += Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension -in @(".log",".txt") -and
            $_.LastWriteTime -gt (Get-Date).AddHours(-6)
        }
}

$Candidates = $Candidates |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 40

if (-not $Candidates) {
    Write-Host "RECENT_LOGS=NONE" -ForegroundColor Yellow
}
else {
    $Candidates |
        Select-Object LastWriteTime,Length,FullName |
        Format-Table -AutoSize
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host " PIE ROOT CAUSE MATCHES" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow

$Patterns = @(
    "ASWW_PIE",
    "PIE_SMOKE",
    "PIE ",
    "Play in editor",
    "LogPlayLevel",
    "LogPython: Error",
    "Traceback",
    "RuntimeError:",
    "AttributeError:",
    "TypeError:",
    "Assertion failed",
    "Fatal error",
    "Error:",
    "failed",
    "missing",
    "PlayerStart",
    "ASGameMode",
    "MissionDirector",
    "WorldBootstrap",
    "Hummer",
    "Helicopter",
    "CommandMech",
    "Extraction",
    "Possess",
    "spawn",
    "NavMesh"
)

$Printed = 0
foreach ($File in $Candidates) {
    $Matches = Select-String -LiteralPath $File.FullName -Pattern $Patterns -Context 4,12 -ErrorAction SilentlyContinue
    if ($Matches) {
        Write-Host ""
        Write-Host "----- FILE: $($File.FullName) -----" -ForegroundColor Cyan
        $Matches | Select-Object -First 80
        $Printed++
        if ($Printed -ge 8) { break }
    }
}

if ($Printed -eq 0) {
    Write-Host "ROOT_CAUSE_MATCHES=NONE_IN_RECENT_LOGS" -ForegroundColor Red
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " NEXT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PIE_DIAGNOSTIC=COMPLETE" -ForegroundColor Green
Write-Host "SEND_BACK=THE_SECTION_NAMED_PIE_ROOT_CAUSE_MATCHES_AND_THE_EXIT_5_LOGIC" -ForegroundColor Yellow
Write-Host "DO_NOT_RERUN_PROMOTION_OR_VALIDATOR_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
