[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\RealMannyQA"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "REAL_MANNY_PACKAGED_QA=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

Set-Location $ProjectRoot

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

if (-not (Test-Path -LiteralPath $PackagedExe -PathType Leaf)) {
    Stop-Gate "PACKAGED_EXE_NOT_FOUND" 11
}

$Existing = @(Get-Process ArabiaStrikeWorldWar -ErrorAction SilentlyContinue)
if ($Existing.Count -gt 0) {
    $Existing | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_EXISTING_GAME_FIRST" 12
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$StdOut = Join-Path $EvidenceRoot "real_manny_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "real_manny_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REAL MANNY PACKAGED QA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "1) Click the game window." -ForegroundColor Yellow
Write-Host "2) Confirm Manny is visible instead of the gray cube." -ForegroundColor Yellow
Write-Host "3) Hold W/A/S/D and confirm the character moves." -ForegroundColor Yellow
Write-Host "4) Move the mouse and confirm the camera rotates/follows." -ForegroundColor Yellow
Write-Host "5) Confirm locomotion animation visibly updates while moving." -ForegroundColor Yellow
Write-Host "6) Close the game normally." -ForegroundColor Yellow
Write-Host ""

$Args = @(
    "-log",
    "-stdout",
    "-FullStdOutLogOutput",
    "-NoSplash",
    "-Windowed",
    "-ResX=1280",
    "-ResY=720"
)

$Proc = Start-Process `
    -FilePath $PackagedExe `
    -ArgumentList $Args `
    -WorkingDirectory (Split-Path -Parent $PackagedExe) `
    -PassThru `
    -RedirectStandardOutput $StdOut `
    -RedirectStandardError $StdErr

Write-Host "PROCESS_ID=$($Proc.Id)"
$Proc.WaitForExit()

$Text = ""
if (Test-Path -LiteralPath $StdOut) {
    $Text += Get-Content -Raw -LiteralPath $StdOut
}
if (Test-Path -LiteralPath $StdErr) {
    $Text += "`n" + (Get-Content -Raw -LiteralPath $StdErr)
}

$Manny = $Text -match "ASWW_REAL_PLAYER_MANNY"
$Move = $Text -match "ASWW_MOVE_STATE AFTER"
$Input = $Text -match "ASWW_TELEMETRY AXIS_MOVEFORWARD|ASWW_TELEMETRY AXIS_MOVERIGHT"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Crash = $Text -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REAL MANNY LOG CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "REAL_MANNY_MARKER_SEEN=$Manny"
Write-Host "MOVEMENT_INPUT_SEEN=$Input"
Write-Host "ACTOR_MOVEMENT_SEEN=$Move"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"

if (Test-Path -LiteralPath $StdOut) {
    Write-Host ""
    Write-Host "=== REAL MANNY / MOVEMENT LINES ===" -ForegroundColor Yellow
    Select-String -LiteralPath $StdOut -Pattern "ASWW_REAL_PLAYER_MANNY|ASWW_MOVE_STATE|ASWW_TELEMETRY" |
        Select-Object -First 140
}

if ($Fatal -or $Crash) {
    Write-Host "REAL_MANNY_RUNTIME_LOG_HEALTH=FAIL" -ForegroundColor Red
} elseif ($Manny -and $Move) {
    Write-Host "REAL_MANNY_RUNTIME_LOG_HEALTH=PASS" -ForegroundColor Green
} else {
    Write-Host "REAL_MANNY_RUNTIME_LOG_HEALTH=INCONCLUSIVE" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "REPORT_VISUAL_RESULT_AS:" -ForegroundColor Cyan
Write-Host "MANNY_VISIBLE=YES/NO"
Write-Host "MANNY_MOVES_WITH_WASD=YES/NO"
Write-Host "MANNY_ANIMATES_WHILE_MOVING=YES/NO"
Write-Host "CAMERA_ROTATES_WITH_MOUSE=YES/NO"
Write-Host "CAMERA_FOLLOWS_MANNY=YES/NO"
Write-Host "FIRST_VISIBLE_BLOCKER=<what you saw>"
Write-Host ""
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
