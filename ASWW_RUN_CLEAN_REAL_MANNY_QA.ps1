[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\CleanRealMannyQA"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "CLEAN_REAL_MANNY_QA=STOPPED" -ForegroundColor Red
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
$StdOut = Join-Path $EvidenceRoot "clean_real_manny_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "clean_real_manny_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLEAN REAL MANNY PACKAGED QA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Test briefly, then close the game normally:" -ForegroundColor Yellow
Write-Host "- Manny visible (not cube)" -ForegroundColor Yellow
Write-Host "- WASD movement" -ForegroundColor Yellow
Write-Host "- Walk/run animation" -ForegroundColor Yellow
Write-Host "- Mouse camera rotation + follow" -ForegroundColor Yellow
Write-Host ""

$Args = @(
    "-log"
    "-stdout"
    "-FullStdOutLogOutput"
    "-NoSplash"
    "-Windowed"
    "-ResX=1280"
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
$Jeddah = $Text -match "/Game/Maps/Jeddah_RedSea_Assault|Jeddah_RedSea_Assault"
$WorldUp = $Text -match "Bringing World .* up for play|Load map complete"
$TempMarkers = $Text -match "ASWW_TELEMETRY|ASWW_MOVE_STATE|ASWW_Telemetry_|ASWW_MoveState_|ASWW_VISUAL_PROOF|ASWW_PlayerVisualProof"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Crash = $Text -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLEAN RUNTIME LOG CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "REAL_MANNY_MARKER_SEEN=$Manny"
Write-Host "JEDDAH_RUNTIME_SEEN=$Jeddah"
Write-Host "WORLD_UP_OR_MAP_COMPLETE_SEEN=$WorldUp"
Write-Host "TEMP_QA_MARKERS_SEEN=$TempMarkers"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"

if ($Manny -and $Jeddah -and -not $TempMarkers -and -not $Fatal -and -not $Crash) {
    Write-Host "CLEAN_RUNTIME_LOG_HEALTH=PASS" -ForegroundColor Green
}
else {
    Write-Host "CLEAN_RUNTIME_LOG_HEALTH=INCONCLUSIVE_OR_FAIL" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "REPORT_VISUAL_RESULT_AS:" -ForegroundColor Cyan
Write-Host "MANNY_VISIBLE=YES/NO"
Write-Host "MANNY_MOVES_WITH_WASD=YES/NO"
Write-Host "MANNY_ANIMATES_WHILE_MOVING=YES/NO"
Write-Host "CAMERA_ROTATES_WITH_MOUSE=YES/NO"
Write-Host "CAMERA_FOLLOWS_MANNY=YES/NO"
Write-Host "FIRST_VISIBLE_BLOCKER=<NONE or what you saw>"
Write-Host ""
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
