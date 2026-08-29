[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [int]$SmokeSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PACKAGED_RUNTIME_SMOKE=STOPPED" -ForegroundColor Red
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

$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\PackagedRuntime"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$AbsLog = Join-Path $EvidenceRoot "packaged_runtime_$Stamp.log"
$StdOut = Join-Path $EvidenceRoot "packaged_runtime_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "packaged_runtime_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PACKAGED RUNTIME STARTUP SMOKE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PACKAGED_EXE=$PackagedExe"
Write-Host "SMOKE_SECONDS=$SmokeSeconds"
Write-Host "RUNTIME_LOG=$AbsLog"

$Args = @(
    "-log",
    "-abslog=$AbsLog",
    "-stdout",
    "-FullStdOutLogOutput",
    "-NoSplash",
    "-NoSound",
    "-Windowed",
    "-ResX=1280",
    "-ResY=720"
)

try {
    $Process = Start-Process `
        -FilePath $PackagedExe `
        -ArgumentList $Args `
        -PassThru `
        -RedirectStandardOutput $StdOut `
        -RedirectStandardError $StdErr
}
catch {
    Stop-Gate "FAILED_TO_LAUNCH_PACKAGED_EXE_$($_.Exception.Message)" 20
}

Write-Host "PROCESS_ID=$($Process.Id)"
Write-Host "PROCESS_STARTED=True" -ForegroundColor Green

$EarlyExit = $false
$EarlyExitCode = $null

for ($i = 0; $i -lt $SmokeSeconds; $i++) {
    Start-Sleep -Seconds 1
    $Process.Refresh()
    if ($Process.HasExited) {
        $EarlyExit = $true
        $EarlyExitCode = $Process.ExitCode
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
        Stop-Process -Id $Process.Id -Force -ErrorAction Stop
        Write-Host "PROCESS_CLEANUP=TERMINATED_AFTER_SMOKE_WINDOW"
    }
    catch {
        Write-Host "PROCESS_CLEANUP=ALREADY_EXITED_OR_STOP_FAILED"
    }
}

Start-Sleep -Seconds 2

$LogCandidates = @()
if (Test-Path -LiteralPath $AbsLog -PathType Leaf) {
    $LogCandidates += Get-Item -LiteralPath $AbsLog
}

$LocalAppDataLogs = Join-Path $env:LOCALAPPDATA "ArabiaStrikeWorldWar\Saved\Logs"
if (Test-Path -LiteralPath $LocalAppDataLogs -PathType Container) {
    $LogCandidates += Get-ChildItem -LiteralPath $LocalAppDataLogs -Filter "*.log" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 3
}

$LogCandidates += @(
    Get-Item -LiteralPath $StdOut -ErrorAction SilentlyContinue,
    Get-Item -LiteralPath $StdErr -ErrorAction SilentlyContinue
) | Where-Object { $_ -ne $null }

$Combined = ""
foreach ($Candidate in ($LogCandidates | Sort-Object FullName -Unique)) {
    try {
        $Text = Get-Content -Raw -LiteralPath $Candidate.FullName -ErrorAction Stop
        if ($Text) {
            $Combined += "`n===== FILE: $($Candidate.FullName) =====`n$Text"
        }
    } catch {}
}

$JeddahSeen = $Combined -match "Jeddah_RedSea_Assault"
$GameModeSeen = $Combined -match "ASGameMode"
$FatalSeen = $Combined -match "(?im)^\s*Fatal error:|LogWindows:\s*Error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$CrashSeen = $Combined -match "CrashReportClient|GPU Crashed|EXCEPTION_ACCESS_VIOLATION"
$MissingContentSeen = $Combined -match "Failed to load package|Can't find file|Could not find file|Failed to open descriptor|Missing.*Jeddah_RedSea_Assault"
$MapLoadSeen = $Combined -match "LoadMap:|Bringing World .* up for play|Browse:.*Jeddah_RedSea_Assault|Game class is"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RUNTIME EVIDENCE SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "JEDDAH_LOG_MARKER_SEEN=$JeddahSeen"
Write-Host "ASGAMEMODE_LOG_MARKER_SEEN=$GameModeSeen"
Write-Host "MAP_LOAD_MARKER_SEEN=$MapLoadSeen"
Write-Host "FATAL_ERROR_SEEN=$FatalSeen"
Write-Host "CRASH_MARKER_SEEN=$CrashSeen"
Write-Host "MISSING_CONTENT_ERROR_SEEN=$MissingContentSeen"

Write-Host ""
Write-Host "=== RUNTIME RELEVANT LOG LINES ===" -ForegroundColor Yellow

foreach ($Candidate in ($LogCandidates | Sort-Object FullName -Unique)) {
    if (Test-Path -LiteralPath $Candidate.FullName) {
        Select-String -LiteralPath $Candidate.FullName `
            -Pattern "Jeddah_RedSea_Assault|ASGameMode|LoadMap:|Bringing World|Game class is|Fatal error:|LogWindows: Error|LowLevelFatalError|Unhandled Exception|Assertion failed:|Failed to load package|Can't find file|Could not find file|GPU Crashed" `
            -Context 2,6 |
            Select-Object -First 120
    }
}

if ($EarlyExit) {
    Stop-Gate "PACKAGED_GAME_EXITED_DURING_SMOKE_WINDOW_CODE_$EarlyExitCode" 30
}

if ($FatalSeen -or $CrashSeen -or $MissingContentSeen) {
    Stop-Gate "PACKAGED_RUNTIME_LOG_CONTAINS_FATAL_CRASH_OR_MISSING_CONTENT" 31
}

if (-not $JeddahSeen) {
    Stop-Gate "JEDDAH_RUNTIME_LOAD_NOT_PROVEN_IN_LOG" 32
}

Write-Host ""
Write-Host "PACKAGED_RUNTIME_SMOKE=PASS" -ForegroundColor Green
Write-Host "PROCESS_SURVIVED_${SmokeSeconds}S=True" -ForegroundColor Green
Write-Host "JEDDAH_RUNTIME_LOAD=PROVEN_BY_LOG_MARKER" -ForegroundColor Green

if ($GameModeSeen) {
    Write-Host "ASGAMEMODE_RUNTIME=PROVEN_BY_LOG_MARKER" -ForegroundColor Green
} else {
    Write-Host "ASGAMEMODE_RUNTIME=NOT_EXPLICITLY_LOGGED" -ForegroundColor Yellow
}

Write-Host "NEXT_GATE=MANUAL_PACKAGED_GAMEPLAY_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
