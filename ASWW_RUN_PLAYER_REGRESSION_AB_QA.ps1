[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\PlayerRegressionABQA"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PLAYER_REGRESSION_AB_QA=STOPPED" -ForegroundColor Red
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
$StdOut = Join-Path $EvidenceRoot "player_regression_ab_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "player_regression_ab_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PLAYER REGRESSION A/B QA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "This build intentionally uses ABP_Unarmed while keeping rifle on HandGrip_R." -ForegroundColor Yellow
Write-Host "Purpose: determine whether direct ABP_TP_Rifle assignment caused the movement/camera regression." -ForegroundColor Yellow
Write-Host ""
Write-Host "Test: WASD, strafe, mouse look, camera follow, run." -ForegroundColor Yellow
Write-Host "Do NOT judge tactical grip in this A/B run." -ForegroundColor DarkYellow
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
Write-Host "RUNTIME_JEDDAH=$Jeddah"
Write-Host "RUNTIME_MANNY=$Manny"
Write-Host "RUNTIME_RIFLE=$Rifle"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"

$Movement = Ask-YesNo "MANNY_MOVEMENT_WORKS_WITH_WASD"
$Strafe = Ask-YesNo "MANNY_STRAFE_WORKS"
$Run = Ask-YesNo "MANNY_RUN_WORKS"
$MouseLook = Ask-YesNo "MOUSE_LOOK_ROTATES_CAMERA"
$CameraFollow = Ask-YesNo "CAMERA_FOLLOWS_MANNY"
$RifleFollows = Ask-YesNo "RIFLE_STILL_FOLLOWS_MANNY"

$Blocker = (Read-Host "FIRST_VISIBLE_BLOCKER [NONE or exact issue]").Trim()
if ([string]::IsNullOrWhiteSpace($Blocker)) { $Blocker = "NONE" }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FINAL A/B CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "MANNY_MOVEMENT_WORKS_WITH_WASD=$Movement"
Write-Host "MANNY_STRAFE_WORKS=$Strafe"
Write-Host "MANNY_RUN_WORKS=$Run"
Write-Host "MOUSE_LOOK_ROTATES_CAMERA=$MouseLook"
Write-Host "CAMERA_FOLLOWS_MANNY=$CameraFollow"
Write-Host "RIFLE_STILL_FOLLOWS_MANNY=$RifleFollows"
Write-Host "FIRST_VISIBLE_BLOCKER=$Blocker"

$RuntimeHealthy = $Jeddah -and $Manny -and $Rifle -and -not $Fatal -and -not $Crash
$ControlsRecovered = (
    $Movement -eq "YES" -and
    $Strafe -eq "YES" -and
    $Run -eq "YES" -and
    $MouseLook -eq "YES" -and
    $CameraFollow -eq "YES"
)

if ($RuntimeHealthy -and $ControlsRecovered) {
    Write-Host "PLAYER_REGRESSION_AB_QA=PASS_CONTROLS_RECOVERED" -ForegroundColor Green
    Write-Host "REGRESSION_CLASSIFICATION=DIRECT_ABP_TP_RIFLE_ASSIGNMENT_CONFIRMED_OR_STRONGLY_IMPLICATED" -ForegroundColor Green
    Write-Host "NEXT_GATE=KEEP_WORKING_LOCOMOTION_AND_LAYER_RIFLE_UPPER_BODY_POSE_IK" -ForegroundColor Green
}
elseif ($RuntimeHealthy) {
    Write-Host "PLAYER_REGRESSION_AB_QA=FAIL_CONTROLS_NOT_RECOVERED" -ForegroundColor Yellow
    Write-Host "REGRESSION_CLASSIFICATION=NOT_ISOLATED_TO_ABP_TP_RIFLE" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=READ_ONLY_PLAYER_INPUT_CAMERA_DIFF_AUDIT" -ForegroundColor Yellow
}
else {
    Write-Host "PLAYER_REGRESSION_AB_QA=INCONCLUSIVE_RUNTIME_HEALTH_FAIL" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=RUNTIME_HEALTH_DIAGNOSTIC" -ForegroundColor Yellow
}

Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
