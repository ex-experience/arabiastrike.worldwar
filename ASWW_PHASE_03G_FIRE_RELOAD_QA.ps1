[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\Phase03G_FireReload_QA"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_03G_FIRE_RELOAD_QA=STOPPED"
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
$StdOut = Join-Path $EvidenceRoot "phase03g_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "phase03g_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================"
Write-Host " PHASE 03G — FIRE + RELOAD AUTHORITY PROOF"
Write-Host "============================================================"
Write-Host "1) Press Z once: NOTHING should happen. Z is intentionally disabled."
Write-Host "2) Click LMB 8 separate times, roughly 0.2 seconds apart."
Write-Host "3) Press R once and wait 3 seconds."
Write-Host "4) Click LMB 3 more times."
Write-Host "5) Exit normally."
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

$FireDispatch = ([regex]::Matches($Text, "ASWW_QA_FIRE_DISPATCH weapon=")).Count
$FireDispatchReject = ([regex]::Matches($Text, "ASWW_QA_FIRE_DISPATCH_REJECT")).Count
$FireRequest = ([regex]::Matches($Text, "ASWW_QA_FIRE_REQUEST_SENT")).Count
$FireAccepted = ([regex]::Matches($Text, "ASWW_QA_FIRE_AUTH_ACCEPTED")).Count
$FireNoDef = ([regex]::Matches($Text, "ASWW_QA_FIRE_AUTH_REJECT_NO_DEFINITION")).Count
$FireReloading = ([regex]::Matches($Text, "ASWW_QA_FIRE_AUTH_REJECT_RELOADING")).Count
$FireEmpty = ([regex]::Matches($Text, "ASWW_QA_FIRE_AUTH_REJECT_EMPTY")).Count
$FireCooldown = ([regex]::Matches($Text, "ASWW_QA_FIRE_AUTH_REJECT_COOLDOWN")).Count
$FireHit = ([regex]::Matches($Text, "ASWW_QA_FIRE_AUTH_HIT actor=")).Count

$ReloadKey = ([regex]::Matches($Text, "ASWW_QA_RELOAD_KEY_PRESSED")).Count
$ReloadAccepted = ([regex]::Matches($Text, "ASWW_QA_RELOAD_ACCEPTED")).Count
$ReloadFinished = ([regex]::Matches($Text, "ASWW_QA_RELOAD_FINISHED")).Count
$ReloadFull = ([regex]::Matches($Text, "ASWW_QA_RELOAD_REJECT_FULL_MAG")).Count
$ReloadNoDef = ([regex]::Matches($Text, "ASWW_QA_RELOAD_REJECT_NO_DEFINITION")).Count
$ReloadNoReserve = ([regex]::Matches($Text, "ASWW_QA_RELOAD_REJECT_NO_RESERVE")).Count

$Jeddah = $Text -match "Jeddah_RedSea_Assault"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Crash = $Text -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"

Write-Host "RIFLE_DEFINITION_EQUIP_SUCCESS=$EquipSuccess"
Write-Host "FIRE_DISPATCH_COUNT=$FireDispatch"
Write-Host "FIRE_DISPATCH_REJECT_COUNT=$FireDispatchReject"
Write-Host "FIRE_REQUEST_COUNT=$FireRequest"
Write-Host "FIRE_AUTH_ACCEPTED_COUNT=$FireAccepted"
Write-Host "FIRE_AUTH_REJECT_NO_DEFINITION_COUNT=$FireNoDef"
Write-Host "FIRE_AUTH_REJECT_RELOADING_COUNT=$FireReloading"
Write-Host "FIRE_AUTH_REJECT_EMPTY_COUNT=$FireEmpty"
Write-Host "FIRE_AUTH_REJECT_COOLDOWN_COUNT=$FireCooldown"
Write-Host "FIRE_AUTH_HIT_RESULT_COUNT=$FireHit"

Write-Host "RELOAD_KEY_COUNT=$ReloadKey"
Write-Host "RELOAD_ACCEPTED_COUNT=$ReloadAccepted"
Write-Host "RELOAD_FINISHED_COUNT=$ReloadFinished"
Write-Host "RELOAD_REJECT_FULL_MAG_COUNT=$ReloadFull"
Write-Host "RELOAD_REJECT_NO_DEFINITION_COUNT=$ReloadNoDef"
Write-Host "RELOAD_REJECT_NO_RESERVE_COUNT=$ReloadNoReserve"

Write-Host "JEDDAH_RUNTIME_SEEN=$Jeddah"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"

$ZNoAction = Ask-YesNo "Z_NOW_DOES_NOT_CHANGE_STANCE_OR_GLITCH"
$ShotVisual = Ask-YesNo "VISIBLE_OR_AUDIBLE_SHOT_FEEDBACK_EXISTS"
$ReloadVisual = Ask-YesNo "VISIBLE_OR_AUDIBLE_RELOAD_FEEDBACK_EXISTS"

Write-Host ""
Write-Host "============================================================"
Write-Host " PHASE 03G CLASSIFICATION"
Write-Host "============================================================"

if (-not $Jeddah -or $Fatal -or $Crash) {
    Write-Host "PHASE_03G_QA=FAIL_RUNTIME"
    Write-Host "NEXT_GATE=FIX_RUNTIME"
}
elseif ($ZNoAction -ne "YES") {
    Write-Host "PHASE_03G_QA=FAIL_Z_TEMP_DISABLE"
    Write-Host "NEXT_GATE=REMOVE_REMAINING_Z_INPUT_CONTEXT"
}
elseif (-not $EquipSuccess) {
    Write-Host "PHASE_03G_QA=FAIL_RIFLE_DEFINITION_EQUIP"
    Write-Host "NEXT_GATE=FIX_LOADOUT_RUNTIME"
}
elseif ($FireDispatch -eq 0 -or $FireRequest -eq 0) {
    Write-Host "PHASE_03G_QA=FAIL_FIRE_INPUT_OR_CHARACTER_DISPATCH"
    Write-Host "NEXT_GATE=TRACE_LMB_BINDING_IN_PLAYER_V2_SETUPINPUT"
}
elseif ($FireAccepted -eq 0) {
    Write-Host "PHASE_03G_QA=FAIL_FIRE_AUTHORITY"
    if ($FireNoDef -gt 0) {
        Write-Host "ROOT_CAUSE=FIRE_AUTH_NO_WEAPON_DEFINITION"
    }
    elseif ($FireReloading -gt 0) {
        Write-Host "ROOT_CAUSE=FIRE_BLOCKED_BY_RELOAD_STATE"
    }
    elseif ($FireEmpty -gt 0) {
        Write-Host "ROOT_CAUSE=FIRE_BLOCKED_BY_EMPTY_MAG"
    }
    elseif ($FireCooldown -gt 0) {
        Write-Host "ROOT_CAUSE=ALL_FIRE_ATTEMPTS_BLOCKED_BY_COOLDOWN"
    }
    else {
        Write-Host "ROOT_CAUSE=UNKNOWN_FIRE_AUTHORITY_REJECTION"
    }
    Write-Host "NEXT_GATE=FIX_FIRE_AUTHORITY_BLOCKER"
}
elseif ($ReloadAccepted -eq 0 -or $ReloadFinished -eq 0) {
    Write-Host "PHASE_03G_QA=FIRE_FUNCTIONAL_RELOAD_NOT_FUNCTIONAL"
    if ($ReloadFull -gt 0) {
        Write-Host "ROOT_CAUSE=RELOAD_REQUEST_SAW_FULL_MAG_DESPITE_ACCEPTED_SHOTS"
    }
    elseif ($ReloadNoDef -gt 0) {
        Write-Host "ROOT_CAUSE=RELOAD_LOST_WEAPON_DEFINITION"
    }
    elseif ($ReloadNoReserve -gt 0) {
        Write-Host "ROOT_CAUSE=RELOAD_HAS_NO_RESERVE"
    }
    else {
        Write-Host "ROOT_CAUSE=RELOAD_TIMER_OR_STATE_NOT_COMPLETING"
    }
    Write-Host "NEXT_GATE=FIX_RELOAD_AFTER_PROVEN_FIRE"
}
else {
    Write-Host "PHASE_03G_QA=FIRE_AND_RELOAD_FUNCTIONAL_PASS"

    if ($ShotVisual -eq "NO" -or $ReloadVisual -eq "NO") {
        Write-Host "PRESENTATION_STATUS=GAMEPLAY_FUNCTIONAL_VISUAL_AUDIO_LAYER_MISSING"
        Write-Host "NEXT_GATE=REMOVE_QA_TELEMETRY_THEN_BUILD_TACTICAL_FIRE_RELOAD_PRESENTATION"
    }
    else {
        Write-Host "PRESENTATION_STATUS=BASIC_FEEDBACK_PRESENT"
        Write-Host "NEXT_GATE=REMOVE_QA_TELEMETRY_THEN_BUILD_LAYERED_TACTICAL_UPPER_BODY_AND_TRUE_PRONE"
    }
}

Write-Host "TRUE_PRONE=DEFERRED_UNTIL_DEDICATED_ANIMATION_STATE"
Write-Host "QA_TELEMETRY_MUST_BE_REMOVED_BEFORE_COMMIT"
Write-Host "DO_NOT_COMMIT_YET"
Write-Host "DO_NOT_TOUCH_MAIN"
