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

$RuntimeRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\PackagedRuntime"
$Latest = Get-ChildItem -LiteralPath $RuntimeRoot -Filter "packaged_runtime_*.log" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $Latest) {
    Write-Host "BLOCKER=NO_PACKAGED_RUNTIME_LOG_FOUND" -ForegroundColor Red
    exit 11
}

$LogPath = $Latest.FullName
$Text = Get-Content -Raw -LiteralPath $LogPath

$JeddahSeen = $Text -match "Jeddah_RedSea_Assault"
$GameModeSeen = $Text -match "ASGameMode"
$MapLoadSeen = $Text -match "LoadMap:|Bringing World .* up for play|Browse:.*Jeddah_RedSea_Assault|Game class is"
$FatalSeen = $Text -match "(?im)^\s*Fatal error:|LogWindows:\s*Error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$CrashSeen = $Text -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION|CrashReportClient"
$MissingContentSeen = $Text -match "Failed to load package|Can't find file|Could not find file|Failed to open descriptor|Missing.*Jeddah_RedSea_Assault"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " EXISTING PACKAGED RUNTIME LOG ANALYSIS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "RUNTIME_LOG=$LogPath"
Write-Host "JEDDAH_LOG_MARKER_SEEN=$JeddahSeen"
Write-Host "ASGAMEMODE_LOG_MARKER_SEEN=$GameModeSeen"
Write-Host "MAP_LOAD_MARKER_SEEN=$MapLoadSeen"
Write-Host "FATAL_ERROR_SEEN=$FatalSeen"
Write-Host "CRASH_MARKER_SEEN=$CrashSeen"
Write-Host "MISSING_CONTENT_ERROR_SEEN=$MissingContentSeen"

Write-Host ""
Write-Host "=== PACKAGED RUNTIME DIAGNOSIS ===" -ForegroundColor Yellow

Select-String -LiteralPath $LogPath `
    -Pattern "Jeddah_RedSea_Assault|ASGameMode|Game class is|LoadMap|Bringing World|WorldPartition|PlayerStart|Possess|Pawn|ASSoldierCharacter|ASChaosHummerPawn|ASHelicopterPawn|ASBossCharacter|ASObjectiveVolume|MissionDirector|WorldBootstrap|Fatal|Error:|Warning:" `
    -Context 1,4 |
    Select-Object -First 260

Write-Host ""
if ($FatalSeen -or $CrashSeen -or $MissingContentSeen) {
    Write-Host "PACKAGED_RUNTIME_LOG=FAIL" -ForegroundColor Red
    Write-Host "NEXT_GATE=FIX_RUNTIME_FATAL_OR_MISSING_CONTENT" -ForegroundColor Red
    exit 20
}

if (-not $JeddahSeen) {
    Write-Host "PACKAGED_RUNTIME_LOG=INCONCLUSIVE" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=PROVE_JEDDAH_RUNTIME_LOAD" -ForegroundColor Yellow
    exit 21
}

Write-Host "PACKAGED_RUNTIME_LOG=PASS_NO_FATALS" -ForegroundColor Green
Write-Host "JEDDAH_RUNTIME_LOAD=PROVEN_BY_LOG_MARKER" -ForegroundColor Green

if ($GameModeSeen) {
    Write-Host "ASGAMEMODE_RUNTIME=PROVEN_BY_LOG_MARKER" -ForegroundColor Green
} else {
    Write-Host "ASGAMEMODE_RUNTIME=NOT_EXPLICITLY_LOGGED" -ForegroundColor Yellow
}

Write-Host "NEXT_GATE=CLASSIFY_PLAYER_POSSESSION_AND_RUNTIME_ACTOR_STREAMING" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
