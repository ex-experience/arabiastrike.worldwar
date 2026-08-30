[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\VisiblePlayerProof"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "VISIBLE_PLAYER_PROOF_QA=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_COMMIT_VISUAL_PROOF_OR_TELEMETRY" -ForegroundColor Yellow
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
$StdOut = Join-Path $EvidenceRoot "visible_player_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "visible_player_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TEMP VISIBLE PLAYER PROOF QA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "A gray rectangular body should now represent the player." -ForegroundColor Yellow
Write-Host ""
Write-Host "1) Click once inside the game window." -ForegroundColor Yellow
Write-Host "2) Hold W, then A/S/D." -ForegroundColor Yellow
Write-Host "3) Move mouse left/right and up/down." -ForegroundColor Yellow
Write-Host "4) Observe whether the gray body moves and whether the camera follows/rotates." -ForegroundColor Yellow
Write-Host "5) Close the game normally." -ForegroundColor Yellow
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
Write-Host "VISIBLE_PLAYER_PROOF_SESSION=STARTED" -ForegroundColor Green

$Proc.WaitForExit()

$Out = if (Test-Path -LiteralPath $StdOut) { Get-Content -Raw -LiteralPath $StdOut } else { "" }
$Err = if (Test-Path -LiteralPath $StdErr) { Get-Content -Raw -LiteralPath $StdErr } else { "" }
$Text = $Out + "`n" + $Err

$Proof = $Text -match "ASWW_VISUAL_PROOF"
$Input = $Text -match "ASWW_TELEMETRY AXIS_MOVEFORWARD|ASWW_TELEMETRY AXIS_MOVERIGHT"
$Move = $Text -match "ASWW_MOVE_STATE AFTER"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LogWindows:\s*Error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Crash = $Text -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VISIBLE PLAYER PROOF LOG CHECK" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "VISUAL_PROOF_COMPONENT_LOGGED=$Proof"
Write-Host "MOVEMENT_INPUT_LOGGED=$Input"
Write-Host "ACTOR_MOVEMENT_LOGGED=$Move"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"

Write-Host ""
Write-Host "=== VISUAL / MOVEMENT LOG LINES ===" -ForegroundColor Yellow
if (Test-Path -LiteralPath $StdOut) {
    Select-String -LiteralPath $StdOut -Pattern "ASWW_VISUAL_PROOF|ASWW_MOVE_STATE|ASWW_TELEMETRY" |
        Select-Object -First 120
}

Write-Host ""
if ($Fatal -or $Crash) {
    Write-Host "VISIBLE_PLAYER_PROOF_LOG_HEALTH=FAIL" -ForegroundColor Red
} elseif ($Proof -and $Move) {
    Write-Host "VISIBLE_PLAYER_PROOF_LOG_HEALTH=PASS" -ForegroundColor Green
} else {
    Write-Host "VISIBLE_PLAYER_PROOF_LOG_HEALTH=INCONCLUSIVE" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "REPORT_VISUAL_RESULT_AS:" -ForegroundColor Cyan
Write-Host "VISIBLE_BODY=YES/NO"
Write-Host "BODY_MOVES_WITH_WASD=YES/NO"
Write-Host "CAMERA_ROTATES_WITH_MOUSE=YES/NO"
Write-Host "CAMERA_FOLLOWS_BODY=YES/NO"
Write-Host "FIRST_VISIBLE_BLOCKER=<what you saw>"
Write-Host ""
Write-Host "DO_NOT_COMMIT_VISUAL_PROOF_OR_TELEMETRY" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
