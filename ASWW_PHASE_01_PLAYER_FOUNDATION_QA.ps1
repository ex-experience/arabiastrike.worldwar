[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\AAAPlayerFoundationV1QA"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_01_PLAYER_FOUNDATION_QA=STOPPED" -ForegroundColor Red
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
$StdOut = Join-Path $EvidenceRoot "phase01_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "phase01_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PHASE 01 — PLAYER FOUNDATION V1 QA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Test in this order:" -ForegroundColor Yellow
Write-Host "WASD -> mouse look -> Shift sprint -> Ctrl crouch -> sprint+Ctrl slide" -ForegroundColor Yellow
Write-Host "Z prone foundation -> Space jump -> Space at low obstacle for mantle" -ForegroundColor Yellow
Write-Host "RMB ADS FOV -> Alt free look -> C ready-state cycle" -ForegroundColor Yellow
Write-Host "LMB fire / R reload / E interact must not regress." -ForegroundColor Yellow
Write-Host ""
Write-Host "Phase 01 does NOT claim final prone/slide/tactical animations yet." -ForegroundColor DarkYellow
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
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Crash = $Text -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"

Write-Host ""
Write-Host "RUNTIME_JEDDAH=$Jeddah"
Write-Host "RUNTIME_MANNY=$Manny"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"

$R = [ordered]@{}
$R["WASD_MOVEMENT"] = Ask-YesNo "WASD_MOVEMENT"
$R["MOUSE_LOOK"] = Ask-YesNo "MOUSE_LOOK"
$R["CAMERA_FOLLOWS_PLAYER"] = Ask-YesNo "CAMERA_FOLLOWS_PLAYER"
$R["SHIFT_SPRINT"] = Ask-YesNo "SHIFT_SPRINT"
$R["CTRL_CROUCH"] = Ask-YesNo "CTRL_CROUCH"
$R["SPRINT_CTRL_SLIDE"] = Ask-YesNo "SPRINT_CTRL_SLIDE"
$R["Z_PRONE_MECHANIC"] = Ask-YesNo "Z_PRONE_MECHANIC"
$R["SPACE_JUMP"] = Ask-YesNo "SPACE_JUMP"
$R["LOW_OBSTACLE_MANTLE"] = Ask-YesNo "LOW_OBSTACLE_MANTLE"
$R["RMB_ADS_FOV"] = Ask-YesNo "RMB_ADS_FOV"
$R["ALT_FREE_LOOK"] = Ask-YesNo "ALT_FREE_LOOK"
$R["LMB_FIRE_STILL_REACHES_EXISTING_WEAPON_PATH"] = Ask-YesNo "LMB_FIRE_STILL_REACHES_EXISTING_WEAPON_PATH"
$R["R_RELOAD_STILL_WORKS"] = Ask-YesNo "R_RELOAD_STILL_WORKS"
$R["E_INTERACT_STILL_WORKS"] = Ask-YesNo "E_INTERACT_STILL_WORKS"

$Blocker = (Read-Host "FIRST_BLOCKER [NONE or exact issue]").Trim()
if ([string]::IsNullOrWhiteSpace($Blocker)) { $Blocker = "NONE" }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FINAL PHASE 01 CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

foreach ($K in $R.Keys) {
    Write-Host "$K=$($R[$K])"
}
Write-Host "FIRST_BLOCKER=$Blocker"

$RuntimeHealthy = $Jeddah -and $Manny -and -not $Fatal -and -not $Crash
$CoreControls = (
    $R["WASD_MOVEMENT"] -eq "YES" -and
    $R["MOUSE_LOOK"] -eq "YES" -and
    $R["CAMERA_FOLLOWS_PLAYER"] -eq "YES" -and
    $R["SHIFT_SPRINT"] -eq "YES" -and
    $R["CTRL_CROUCH"] -eq "YES" -and
    $R["SPACE_JUMP"] -eq "YES" -and
    $R["RMB_ADS_FOV"] -eq "YES"
)

if ($RuntimeHealthy -and $CoreControls) {
    Write-Host "PHASE_01_PLAYER_FOUNDATION_QA=PASS_CORE" -ForegroundColor Green

    $Advanced = (
        $R["SPRINT_CTRL_SLIDE"] -eq "YES" -and
        $R["Z_PRONE_MECHANIC"] -eq "YES" -and
        $R["LOW_OBSTACLE_MANTLE"] -eq "YES" -and
        $R["ALT_FREE_LOOK"] -eq "YES"
    )

    if ($Advanced) {
        Write-Host "PHASE_01_ADVANCED_MOVEMENT_FOUNDATION=PASS" -ForegroundColor Green
        Write-Host "NEXT_GATE=PHASE_02_TACTICAL_ANIMATION_AND_FULL_BODY_IK" -ForegroundColor Green
    }
    else {
        Write-Host "PHASE_01_ADVANCED_MOVEMENT_FOUNDATION=PARTIAL" -ForegroundColor Yellow
        Write-Host "NEXT_GATE=FIX_ONLY_FAILED_PHASE_01_MOVEMENT_ITEMS" -ForegroundColor Yellow
    }
}
else {
    Write-Host "PHASE_01_PLAYER_FOUNDATION_QA=FAIL_CORE" -ForegroundColor Red
    Write-Host "NEXT_GATE=FIX_CORE_PLAYER_CONTROL_BEFORE_ANIMATION" -ForegroundColor Red
}

Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
