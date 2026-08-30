[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\Phase03E_Z_Reload_QA"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_03E_Z_RELOAD_QA=STOPPED" -ForegroundColor Red
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
if ($Branch -ne "codex/asww-development") { Stop-Gate "WRONG_BRANCH_$Branch" 10 }
if (-not (Test-Path -LiteralPath $PackagedExe -PathType Leaf)) { Stop-Gate "PACKAGED_EXE_NOT_FOUND" 11 }

$Existing = @(Get-Process ArabiaStrikeWorldWar -ErrorAction SilentlyContinue)
if ($Existing.Count -gt 0) {
    $Existing | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_EXISTING_GAME_FIRST" 12
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$StdOut = Join-Path $EvidenceRoot "phase03e_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "phase03e_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================"
Write-Host " PHASE 03E — Z + RELOAD QA"
Write-Host "============================================================"
Write-Host "1) Press Z once. Confirm Manny does NOT sink/disappear under the floor."
Write-Host "2) Press Z again. Confirm standing recovery is clean."
Write-Host "3) Fire at least FIVE rounds with LMB."
Write-Host "4) Press R once and wait 3 seconds."
Write-Host "5) Press R once more."
Write-Host "6) Exit normally."
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

$KeyCount = ([regex]::Matches($Text, "ASWW_QA_RELOAD_KEY_PRESSED")).Count
$AcceptedCount = ([regex]::Matches($Text, "ASWW_QA_RELOAD_ACCEPTED")).Count
$FinishedCount = ([regex]::Matches($Text, "ASWW_QA_RELOAD_FINISHED")).Count
$FullMagCount = ([regex]::Matches($Text, "ASWW_QA_RELOAD_REJECT_FULL_MAG")).Count
$NoDefCount = ([regex]::Matches($Text, "ASWW_QA_RELOAD_REJECT_NO_DEFINITION")).Count
$NoReserveCount = ([regex]::Matches($Text, "ASWW_QA_RELOAD_REJECT_NO_RESERVE")).Count
$AlreadyCount = ([regex]::Matches($Text, "ASWW_QA_RELOAD_REJECT_ALREADY_RELOADING")).Count
$Jeddah = $Text -match "Jeddah_RedSea_Assault"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Crash = $Text -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"

Write-Host "RELOAD_KEY_COUNT=$KeyCount"
Write-Host "RELOAD_ACCEPTED_COUNT=$AcceptedCount"
Write-Host "RELOAD_FINISHED_COUNT=$FinishedCount"
Write-Host "RELOAD_REJECT_FULL_MAG_COUNT=$FullMagCount"
Write-Host "RELOAD_REJECT_NO_DEFINITION_COUNT=$NoDefCount"
Write-Host "RELOAD_REJECT_NO_RESERVE_COUNT=$NoReserveCount"
Write-Host "RELOAD_REJECT_ALREADY_RELOADING_COUNT=$AlreadyCount"
Write-Host "JEDDAH_RUNTIME_SEEN=$Jeddah"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"

$ZSinks = Ask-YesNo "Z_CHARACTER_SINKS_OR_DISAPPEARS_UNDER_GROUND"
$ZRecovers = Ask-YesNo "Z_SECOND_PRESS_RETURNS_TO_STANDING_CLEANLY"
$ReloadVisual = Ask-YesNo "RELOAD_ANIMATION_OR_CLEAR_VISUAL_FEEDBACK_SEEN"

Write-Host ""
Write-Host "============================================================"
Write-Host " PHASE 03E CLASSIFICATION"
Write-Host "============================================================"

if (-not $Jeddah -or $Fatal -or $Crash) {
    Write-Host "PHASE_03E_QA=FAIL_RUNTIME"
    Write-Host "NEXT_GATE=FIX_RUNTIME"
}
elseif ($ZSinks -eq "YES") {
    Write-Host "PHASE_03E_QA=FAIL_Z_FLOOR_CLIP_REMAINS"
    Write-Host "NEXT_GATE=DISABLE_Z_TEMPORARILY_UNTIL_TRUE_PRONE_ANIMATION_AND_CAPSULE_MODEL"
}
elseif ($ZRecovers -ne "YES") {
    Write-Host "PHASE_03E_QA=FAIL_Z_EXIT_TRANSITION"
    Write-Host "NEXT_GATE=FIX_PRONE_EXIT_STATE"
}
elseif ($KeyCount -eq 0) {
    Write-Host "PHASE_03E_QA=Z_PASS_RELOAD_KEY_NOT_REACHING_PLAYER"
    Write-Host "NEXT_GATE=TRACE_INPUT_CONTEXT_OR_FOCUS_FOR_R"
}
elseif ($AcceptedCount -gt 0 -and $FinishedCount -gt 0) {
    Write-Host "PHASE_03E_QA=Z_PASS_RELOAD_FUNCTIONAL"
    if ($ReloadVisual -eq "YES") {
        Write-Host "RELOAD_STATUS=FUNCTION_AND_VISUAL_PASS"
        Write-Host "NEXT_GATE=BUILD_LAYERED_TACTICAL_UPPER_BODY_PLUS_LEFT_HAND_IK"
    }
    else {
        Write-Host "RELOAD_STATUS=FUNCTION_PASS_VISUAL_ANIMATION_MISSING"
        Write-Host "NEXT_GATE=BUILD_LAYERED_TACTICAL_UPPER_BODY_RELOAD_PLUS_LEFT_HAND_IK"
    }
}
elseif ($FullMagCount -gt 0) {
    Write-Host "PHASE_03E_QA=Z_PASS_RELOAD_REJECTED_FULL_MAG"
    Write-Host "INTERPRETATION=R_INPUT_WORKS_BUT_MAGAZINE_WAS_FULL_WHEN_REQUESTED"
    Write-Host "NEXT_GATE=RETEST_AFTER_CONFIRMED_AMMO_CONSUMPTION"
}
elseif ($NoDefCount -gt 0) {
    Write-Host "PHASE_03E_QA=Z_PASS_RELOAD_REJECTED_NO_WEAPON_DEFINITION"
    Write-Host "NEXT_GATE=FIX_WEAPON_DEFINITION_EQUIP_RUNTIME"
}
elseif ($NoReserveCount -gt 0) {
    Write-Host "PHASE_03E_QA=Z_PASS_RELOAD_REJECTED_NO_RESERVE"
    Write-Host "NEXT_GATE=FIX_AMMO_LOADOUT_OR_RESERVE_INITIALIZATION"
}
else {
    Write-Host "PHASE_03E_QA=Z_PASS_RELOAD_MIXED_DIAGNOSTIC"
    Write-Host "NEXT_GATE=INSPECT_RELOAD_QA_LOG_COUNTS"
}

Write-Host "QA_RELOAD_TELEMETRY_MUST_BE_REMOVED_BEFORE_COMMIT"
Write-Host "DO_NOT_COMMIT_YET"
Write-Host "DO_NOT_TOUCH_MAIN"
