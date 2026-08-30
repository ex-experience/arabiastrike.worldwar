[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\TPRifleTacticalVisualQA"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "TP_RIFLE_TACTICAL_VISUAL_QA=STOPPED" -ForegroundColor Red
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
$StdOut = Join-Path $EvidenceRoot "tp_rifle_tactical_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "tp_rifle_tactical_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " THIRD-PERSON RIFLE TACTICAL VISUAL QA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Check each state visually before closing:" -ForegroundColor Yellow
Write-Host "1) Idle: believable armed/tactical-ready posture." -ForegroundColor Yellow
Write-Host "2) Right hand: primary grip aligned with rifle grip/trigger area." -ForegroundColor Yellow
Write-Host "3) Left hand: supports fore-end/handguard; not hanging or crossing incorrectly." -ForegroundColor Yellow
Write-Host "4) Walk forward/backward/strafe: armed locomotion remains believable." -ForegroundColor Yellow
Write-Host "5) Run: rifle remains controlled and follows body." -ForegroundColor Yellow
Write-Host "6) Rifle scale/orientation: realistic; not sideways, backwards, giant or floating." -ForegroundColor Yellow
Write-Host "7) Manny movement and camera still work." -ForegroundColor Yellow
Write-Host ""
Write-Host "Important: IK is PASS only if the left hand visibly stays on the support grip." -ForegroundColor DarkYellow
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
    Write-Host "TP_RIFLE_RUNTIME_HEALTH=PASS" -ForegroundColor Green
}
else {
    Write-Host "TP_RIFLE_RUNTIME_HEALTH=INCONCLUSIVE_OR_FAIL" -ForegroundColor Yellow
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
Write-Host "LEFT_HAND_STAYS_ON_FOREEND_DURING_MOVEMENT=YES/NO"
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

function Ask-YesNo([string]$Label) {
    while ($true) {
        $v = (Read-Host "$Label [YES/NO]").Trim().ToUpperInvariant()
        if ($v -eq "YES" -or $v -eq "NO") { return $v }
        Write-Host "Enter YES or NO only." -ForegroundColor Yellow
    }
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ENTER VISUAL QA RESULTS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Results = [ordered]@{}
$Results["RIFLE_SCALE_REALISTIC"] = Ask-YesNo "RIFLE_SCALE_REALISTIC"
$Results["RIFLE_POSITION_REALISTIC"] = Ask-YesNo "RIFLE_POSITION_REALISTIC"
$Results["RIFLE_ORIENTATION_REALISTIC"] = Ask-YesNo "RIFLE_ORIENTATION_REALISTIC"
$Results["RIGHT_HAND_PRIMARY_GRIP_REALISTIC"] = Ask-YesNo "RIGHT_HAND_PRIMARY_GRIP_REALISTIC"
$Results["LEFT_HAND_SUPPORT_GRIP_REALISTIC"] = Ask-YesNo "LEFT_HAND_SUPPORT_GRIP_REALISTIC"
$Results["LEFT_HAND_STAYS_ON_FOREEND_DURING_MOVEMENT"] = Ask-YesNo "LEFT_HAND_STAYS_ON_FOREEND_DURING_MOVEMENT"
$Results["LEFT_HAND_IK_VISUALLY_CORRECT"] = Ask-YesNo "LEFT_HAND_IK_VISUALLY_CORRECT"
$Results["TACTICAL_READY_IDLE"] = Ask-YesNo "TACTICAL_READY_IDLE"
$Results["ARMED_WALK_FORWARD"] = Ask-YesNo "ARMED_WALK_FORWARD"
$Results["ARMED_WALK_BACKWARD"] = Ask-YesNo "ARMED_WALK_BACKWARD"
$Results["ARMED_STRAFE"] = Ask-YesNo "ARMED_STRAFE"
$Results["ARMED_RUN"] = Ask-YesNo "ARMED_RUN"
$Results["RIFLE_FOLLOWS_BODY_WITHOUT_FLOATING"] = Ask-YesNo "RIFLE_FOLLOWS_BODY_WITHOUT_FLOATING"
$Results["MANNY_MOVEMENT_STILL_WORKS"] = Ask-YesNo "MANNY_MOVEMENT_STILL_WORKS"
$Results["CAMERA_STILL_WORKS"] = Ask-YesNo "CAMERA_STILL_WORKS"

$FirstBlocker = (Read-Host "FIRST_VISIBLE_BLOCKER [NONE or exact issue]").Trim()
if ([string]::IsNullOrWhiteSpace($FirstBlocker)) { $FirstBlocker = "NONE" }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FINAL VISUAL QA CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

foreach ($K in $Results.Keys) {
    Write-Host "$K=$($Results[$K])"
}
Write-Host "FIRST_VISIBLE_BLOCKER=$FirstBlocker"

$RuntimeHealthy = $Jeddah -and $Manny -and $Rifle -and -not $Fatal -and -not $Crash
$AllVisualYes = @($Results.Values | Where-Object { $_ -ne "YES" }).Count -eq 0
$NoBlocker = $FirstBlocker.ToUpperInvariant() -eq "NONE"

if ($RuntimeHealthy -and $AllVisualYes -and $NoBlocker) {
    Write-Host "TP_RIFLE_TACTICAL_VISUAL_QA=PASS" -ForegroundColor Green
    Write-Host "NEXT_GATE=COMBAT_FIRE_RUNTIME_PROOF" -ForegroundColor Green
}
else {
    Write-Host "TP_RIFLE_TACTICAL_VISUAL_QA=FAIL_OR_NEEDS_FIX" -ForegroundColor Yellow

    if ($Results["RIFLE_SCALE_REALISTIC"] -eq "NO" -or
        $Results["RIFLE_POSITION_REALISTIC"] -eq "NO" -or
        $Results["RIFLE_ORIENTATION_REALISTIC"] -eq "NO" -or
        $Results["RIGHT_HAND_PRIMARY_GRIP_REALISTIC"] -eq "NO") {
        Write-Host "NEXT_GATE=FIX_WEAPON_SOCKET_OR_TRANSFORM_ONLY" -ForegroundColor Yellow
    }
    elseif ($Results["LEFT_HAND_SUPPORT_GRIP_REALISTIC"] -eq "NO" -or
            $Results["LEFT_HAND_STAYS_ON_FOREEND_DURING_MOVEMENT"] -eq "NO" -or
            $Results["LEFT_HAND_IK_VISUALLY_CORRECT"] -eq "NO") {
        Write-Host "NEXT_GATE=LEFT_HAND_IK_OR_CONTROL_RIG_FIX_ONLY" -ForegroundColor Yellow
    }
    elseif ($Results["TACTICAL_READY_IDLE"] -eq "NO" -or
            $Results["ARMED_WALK_FORWARD"] -eq "NO" -or
            $Results["ARMED_WALK_BACKWARD"] -eq "NO" -or
            $Results["ARMED_STRAFE"] -eq "NO" -or
            $Results["ARMED_RUN"] -eq "NO") {
        Write-Host "NEXT_GATE=RIFLE_LOCOMOTION_OR_STATE_MACHINE_FIX_ONLY" -ForegroundColor Yellow
    }
    elseif ($Results["MANNY_MOVEMENT_STILL_WORKS"] -eq "NO" -or
            $Results["CAMERA_STILL_WORKS"] -eq "NO") {
        Write-Host "NEXT_GATE=PLAYER_REGRESSION_FIX_ONLY" -ForegroundColor Yellow
    }
    else {
        Write-Host "NEXT_GATE=REVIEW_FIRST_VISIBLE_BLOCKER" -ForegroundColor Yellow
    }
}

Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
