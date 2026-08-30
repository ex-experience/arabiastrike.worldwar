[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\CombatPlayerV1QA"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_03B_COMBAT_PLAYER_V1_QA=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Ask-YesNo([string]$Label) {
    while ($true) {
        $v = (Read-Host "$Label [YES/NO]").Trim().ToUpperInvariant()
        if ($v -eq "YES" -or $v -eq "NO") { return $v }
        Write-Host "Enter YES or NO only." -ForegroundColor Yellow
    }
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
$StdOut = Join-Path $EvidenceRoot "combat_player_v1_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "combat_player_v1_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COMBAT PLAYER V1 — MANUAL VISUAL QA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Evaluate the real packaged build, not editor preview." -ForegroundColor Yellow
Write-Host "Focus on military third-person presentation and control regression." -ForegroundColor Yellow
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

$CombatMarker = $Text -match "ASWW_COMBAT_PLAYER_V1"
$Jeddah = $Text -match "/Game/Maps/Jeddah_RedSea_Assault|Jeddah_RedSea_Assault"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Crash = $Text -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"

Write-Host "COMBAT_PLAYER_MARKER_SEEN=$CombatMarker"
Write-Host "JEDDAH_RUNTIME_SEEN=$Jeddah"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"

$R = [ordered]@{}
$R["RIFLE_VISIBLE"] = Ask-YesNo "RIFLE_VISIBLE"
$R["RIFLE_SCALE_REALISTIC"] = Ask-YesNo "RIFLE_SCALE_REALISTIC"
$R["RIFLE_POSITION_ORIENTATION_REALISTIC"] = Ask-YesNo "RIFLE_POSITION_ORIENTATION_REALISTIC"
$R["RIGHT_HAND_PRIMARY_GRIP_REALISTIC"] = Ask-YesNo "RIGHT_HAND_PRIMARY_GRIP_REALISTIC"
$R["LEFT_HAND_SUPPORTS_FOREND"] = Ask-YesNo "LEFT_HAND_SUPPORTS_FOREND"
$R["TACTICAL_READY_IDLE"] = Ask-YesNo "TACTICAL_READY_IDLE"
$R["ARMED_WALK_FORWARD"] = Ask-YesNo "ARMED_WALK_FORWARD"
$R["ARMED_WALK_BACKWARD"] = Ask-YesNo "ARMED_WALK_BACKWARD"
$R["ARMED_STRAFE_LEFT_RIGHT"] = Ask-YesNo "ARMED_STRAFE_LEFT_RIGHT"
$R["SPRINT_STILL_WORKS"] = Ask-YesNo "SPRINT_STILL_WORKS"
$R["JUMP_STILL_WORKS"] = Ask-YesNo "JUMP_STILL_WORKS"
$R["RMB_ADS_CAMERA_WORKS"] = Ask-YesNo "RMB_ADS_CAMERA_WORKS"
$R["WASD_MOVEMENT_STILL_WORKS"] = Ask-YesNo "WASD_MOVEMENT_STILL_WORKS"
$R["MOUSE_CAMERA_STILL_WORKS"] = Ask-YesNo "MOUSE_CAMERA_STILL_WORKS"
$R["LMB_FIRE_STILL_WORKS"] = Ask-YesNo "LMB_FIRE_STILL_WORKS"
$R["R_RELOAD_STILL_WORKS"] = Ask-YesNo "R_RELOAD_STILL_WORKS"
$R["RIFLE_FOLLOWS_BODY_WITHOUT_FLOATING"] = Ask-YesNo "RIFLE_FOLLOWS_BODY_WITHOUT_FLOATING"

$Blocker = (Read-Host "FIRST_VISIBLE_BLOCKER [NONE or exact issue]").Trim()
if ([string]::IsNullOrWhiteSpace($Blocker)) { $Blocker = "NONE" }

Write-Host ""
foreach ($K in $R.Keys) {
    Write-Host "$K=$($R[$K])"
}
Write-Host "FIRST_VISIBLE_BLOCKER=$Blocker"

$RuntimeHealthy = $CombatMarker -and $Jeddah -and -not $Fatal -and -not $Crash

$CoreControls = (
    $R["WASD_MOVEMENT_STILL_WORKS"] -eq "YES" -and
    $R["MOUSE_CAMERA_STILL_WORKS"] -eq "YES" -and
    $R["SPRINT_STILL_WORKS"] -eq "YES" -and
    $R["JUMP_STILL_WORKS"] -eq "YES" -and
    $R["RMB_ADS_CAMERA_WORKS"] -eq "YES"
)

$CombatPresentation = (
    $R["RIFLE_VISIBLE"] -eq "YES" -and
    $R["RIFLE_SCALE_REALISTIC"] -eq "YES" -and
    $R["RIFLE_POSITION_ORIENTATION_REALISTIC"] -eq "YES" -and
    $R["RIGHT_HAND_PRIMARY_GRIP_REALISTIC"] -eq "YES" -and
    $R["TACTICAL_READY_IDLE"] -eq "YES" -and
    $R["ARMED_WALK_FORWARD"] -eq "YES" -and
    $R["ARMED_STRAFE_LEFT_RIGHT"] -eq "YES"
)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COMBAT PLAYER V1 CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (-not $RuntimeHealthy) {
    Write-Host "COMBAT_PLAYER_V1_QA=FAIL_RUNTIME" -ForegroundColor Red
    Write-Host "NEXT_GATE=FIX_RUNTIME_ONLY" -ForegroundColor Red
}
elseif (-not $CoreControls) {
    Write-Host "COMBAT_PLAYER_V1_QA=FAIL_CONTROL_REGRESSION" -ForegroundColor Red
    Write-Host "NEXT_GATE=FIX_PLAYER_CONTROL_BEFORE_ANY_IK_OR_GUNPLAY" -ForegroundColor Red
}
elseif (-not $CombatPresentation) {
    Write-Host "COMBAT_PLAYER_V1_QA=PARTIAL_PRESENTATION" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=PHASE_03C_DEDICATED_HAND_IK_AND_TACTICAL_POSE_FIX" -ForegroundColor Yellow
}
else {
    Write-Host "COMBAT_PLAYER_V1_QA=PASS_CORE" -ForegroundColor Green

    if ($R["LEFT_HAND_SUPPORTS_FOREND"] -eq "YES") {
        Write-Host "TWO_HAND_RIFLE_PRESENTATION=PASS_BASELINE" -ForegroundColor Green
        Write-Host "NEXT_GATE=PHASE_04_MILITARY_GUNPLAY_V1" -ForegroundColor Green
    }
    else {
        Write-Host "TWO_HAND_RIFLE_PRESENTATION=RIGHT_HAND_PASS_LEFT_HAND_NEEDS_IK" -ForegroundColor Yellow
        Write-Host "NEXT_GATE=PHASE_03C_DEDICATED_LEFT_HAND_IK" -ForegroundColor Yellow
    }
}

Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
