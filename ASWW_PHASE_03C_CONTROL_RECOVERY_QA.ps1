[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\ControlRecoveryAB_QA"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_03C_CONTROL_RECOVERY_QA=STOPPED" -ForegroundColor Red
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
Write-Host "BRANCH=$Branch"
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
$StdOut = Join-Path $EvidenceRoot "control_recovery_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "control_recovery_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================"
Write-Host " CONTROL RECOVERY A/B QA"
Write-Host "============================================================"
Write-Host "This build keeps rifle/camera and restores only ABP_Unarmed."
Write-Host "Test controls first. Do not judge final tactical pose yet."
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
$Proc.WaitForExit()

$Text = ""
if (Test-Path -LiteralPath $StdOut) { $Text += Get-Content -Raw -LiteralPath $StdOut }
if (Test-Path -LiteralPath $StdErr) { $Text += "`n" + (Get-Content -Raw -LiteralPath $StdErr) }

$ABMarker = $Text -match "ASWW_CONTROL_RECOVERY_AB_UNARMED"
$Jeddah = $Text -match "Jeddah_RedSea_Assault"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Crash = $Text -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"

Write-Host "CONTROL_RECOVERY_MARKER_SEEN=$ABMarker"
Write-Host "JEDDAH_RUNTIME_SEEN=$Jeddah"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"

$R = [ordered]@{}
$R["WASD_MOVEMENT"] = Ask-YesNo "WASD_MOVEMENT"
$R["MOUSE_CAMERA"] = Ask-YesNo "MOUSE_CAMERA"
$R["CAMERA_FOLLOWS_PLAYER"] = Ask-YesNo "CAMERA_FOLLOWS_PLAYER"
$R["SPRINT"] = Ask-YesNo "SPRINT"
$R["JUMP"] = Ask-YesNo "JUMP"
$R["CROUCH_SLIDE"] = Ask-YesNo "CROUCH_SLIDE"
$R["PRONE_MECHANIC"] = Ask-YesNo "PRONE_MECHANIC"
$R["RMB_ADS_FOV"] = Ask-YesNo "RMB_ADS_FOV"
$R["LMB_FIRE_INPUT"] = Ask-YesNo "LMB_FIRE_INPUT"
$R["R_RELOAD_INPUT"] = Ask-YesNo "R_RELOAD_INPUT"
$R["RIFLE_VISIBLE"] = Ask-YesNo "RIFLE_VISIBLE"
$R["RIFLE_FOLLOWS_PLAYER"] = Ask-YesNo "RIFLE_FOLLOWS_PLAYER"

Write-Host ""
foreach ($K in $R.Keys) {
    Write-Host "$K=$($R[$K])"
}

$RuntimeHealthy = $ABMarker -and $Jeddah -and -not $Fatal -and -not $Crash
$CoreControls = (
    $R["WASD_MOVEMENT"] -eq "YES" -and
    $R["MOUSE_CAMERA"] -eq "YES" -and
    $R["CAMERA_FOLLOWS_PLAYER"] -eq "YES" -and
    $R["SPRINT"] -eq "YES" -and
    $R["JUMP"] -eq "YES" -and
    $R["RMB_ADS_FOV"] -eq "YES"
)

Write-Host ""
Write-Host "============================================================"
Write-Host " CONTROL RECOVERY CLASSIFICATION"
Write-Host "============================================================"

if (-not $RuntimeHealthy) {
    Write-Host "CONTROL_RECOVERY_AB=FAIL_RUNTIME"
    Write-Host "NEXT_GATE=FIX_RUNTIME_ONLY"
}
elseif ($CoreControls) {
    Write-Host "CONTROL_RECOVERY_AB=PASS"
    Write-Host "ROOT_CAUSE_CLASSIFICATION=FULL_ABP_TP_RIFLE_SWAP_CAUSED_CONTROL_REGRESSION"
    Write-Host "NEXT_GATE=BUILD_LAYERED_TACTICAL_UPPER_BODY_PLUS_LEFT_HAND_IK_OVER_PROVEN_LOCOMOTION"
}
else {
    Write-Host "CONTROL_RECOVERY_AB=FAIL_CONTROLS_STILL_BROKEN"
    Write-Host "ROOT_CAUSE_CLASSIFICATION=NOT_ANIMBP_ONLY"
    Write-Host "NEXT_GATE=DIAGNOSE_PLAYER_V2_INPUT_CAMERA_POSSESSION_BEFORE_ANY_IK_OR_GUNPLAY"
}

Write-Host "DO_NOT_COMMIT_YET"
Write-Host "DO_NOT_TOUCH_MAIN"
