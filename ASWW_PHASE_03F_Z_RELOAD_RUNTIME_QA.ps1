[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\Phase03F_Z_Reload_QA"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_03F_Z_RELOAD_QA=STOPPED"
    Write-Host "BLOCKER=$Reason"
    Write-Host "DO_NOT_COMMIT_YET"
    Write-Host "DO_NOT_TOUCH_MAIN"
    exit $Code
}

function Ask-YesNo([string]$Label) {
    while ($true) {
        $v = (Read-Host "$Label [YES/NO]").Trim().ToUpperInvariant()
        if ($v -eq "YES" -or $v -eq "NO") { return $v }
        Write-Host "Enter YES or NO only."
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
$StdOut = Join-Path $EvidenceRoot "phase03f_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "phase03f_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================"
Write-Host " PHASE 03F — Z EXIT + REAL RIFLE DEFINITION QA"
Write-Host "============================================================"
Write-Host "1) Press Z once; verify the character goes to the safe low stance without floor clipping."
Write-Host "2) Press Z again; verify full standing recovery."
Write-Host "3) Fire at least FIVE rounds with LMB."
Write-Host "4) Press R once, wait 3 seconds."
Write-Host "5) Fire again after the reload attempt."
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

$EquipSuccess = $Text -match "ASWW_QA_RIFLE_DEFINITION_EQUIP load=1 accepted=1"
$EquipFail = $Text -match "ASWW_QA_RIFLE_DEFINITION_EQUIP load=0"
$ZEnterCount = ([regex]::Matches($Text, "ASWW_QA_Z_ENTER")).Count
$ZExitCount = ([regex]::Matches($Text, "ASWW_QA_Z_EXIT_REQUEST")).Count
$ReloadKeyCount = ([regex]::Matches($Text, "ASWW_QA_RELOAD_KEY_PRESSED")).Count
$ReloadAcceptedCount = ([regex]::Matches($Text, "ASWW_QA_RELOAD_ACCEPTED")).Count
$ReloadFinishedCount = ([regex]::Matches($Text, "ASWW_QA_RELOAD_FINISHED")).Count
$NoDefCount = ([regex]::Matches($Text, "ASWW_QA_RELOAD_REJECT_NO_DEFINITION")).Count
$FullMagCount = ([regex]::Matches($Text, "ASWW_QA_RELOAD_REJECT_FULL_MAG")).Count
$NoReserveCount = ([regex]::Matches($Text, "ASWW_QA_RELOAD_REJECT_NO_RESERVE")).Count
$Jeddah = $Text -match "Jeddah_RedSea_Assault"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Crash = $Text -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"

Write-Host "RIFLE_DEFINITION_EQUIP_SUCCESS=$EquipSuccess"
Write-Host "RIFLE_DEFINITION_EQUIP_FAIL=$EquipFail"
Write-Host "Z_ENTER_COUNT=$ZEnterCount"
Write-Host "Z_EXIT_COUNT=$ZExitCount"
Write-Host "RELOAD_KEY_COUNT=$ReloadKeyCount"
Write-Host "RELOAD_ACCEPTED_COUNT=$ReloadAcceptedCount"
Write-Host "RELOAD_FINISHED_COUNT=$ReloadFinishedCount"
Write-Host "RELOAD_REJECT_NO_DEFINITION_COUNT=$NoDefCount"
Write-Host "RELOAD_REJECT_FULL_MAG_COUNT=$FullMagCount"
Write-Host "RELOAD_REJECT_NO_RESERVE_COUNT=$NoReserveCount"
Write-Host "JEDDAH_RUNTIME_SEEN=$Jeddah"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"

$ZLow = Ask-YesNo "Z_FIRST_PRESS_SAFE_LOW_STANCE_VISIBLE"
$ZSinks = Ask-YesNo "Z_CHARACTER_SINKS_OR_DISAPPEARS_UNDER_GROUND"
$ZStand = Ask-YesNo "Z_SECOND_PRESS_RETURNS_TO_FULL_STANDING"
$FireBefore = Ask-YesNo "LMB_FIRE_CONSUMES_AMMO_OR_PRODUCES_REAL_SHOT_EFFECT"
$ReloadVisual = Ask-YesNo "RELOAD_ANIMATION_OR_CLEAR_VISUAL_FEEDBACK_SEEN"
$FireAfter = Ask-YesNo "LMB_FIRE_WORKS_AFTER_RELOAD_ATTEMPT"

Write-Host ""
Write-Host "============================================================"
Write-Host " PHASE 03F CLASSIFICATION"
Write-Host "============================================================"

if (-not $Jeddah -or $Fatal -or $Crash) {
    Write-Host "PHASE_03F_QA=FAIL_RUNTIME"
    Write-Host "NEXT_GATE=FIX_RUNTIME"
}
elseif (-not $EquipSuccess -or $NoDefCount -gt 0) {
    Write-Host "PHASE_03F_QA=FAIL_RIFLE_DEFINITION_EQUIP"
    Write-Host "NEXT_GATE=FIX_DATA_ASSET_LOADOUT_REFERENCE"
}
elseif ($ZSinks -eq "YES" -or $ZStand -ne "YES") {
    Write-Host "PHASE_03F_QA=FAIL_Z_TRANSITION"
    Write-Host "NEXT_GATE=TEMP_DISABLE_Z_UNTIL_DEDICATED_PRONE_ANIMATION_STATE"
}
elseif ($FireBefore -ne "YES") {
    Write-Host "PHASE_03F_QA=Z_PASS_RIFLE_DEF_PASS_FIRE_RUNTIME_NOT_PROVEN"
    Write-Host "NEXT_GATE=PROVE_FIRE_DAMAGE_AND_AMMO_PATH"
}
elseif ($ReloadAcceptedCount -gt 0 -and $ReloadFinishedCount -gt 0) {
    Write-Host "PHASE_03F_QA=FUNCTIONAL_PASS"
    if ($ReloadVisual -eq "YES") {
        Write-Host "RELOAD=FUNCTION_AND_VISUAL_PASS"
    }
    else {
        Write-Host "RELOAD=FUNCTION_PASS_VISUAL_ANIMATION_MISSING"
    }
    Write-Host "NEXT_GATE=REMOVE_QA_TELEMETRY_THEN_BUILD_LAYERED_TACTICAL_UPPER_BODY_AND_TRUE_PRONE"
}
elseif ($FullMagCount -gt 0) {
    Write-Host "PHASE_03F_QA=RELOAD_INPUT_PASS_BUT_MAG_FULL"
    Write-Host "NEXT_GATE=VERIFY_REAL_AMMO_CONSUMPTION_BEFORE_RELOAD"
}
elseif ($NoReserveCount -gt 0) {
    Write-Host "PHASE_03F_QA=RELOAD_INPUT_PASS_BUT_NO_RESERVE"
    Write-Host "NEXT_GATE=FIX_RIFLE_RESERVE_AMMO_INITIALIZATION"
}
else {
    Write-Host "PHASE_03F_QA=MIXED_RELOAD_RESULT"
    Write-Host "NEXT_GATE=INSPECT_RUNTIME_RELOAD_COUNTS"
}

Write-Host "QA_MARKERS_MUST_BE_REMOVED_BEFORE_COMMIT"
Write-Host "DO_NOT_COMMIT_YET"
Write-Host "DO_NOT_TOUCH_MAIN"
