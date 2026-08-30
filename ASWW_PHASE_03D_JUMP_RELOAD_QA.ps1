[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\JumpReloadInputProof"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_03D_JUMP_RELOAD_QA=STOPPED"
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
$StdOut = Join-Path $EvidenceRoot "jump_reload_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "jump_reload_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================"
Write-Host " JUMP / RELOAD INPUT PROOF"
Write-Host "============================================================"
Write-Host "When the game opens:"
Write-Host "1) Press SPACE three separate times while standing on clear ground."
Write-Host "2) Press R three separate times."
Write-Host "3) Observe whether the player physically leaves the ground."
Write-Host "4) Observe whether any reload action/animation is visible."
Write-Host "5) Exit the game normally."
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

$JumpCount = ([regex]::Matches($Text, "ASWW_QA_JUMP_INPUT")).Count
$ReloadCount = ([regex]::Matches($Text, "ASWW_QA_RELOAD_INPUT")).Count
$DispatchCount = ([regex]::Matches($Text, "ASWW_QA_RELOAD_DISPATCHED")).Count
$Jeddah = $Text -match "Jeddah_RedSea_Assault"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Crash = $Text -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"

Write-Host "JUMP_INPUT_MARKER_COUNT=$JumpCount"
Write-Host "RELOAD_INPUT_MARKER_COUNT=$ReloadCount"
Write-Host "RELOAD_DISPATCH_MARKER_COUNT=$DispatchCount"
Write-Host "JEDDAH_RUNTIME_SEEN=$Jeddah"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"

$JumpVisible = Ask-YesNo "JUMP_PHYSICAL_MOVEMENT_VISIBLE"
$ReloadVisible = Ask-YesNo "RELOAD_ACTION_OR_ANIMATION_VISIBLE"

$JumpInput = $JumpCount -gt 0
$ReloadInput = $ReloadCount -gt 0 -and $DispatchCount -gt 0
$RuntimeHealthy = $Jeddah -and -not $Fatal -and -not $Crash

Write-Host ""
Write-Host "============================================================"
Write-Host " PHASE 03D CLASSIFICATION"
Write-Host "============================================================"

if (-not $RuntimeHealthy) {
    Write-Host "PHASE_03D_RESULT=FAIL_RUNTIME"
    Write-Host "NEXT_GATE=FIX_RUNTIME"
}
elseif (-not $JumpInput) {
    Write-Host "PHASE_03D_RESULT=FAIL_JUMP_INPUT_BINDING"
    Write-Host "NEXT_GATE=FIX_JUMP_BINDING_OR_POSSESSION"
}
elseif (-not $ReloadInput) {
    Write-Host "PHASE_03D_RESULT=FAIL_RELOAD_INPUT_BINDING"
    Write-Host "NEXT_GATE=FIX_RELOAD_BINDING_OR_DISPATCH"
}
else {
    Write-Host "PHASE_03D_INPUT_LAYER=PASS"

    if ($JumpVisible -eq "YES" -and $ReloadVisible -eq "NO") {
        Write-Host "ROOT_CAUSE=RELOAD_IS_NOT_AN_INPUT_FAILURE"
        Write-Host "INTERPRETATION=ABP_UNARMED_PRESERVES_LOCOMOTION_BUT_HAS_NO_VISIBLE_RIFLE_RELOAD_PRESENTATION"
        Write-Host "NEXT_GATE=BUILD_LAYERED_TACTICAL_UPPER_BODY_RELOAD_AIM_PLUS_LEFT_HAND_IK"
    }
    elseif ($JumpVisible -eq "YES" -and $ReloadVisible -eq "YES") {
        Write-Host "ROOT_CAUSE=INPUT_AND_BASIC_ACTIONS_PASS_ON_PROVEN_LOCOMOTION"
        Write-Host "NEXT_GATE=BUILD_LAYERED_TACTICAL_UPPER_BODY_PLUS_LEFT_HAND_IK"
    }
    elseif ($JumpVisible -eq "NO") {
        Write-Host "ROOT_CAUSE=JUMP_INPUT_REACHES_PLAYER_BUT_PHYSICAL_JUMP_REMAINS_BLOCKED"
        Write-Host "NEXT_GATE=DIAGNOSE_TRYMANTLE_CANJUMP_MOVEMENTMODE"
    }
    else {
        Write-Host "ROOT_CAUSE=MIXED_ACTION_PRESENTATION"
        Write-Host "NEXT_GATE=BUILD_LAYERED_TACTICAL_ANIMATION_WITH_ACTION_SPECIFIC_VALIDATION"
    }
}

Write-Host "QA_ONLY_TELEMETRY_MUST_BE_REMOVED_BEFORE_COMMIT"
Write-Host "DO_NOT_COMMIT_YET"
Write-Host "DO_NOT_TOUCH_MAIN"
