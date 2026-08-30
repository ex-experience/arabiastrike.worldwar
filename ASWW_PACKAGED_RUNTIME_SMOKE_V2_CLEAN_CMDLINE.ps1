[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE",
    [int]$SmokeSeconds = 45
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PACKAGED_RUNTIME_SMOKE_V2=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_SOURCE_OR_MAP_FILES_WERE_MODIFIED" -ForegroundColor Green
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
$StdOut = Join-Path $EvidenceRoot "asww_runtime_v2_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "asww_runtime_v2_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLEAN-COMMAND-LINE PACKAGED RUNTIME SMOKE V2" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PACKAGED_EXE=$PackagedExe"
Write-Host "SMOKE_SECONDS=$SmokeSeconds"
Write-Host "STDOUT_LOG=$StdOut"
Write-Host "STDERR_LOG=$StdErr"
Write-Host "ABSLOG_ARGUMENT=OMITTED_TO_AVOID_SPACES_IN_PROJECT_PATH" -ForegroundColor Yellow

# Deliberately use only arguments that contain no spaces.
# Previous run passed an unquoted -abslog= path inside OneDrive, causing Unreal
# to see STRIKE/WORLD/WAR as command-line tokens and attempt to resolve STRIKE as a URL.
$Args = @(
    "-log",
    "-stdout",
    "-FullStdOutLogOutput",
    "-NoSplash",
    "-NoSound",
    "-Windowed",
    "-ResX=1280",
    "-ResY=720"
)

try {
    $Proc = Start-Process `
        -FilePath $PackagedExe `
        -ArgumentList $Args `
        -WorkingDirectory (Split-Path -Parent $PackagedExe) `
        -PassThru `
        -RedirectStandardOutput $StdOut `
        -RedirectStandardError $StdErr
}
catch {
    Stop-Gate "FAILED_TO_LAUNCH_$($_.Exception.Message)" 20
}

Write-Host "PROCESS_ID=$($Proc.Id)"
Write-Host "PROCESS_STARTED=True" -ForegroundColor Green

$EarlyExit = $false
$EarlyExitCode = $null

for ($i = 0; $i -lt $SmokeSeconds; $i++) {
    Start-Sleep -Seconds 1
    $Proc.Refresh()
    if ($Proc.HasExited) {
        $EarlyExit = $true
        $EarlyExitCode = $Proc.ExitCode
        break
    }
}

if ($EarlyExit) {
    Write-Host "PROCESS_SURVIVED_SMOKE_WINDOW=False" -ForegroundColor Red
    Write-Host "EARLY_EXIT_CODE=$EarlyExitCode" -ForegroundColor Red
}
else {
    Write-Host "PROCESS_SURVIVED_SMOKE_WINDOW=True" -ForegroundColor Green
    try {
        Stop-Process -Id $Proc.Id -Force -ErrorAction Stop
        Write-Host "PROCESS_CLEANUP=TERMINATED_AFTER_SMOKE_WINDOW"
    }
    catch {
        Write-Host "PROCESS_CLEANUP=ALREADY_EXITED_OR_STOP_FAILED"
    }
}

Start-Sleep -Seconds 2

$OutText = ""
$ErrText = ""

if (Test-Path -LiteralPath $StdOut -PathType Leaf) {
    $OutText = Get-Content -Raw -LiteralPath $StdOut
}
if (Test-Path -LiteralPath $StdErr -PathType Leaf) {
    $ErrText = Get-Content -Raw -LiteralPath $StdErr
}

$Combined = $OutText + "`n" + $ErrText

$MalformedStrikeUrl = $Combined -match "Can't Find URL:\s*STRIKE"
$FailedJeddahEnter = $Combined -match "Failed to enter\s+/Game/Maps/Jeddah_RedSea_Assault"
$JeddahBrowse = $Combined -match "Browse:.*Jeddah_RedSea_Assault"
$JeddahLoadMap = $Combined -match "LoadMap:.*Jeddah_RedSea_Assault"
$JeddahWorldUp = $Combined -match "Bringing World .*Jeddah_RedSea_Assault.*up for play"
$GameModeSeen = $Combined -match "Game class is 'ASGameMode'"
$FatalSeen = $Combined -match "(?im)^\s*Fatal error:|LogWindows:\s*Error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$CrashSeen = $Combined -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"
$WorldPartitionSeen = $Combined -match "WorldPartition"
$PlayerControllerSeen = $Combined -match "PlayerController"
$PossessSeen = $Combined -match "(?i)Possess|Possessed"
$SoldierSeen = $Combined -match "ASSoldierCharacter"
$HummerSeen = $Combined -match "ASChaosHummerPawn"
$HelicopterSeen = $Combined -match "ASHelicopterPawn"
$BossSeen = $Combined -match "ASBossCharacter"
$MissionSeen = $Combined -match "ASMissionDirector|MissionDirector"
$BootstrapSeen = $Combined -match "ASWorldBootstrap|WorldBootstrap"

$JeddahLoadProven = ($JeddahLoadMap -or $JeddahWorldUp) -and (-not $FailedJeddahEnter)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLEAN COMMAND-LINE CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "MALFORMED_STRIKE_URL_SEEN=$MalformedStrikeUrl"
Write-Host "JEDDAH_BROWSE_MARKER_SEEN=$JeddahBrowse"
Write-Host "JEDDAH_LOADMAP_MARKER_SEEN=$JeddahLoadMap"
Write-Host "JEDDAH_WORLD_UP_FOR_PLAY_SEEN=$JeddahWorldUp"
Write-Host "FAILED_TO_ENTER_JEDDAH_SEEN=$FailedJeddahEnter"
Write-Host "ASGAMEMODE_RUNTIME_SEEN=$GameModeSeen"
Write-Host "WORLD_PARTITION_RUNTIME_SEEN=$WorldPartitionSeen"
Write-Host "FATAL_ERROR_SEEN=$FatalSeen"
Write-Host "CRASH_MARKER_SEEN=$CrashSeen"
Write-Host "RUNTIME_PLAYER_CONTROLLER_MARKER_SEEN=$PlayerControllerSeen"
Write-Host "RUNTIME_POSSESSION_MARKER_SEEN=$PossessSeen"
Write-Host "RUNTIME_SOLDIER_MARKER_SEEN=$SoldierSeen"
Write-Host "RUNTIME_HUMMER_MARKER_SEEN=$HummerSeen"
Write-Host "RUNTIME_HELICOPTER_MARKER_SEEN=$HelicopterSeen"
Write-Host "RUNTIME_BOSS_MARKER_SEEN=$BossSeen"
Write-Host "RUNTIME_MISSION_DIRECTOR_MARKER_SEEN=$MissionSeen"
Write-Host "RUNTIME_WORLD_BOOTSTRAP_MARKER_SEEN=$BootstrapSeen"

Write-Host ""
Write-Host "=== KEY RUNTIME LINES ===" -ForegroundColor Yellow
if (Test-Path -LiteralPath $StdOut -PathType Leaf) {
    Select-String -LiteralPath $StdOut `
        -Pattern "Command Line:|Can't Find URL:|Browse:|LoadMap:|Failed to enter|Game class is|Bringing World|WorldPartition|PlayerController|Possess|ASSoldierCharacter|ASChaosHummerPawn|ASHelicopterPawn|ASBossCharacter|ASMissionDirector|ASWorldBootstrap|Fatal error:|LogWindows: Error|LowLevelFatalError|Unhandled Exception" `
        -Context 1,4 |
        Select-Object -First 220
}

if ($EarlyExit) {
    Stop-Gate "PACKAGED_GAME_EXITED_DURING_SMOKE_WINDOW_CODE_$EarlyExitCode" 30
}

if ($FatalSeen -or $CrashSeen) {
    Stop-Gate "PACKAGED_RUNTIME_FATAL_OR_CRASH" 31
}

if ($MalformedStrikeUrl) {
    Stop-Gate "CLEAN_RUN_STILL_HAS_MALFORMED_STRIKE_URL" 32
}

if ($FailedJeddahEnter) {
    Write-Host ""
    Write-Host "PACKAGED_RUNTIME_SMOKE_V2=FAIL_JEDDAH_ENTER" -ForegroundColor Red
    Write-Host "COMMAND_LINE_CONTAMINATION=FIXED_OR_NOT_PRESENT" -ForegroundColor Green
    Write-Host "NEXT_GATE=EXTRACT_REAL_JEDDAH_LOAD_FAILURE" -ForegroundColor Yellow
    Write-Host "NO_SOURCE_OR_MAP_FILES_WERE_MODIFIED" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit 33
}

if (-not $JeddahLoadProven) {
    Write-Host ""
    Write-Host "PACKAGED_RUNTIME_SMOKE_V2=INCONCLUSIVE" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=PROVE_JEDDAH_LOAD_WITH_CLEAN_COMMAND_LINE" -ForegroundColor Yellow
    Write-Host "NO_SOURCE_OR_MAP_FILES_WERE_MODIFIED" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit 34
}

Write-Host ""
Write-Host "PACKAGED_RUNTIME_SMOKE_V2=PASS" -ForegroundColor Green
Write-Host "CLEAN_COMMAND_LINE=PASS" -ForegroundColor Green
Write-Host "JEDDAH_RUNTIME_LOAD=PASS" -ForegroundColor Green
Write-Host "PROCESS_SURVIVED_${SmokeSeconds}S=True" -ForegroundColor Green
Write-Host "NEXT_GATE=MANUAL_PACKAGED_GAMEPLAY_QA" -ForegroundColor Green
Write-Host "NO_SOURCE_OR_MAP_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
