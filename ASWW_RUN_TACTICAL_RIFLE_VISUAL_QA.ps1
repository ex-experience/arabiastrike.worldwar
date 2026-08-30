[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\TacticalRifleVisualQA"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "TACTICAL_RIFLE_VISUAL_QA=STOPPED" -ForegroundColor Red
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
$StdOut = Join-Path $EvidenceRoot "tactical_rifle_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "tactical_rifle_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TACTICAL RIFLE VISUAL QA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Inspect these states before closing the game:" -ForegroundColor Yellow
Write-Host "1) Idle: rifle held in a believable low-ready / patrol-ready / combat-ready stance." -ForegroundColor Yellow
Write-Host "2) Walk forward/back/strafe: torso and weapon remain in armed locomotion." -ForegroundColor Yellow
Write-Host "3) Run: weapon remains controlled and does not float or detach." -ForegroundColor Yellow
Write-Host "4) Left hand: visibly supports the fore-end/handguard instead of hanging free." -ForegroundColor Yellow
Write-Host "5) Right hand: believable primary grip / trigger-hand position." -ForegroundColor Yellow
Write-Host "6) Rifle transform: no giant scale, no camera intrusion, no sideways/backwards orientation." -ForegroundColor Yellow
Write-Host "7) Camera and Manny movement must remain functional." -ForegroundColor Yellow
Write-Host ""
Write-Host "Do not mark IK PASS from logs; left-hand grip must be visibly correct." -ForegroundColor DarkYellow
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
if (Test-Path -LiteralPath $StdOut) { $Text += Get-Content -Raw -LiteralPath $StdOut }
if (Test-Path -LiteralPath $StdErr) { $Text += "`n" + (Get-Content -Raw -LiteralPath $StdErr) }

$Jeddah = $Text -match "/Game/Maps/Jeddah_RedSea_Assault|Jeddah_RedSea_Assault"
$Manny = $Text -match "ASWW_REAL_PLAYER_MANNY"
$Rifle = $Text -match "ASWW_COMBAT_PROOF RIFLE_VISUAL"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Crash = $Text -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RUNTIME HEALTH" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "JEDDAH_RUNTIME_SEEN=$Jeddah"
Write-Host "REAL_MANNY_MARKER_SEEN=$Manny"
Write-Host "REAL_RIFLE_MARKER_SEEN=$Rifle"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"

if ($Jeddah -and $Manny -and $Rifle -and -not $Fatal -and -not $Crash) {
    Write-Host "TACTICAL_RIFLE_RUNTIME_HEALTH=PASS" -ForegroundColor Green
}
else {
    Write-Host "TACTICAL_RIFLE_RUNTIME_HEALTH=INCONCLUSIVE_OR_FAIL" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REPORT VISUAL RESULT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "RIFLE_SCALE_REALISTIC=YES/NO"
Write-Host "RIFLE_POSITION_REALISTIC=YES/NO"
Write-Host "RIFLE_ORIENTATION_REALISTIC=YES/NO"
Write-Host "RIGHT_HAND_PRIMARY_GRIP_REALISTIC=YES/NO"
Write-Host "LEFT_HAND_SUPPORT_GRIP_REALISTIC=YES/NO"
Write-Host "LEFT_HAND_IK_VISUALLY_CORRECT=YES/NO"
Write-Host "TACTICAL_READY_IDLE=YES/NO"
Write-Host "ARMED_WALK_FORWARD=YES/NO"
Write-Host "ARMED_WALK_BACKWARD=YES/NO"
Write-Host "ARMED_STRAFE=YES/NO"
Write-Host "ARMED_RUN=YES/NO"
Write-Host "RIFLE_FOLLOWS_BODY_WITHOUT_FLOATING=YES/NO"
Write-Host "MANNY_MOVEMENT_STILL_WORKS=YES/NO"
Write-Host "CAMERA_STILL_WORKS=YES/NO"
Write-Host "FIRST_VISIBLE_BLOCKER=<NONE or exact first failure>"
Write-Host ""
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
