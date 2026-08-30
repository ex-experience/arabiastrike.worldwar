[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\ManualQA"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "MANUAL_PACKAGED_QA=STOPPED" -ForegroundColor Red
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
$StdOut = Join-Path $EvidenceRoot "manual_qa_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "manual_qa_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " MANUAL PACKAGED GAMEPLAY QA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PACKAGED_EXE=$PackagedExe"
Write-Host "STDOUT_LOG=$StdOut"
Write-Host "STDERR_LOG=$StdErr"
Write-Host ""
Write-Host "PLAY THE GAME MANUALLY NOW." -ForegroundColor Yellow
Write-Host "When finished, close the game normally. This PowerShell window will then continue automatically." -ForegroundColor Yellow
Write-Host ""

# Keep all args free of spaces to avoid the previous command-line parsing issue.
$Args = @(
    "-log",
    "-stdout",
    "-FullStdOutLogOutput",
    "-NoSplash",
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
Write-Host "MANUAL_QA_SESSION=STARTED" -ForegroundColor Green

$Proc.WaitForExit()
$ExitCode = $Proc.ExitCode

Write-Host ""
Write-Host "PROCESS_EXIT_CODE=$ExitCode"

$OutText = ""
$ErrText = ""

if (Test-Path -LiteralPath $StdOut -PathType Leaf) {
    $OutText = Get-Content -Raw -LiteralPath $StdOut
}
if (Test-Path -LiteralPath $StdErr -PathType Leaf) {
    $ErrText = Get-Content -Raw -LiteralPath $StdErr
}

$Combined = $OutText + "`n" + $ErrText

$JeddahLoad = ($Combined -match "LoadMap:.*Jeddah_RedSea_Assault") -or ($Combined -match "Bringing World .*Jeddah_RedSea_Assault.*up for play")
$GameMode = $Combined -match "Game class is 'ASGameMode'"
$FailedEnter = $Combined -match "Failed to enter\s+/Game/Maps/Jeddah_RedSea_Assault"
$Fatal = $Combined -match "(?im)^\s*Fatal error:|LogWindows:\s*Error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Crash = $Combined -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"
$Hummer = $Combined -match "ASChaosHummerPawn"
$Soldier = $Combined -match "ASSoldierCharacter"
$Helicopter = $Combined -match "ASHelicopterPawn"
$Boss = $Combined -match "ASBossCharacter"
$Mission = $Combined -match "ASMissionDirector|MissionDirector"
$Bootstrap = $Combined -match "ASWorldBootstrap|WorldBootstrap"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " MANUAL QA LOG SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "JEDDAH_RUNTIME_LOAD_SEEN=$JeddahLoad"
Write-Host "ASGAMEMODE_RUNTIME_SEEN=$GameMode"
Write-Host "FAILED_TO_ENTER_JEDDAH_SEEN=$FailedEnter"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"
Write-Host "RUNTIME_SOLDIER_MARKER_SEEN=$Soldier"
Write-Host "RUNTIME_HUMMER_MARKER_SEEN=$Hummer"
Write-Host "RUNTIME_HELICOPTER_MARKER_SEEN=$Helicopter"
Write-Host "RUNTIME_BOSS_MARKER_SEEN=$Boss"
Write-Host "RUNTIME_MISSION_DIRECTOR_MARKER_SEEN=$Mission"
Write-Host "RUNTIME_WORLD_BOOTSTRAP_MARKER_SEEN=$Bootstrap"

Write-Host ""
Write-Host "=== IMPORTANT RUNTIME LINES ===" -ForegroundColor Yellow
if (Test-Path -LiteralPath $StdOut -PathType Leaf) {
    Select-String -LiteralPath $StdOut `
        -Pattern "Jeddah_RedSea_Assault|Game class is|Failed to enter|ASSoldierCharacter|ASChaosHummerPawn|ASHelicopterPawn|ASBossCharacter|ASMissionDirector|ASWorldBootstrap|Fatal error:|LogWindows: Error|LowLevelFatalError|Unhandled Exception|GPU Crashed|EXCEPTION_ACCESS_VIOLATION" `
        -Context 1,3 |
        Select-Object -First 220
}

Write-Host ""
if ($Fatal -or $Crash -or $FailedEnter) {
    Write-Host "MANUAL_PACKAGED_QA_LOG_HEALTH=FAIL" -ForegroundColor Red
    Write-Host "NEXT_GATE=FIX_FIRST_RUNTIME_FAILURE" -ForegroundColor Red
} else {
    Write-Host "MANUAL_PACKAGED_QA_LOG_HEALTH=PASS_NO_FATALS" -ForegroundColor Green
    Write-Host "NEXT_GATE=REPORT_MANUAL_GAMEPLAY_CHECKLIST" -ForegroundColor Green
}

Write-Host "NO_SOURCE_OR_MAP_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
