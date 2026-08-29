[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\MovementTelemetry"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "MOVEMENT_TELEMETRY_RUN=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_COMMIT_TELEMETRY" -ForegroundColor Yellow
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
$StdOut = Join-Path $EvidenceRoot "movement_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "movement_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " MOVEMENT TELEMETRY RUN" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "1) Click inside the game window." -ForegroundColor Yellow
Write-Host "2) Hold W for ~3 seconds." -ForegroundColor Yellow
Write-Host "3) Hold D for ~3 seconds." -ForegroundColor Yellow
Write-Host "4) Move mouse left/right." -ForegroundColor Yellow
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
Write-Host "MOVEMENT_TELEMETRY_SESSION=STARTED" -ForegroundColor Green

$Proc.WaitForExit()

$Out = if (Test-Path -LiteralPath $StdOut) { Get-Content -Raw -LiteralPath $StdOut } else { "" }
$Err = if (Test-Path -LiteralPath $StdErr) { Get-Content -Raw -LiteralPath $StdErr } else { "" }
$Text = $Out + "`n" + $Err

$Begin = $Text -match "ASWW_MOVE_STATE BEGIN"
$Input = $Text -match "ASWW_MOVE_STATE INPUT"
$After = $Text -match "ASWW_MOVE_STATE AFTER"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LogWindows:\s*Error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Crash = $Text -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"

$Deltas = @()
$Matches = [regex]::Matches($Text, 'ASWW_MOVE_STATE AFTER .*? delta=([0-9]+(?:\.[0-9]+)?)')
foreach ($M in $Matches) {
    $Deltas += [double]$M.Groups[1].Value
}

$MaxDelta = if ($Deltas.Count -gt 0) { ($Deltas | Measure-Object -Maximum).Maximum } else { 0.0 }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " MOVEMENT CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "BEGIN_STATE_SEEN=$Begin"
Write-Host "MOVEMENT_INPUT_STATE_SEEN=$Input"
Write-Host "AFTER_MOVE_STATE_SEEN=$After"
Write-Host "MAX_NEXT_TICK_DELTA=$MaxDelta"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"

Write-Host ""
Write-Host "=== MOVEMENT TELEMETRY LINES ===" -ForegroundColor Yellow
if (Test-Path -LiteralPath $StdOut) {
    Select-String -LiteralPath $StdOut -Pattern "ASWW_MOVE_STATE|ASWW_TELEMETRY" | Select-Object -First 120
}

Write-Host ""
if ($Fatal -or $Crash) {
    Write-Host "MOVEMENT_ROOT_CLASSIFICATION=RUNTIME_FATAL_OR_CRASH" -ForegroundColor Red
}
elseif (-not $Begin) {
    Write-Host "MOVEMENT_ROOT_CLASSIFICATION=CHARACTER_BEGIN_STATE_NOT_CAPTURED" -ForegroundColor Red
}
elseif (-not $Input) {
    Write-Host "MOVEMENT_ROOT_CLASSIFICATION=MOVEMENT_FUNCTION_NOT_REACHED" -ForegroundColor Red
}
elseif (-not $After) {
    Write-Host "MOVEMENT_ROOT_CLASSIFICATION=MOVEMENT_AFTER_PROBE_NOT_EXECUTED" -ForegroundColor Red
}
elseif ($MaxDelta -lt 1.0) {
    Write-Host "MOVEMENT_ROOT_CLASSIFICATION=INPUT_REACHES_CHARACTER_BUT_ACTOR_POSITION_STAYS_FIXED" -ForegroundColor Red
    Write-Host "NEXT_GATE=INSPECT_MOVEMENT_MODE_FLOOR_COLLISION_AND_ROOT_COMPONENT" -ForegroundColor Yellow
}
else {
    Write-Host "MOVEMENT_ROOT_CLASSIFICATION=ACTOR_POSITION_CHANGES" -ForegroundColor Green
    Write-Host "NEXT_GATE=VISUAL_CONTROL_FAILURE_IS_CAMERA_OR_PRESENTATION_NOT_MOVEMENT" -ForegroundColor Yellow
}

Write-Host "MOVEMENT_TELEMETRY_RUN=PASS_DIAGNOSTIC_COMPLETED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_TELEMETRY" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
