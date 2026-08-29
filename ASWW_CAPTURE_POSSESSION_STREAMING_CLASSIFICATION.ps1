[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location $ProjectRoot
$env:GIT_PAGER = "cat"

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Write-Host "BLOCKER=WRONG_BRANCH_$Branch" -ForegroundColor Red
    exit 10
}

$Diag = Join-Path $ProjectRoot "ASWW_DIAGNOSE_PACKAGED_POSSESSION_STREAMING.ps1"
if (-not (Test-Path -LiteralPath $Diag -PathType Leaf)) {
    Write-Host "BLOCKER=MISSING_$Diag" -ForegroundColor Red
    exit 11
}

$OutDir = Join-Path $ProjectRoot "Saved\RuntimeEvidence\PackagedRuntime"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Out = Join-Path $OutDir "possession_streaming_diag_$Stamp.txt"

$Lines = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Diag 2>&1
$Exit = $LASTEXITCODE

$Lines | Set-Content -LiteralPath $Out -Encoding UTF8

Write-Host "DIAGNOSTIC_CAPTURE=$Out" -ForegroundColor Cyan
Write-Host "DIAGNOSTIC_EXIT=$Exit"

Write-Host ""
Write-Host "=== CLASSIFICATION SIGNALS ===" -ForegroundColor Yellow

$Patterns = @(
    "SOURCE_DEFAULT_PAWN_CONFIG_SEEN=",
    "SOURCE_PLAYER_CONTROLLER_CONFIG_SEEN=",
    "SOURCE_CAMERA_CONFIG_SEEN=",
    "RUNTIME_POSSESSION_MARKER_SEEN=",
    "RUNTIME_PLAYER_CONTROLLER_MARKER_SEEN=",
    "RUNTIME_SOLDIER_MARKER_SEEN=",
    "RUNTIME_HUMMER_MARKER_SEEN=",
    "RUNTIME_HELICOPTER_MARKER_SEEN=",
    "RUNTIME_BOSS_MARKER_SEEN=",
    "RUNTIME_OBJECTIVE_MARKER_SEEN=",
    "RUNTIME_MISSION_DIRECTOR_MARKER_SEEN=",
    "RUNTIME_WORLD_BOOTSTRAP_MARKER_SEEN=",
    "RUNTIME_WORLD_PARTITION_STREAMING_MARKER_SEEN="
)

$Found = 0
foreach ($Line in $Lines) {
    $Text = [string]$Line
    foreach ($Pattern in $Patterns) {
        if ($Text -like "*$Pattern*") {
            Write-Host $Text
            $Found++
            break
        }
    }
}

if ($Exit -ne 0) {
    Write-Host "CLASSIFICATION_CAPTURE=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=DIAGNOSTIC_EXIT_$Exit" -ForegroundColor Red
    exit $Exit
}

if ($Found -eq 0) {
    Write-Host "CLASSIFICATION_CAPTURE=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=CLASSIFICATION_SIGNALS_NOT_FOUND" -ForegroundColor Red
    exit 20
}

Write-Host ""
Write-Host "CLASSIFICATION_CAPTURE=PASS" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
