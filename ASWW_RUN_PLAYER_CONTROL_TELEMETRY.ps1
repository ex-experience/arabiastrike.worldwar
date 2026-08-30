[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\PlayerControlTelemetry"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PLAYER_CONTROL_TELEMETRY_RUN=STOPPED" -ForegroundColor Red
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

if (-not (Test-Path -LiteralPath $PackagedExe -PathType Leaf)) {
    Stop-Gate "PACKAGED_EXE_NOT_FOUND_$PackagedExe" 11
}

$Existing = @(Get-Process ArabiaStrikeWorldWar -ErrorAction SilentlyContinue)
if ($Existing.Count -gt 0) {
    $Existing | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_EXISTING_PACKAGED_GAME_FIRST" 12
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$StdOut = Join-Path $EvidenceRoot "control_telemetry_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "control_telemetry_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PLAYER CONTROL TELEMETRY RUN" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "STDOUT_LOG=$StdOut"
Write-Host ""
Write-Host "When the game opens:" -ForegroundColor Yellow
Write-Host "1) CLICK ONCE INSIDE THE GAME WINDOW." -ForegroundColor Yellow
Write-Host "2) Hold W for 2 seconds, then S, A, D." -ForegroundColor Yellow
Write-Host "3) Move the mouse left/right and up/down." -ForegroundColor Yellow
Write-Host "4) Then close the game normally." -ForegroundColor Yellow
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
Write-Host "PLAYER_CONTROL_TELEMETRY_SESSION=STARTED" -ForegroundColor Green

$Proc.WaitForExit()
$ExitCode = $Proc.ExitCode

$Out = if (Test-Path -LiteralPath $StdOut) { Get-Content -Raw -LiteralPath $StdOut } else { "" }
$Err = if (Test-Path -LiteralPath $StdErr) { Get-Content -Raw -LiteralPath $StdErr } else { "" }
$Text = $Out + "`n" + $Err

$CharBegin = $Text -match "ASWW_TELEMETRY CHARACTER_BEGIN"
$Controller = $Text -match "ASWW_TELEMETRY CONTROLLER_SEEN"
$InputSetup = $Text -match "ASWW_TELEMETRY INPUT_SETUP"
$Forward = $Text -match "ASWW_TELEMETRY AXIS_MOVEFORWARD"
$Right = $Text -match "ASWW_TELEMETRY AXIS_MOVERIGHT"
$Turn = $Text -match "ASWW_TELEMETRY AXIS_TURN"
$LookUp = $Text -match "ASWW_TELEMETRY AXIS_LOOKUP"
$Jeddah = (($Text -match "LoadMap:.*Jeddah_RedSea_Assault") -or
           ($Text -match "Bringing World .*Jeddah_RedSea_Assault.*up for play")) -and
          ($Text -notmatch "Failed to enter\s+/Game/Maps/Jeddah_RedSea_Assault")
$Fatal = $Text -match "(?im)^\s*Fatal error:|LogWindows:\s*Error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Crash = $Text -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CONTROL TELEMETRY CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "PROCESS_EXIT_CODE=$ExitCode"
Write-Host "JEDDAH_RUNTIME_LOAD=$Jeddah"
Write-Host "CHARACTER_BEGIN_SEEN=$CharBegin"
Write-Host "CONTROLLER_SEEN=$Controller"
Write-Host "INPUT_SETUP_SEEN=$InputSetup"
Write-Host "MOVEFORWARD_INPUT_SEEN=$Forward"
Write-Host "MOVERIGHT_INPUT_SEEN=$Right"
Write-Host "TURN_INPUT_SEEN=$Turn"
Write-Host "LOOKUP_INPUT_SEEN=$LookUp"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"

Write-Host ""
Write-Host "=== ASWW TELEMETRY LINES ===" -ForegroundColor Yellow
if (Test-Path -LiteralPath $StdOut) {
    Select-String -LiteralPath $StdOut -Pattern "ASWW_TELEMETRY" | Select-Object -First 100
}

Write-Host ""
if ($Fatal -or $Crash) {
    Write-Host "PLAYER_CONTROL_ROOT_CLASSIFICATION=RUNTIME_FATAL_OR_CRASH" -ForegroundColor Red
}
elseif (-not $Jeddah) {
    Write-Host "PLAYER_CONTROL_ROOT_CLASSIFICATION=JEDDAH_NOT_LOADED" -ForegroundColor Red
}
elseif (-not $CharBegin) {
    Write-Host "PLAYER_CONTROL_ROOT_CLASSIFICATION=DEFAULT_PLAYER_CHARACTER_NOT_SPAWNED_OR_NOT_BEGUN_PLAY" -ForegroundColor Red
}
elseif (-not $Controller) {
    Write-Host "PLAYER_CONTROL_ROOT_CLASSIFICATION=CHARACTER_SPAWNED_BUT_NO_CONTROLLER_OBSERVED" -ForegroundColor Red
}
elseif (-not $InputSetup) {
    Write-Host "PLAYER_CONTROL_ROOT_CLASSIFICATION=CONTROLLER_PRESENT_BUT_INPUT_COMPONENT_NOT_SETUP" -ForegroundColor Red
}
elseif (-not ($Forward -or $Right -or $Turn -or $LookUp)) {
    Write-Host "PLAYER_CONTROL_ROOT_CLASSIFICATION=INPUT_COMPONENT_SETUP_BUT_NO_RUNTIME_INPUT_EVENTS_REACHED_CHARACTER" -ForegroundColor Red
}
else {
    Write-Host "PLAYER_CONTROL_ROOT_CLASSIFICATION=RUNTIME_INPUT_REACHES_CHARACTER" -ForegroundColor Green
    Write-Host "NEXT_GATE=IF_VISUAL_MOVEMENT_STILL_FAILS_INSPECT_MOVEMENT_STATE_COLLISION_AND_CAMERA" -ForegroundColor Yellow
}

Write-Host "PLAYER_CONTROL_TELEMETRY_RUN=PASS_DIAGNOSTIC_COMPLETED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_TELEMETRY" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
