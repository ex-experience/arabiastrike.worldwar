[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\CombatDamageDeathRespawnQA"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PACKAGED_COMBAT_QA=STOPPED" -ForegroundColor Red
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
$StdOut = Join-Path $EvidenceRoot "combat_qa_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "combat_qa_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PACKAGED COMBAT / DAMAGE / DEATH / RESPAWN QA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Use the current CLEAN packaged build." -ForegroundColor Yellow
Write-Host ""
Write-Host "TEST SEQUENCE:" -ForegroundColor Yellow
Write-Host "1) Confirm Manny can still move and aim." -ForegroundColor Yellow
Write-Host "2) Fire the equipped weapon several times." -ForegroundColor Yellow
Write-Host "3) Shoot a prototype enemy until you can confirm it takes damage or dies." -ForegroundColor Yellow
Write-Host "4) Allow an enemy to damage the player." -ForegroundColor Yellow
Write-Host "5) Continue until the player reaches downed/death/eliminated state." -ForegroundColor Yellow
Write-Host "6) Wait through bleedout if applicable." -ForegroundColor Yellow
Write-Host "7) Confirm respawn/restart actually returns control to a live player pawn." -ForegroundColor Yellow
Write-Host "8) After respawn, move and fire once more." -ForegroundColor Yellow
Write-Host "9) Close the game normally." -ForegroundColor Yellow
Write-Host ""
Write-Host "Do not infer PASS from the log alone; visual gameplay confirmation is required." -ForegroundColor DarkYellow
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
if (Test-Path -LiteralPath $StdOut) {
    $Text += Get-Content -Raw -LiteralPath $StdOut
}
if (Test-Path -LiteralPath $StdErr) {
    $Text += "`n" + (Get-Content -Raw -LiteralPath $StdErr)
}

$Jeddah = $Text -match "/Game/Maps/Jeddah_RedSea_Assault|Jeddah_RedSea_Assault"
$Manny = $Text -match "ASWW_REAL_PLAYER_MANNY"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Crash = $Text -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"
$TempMarkers = $Text -match "ASWW_TELEMETRY|ASWW_MOVE_STATE|ASWW_Telemetry_|ASWW_MoveState_|ASWW_VISUAL_PROOF|ASWW_PlayerVisualProof"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RUNTIME HEALTH CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "JEDDAH_RUNTIME_SEEN=$Jeddah"
Write-Host "REAL_MANNY_MARKER_SEEN=$Manny"
Write-Host "TEMP_QA_MARKERS_SEEN=$TempMarkers"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"

if ($Jeddah -and $Manny -and -not $TempMarkers -and -not $Fatal -and -not $Crash) {
    Write-Host "COMBAT_QA_RUNTIME_HEALTH=PASS" -ForegroundColor Green
} else {
    Write-Host "COMBAT_QA_RUNTIME_HEALTH=INCONCLUSIVE_OR_FAIL" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RELEVANT LOG HINTS (NOT BEHAVIOR PROOF)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (Test-Path -LiteralPath $StdOut) {
    Select-String -LiteralPath $StdOut `
        -Pattern "damage|damaged|death|dead|downed|eliminated|bleedout|respawn|restartplayer|projectile|weapon|fire|hit" `
        -CaseSensitive:$false |
        Select-Object -First 220 |
        ForEach-Object { Write-Host $_.Line }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REPORT VISUAL / GAMEPLAY RESULT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PLAYER_FIRE_WORKS=YES/NO"
Write-Host "PROJECTILE_OR_HIT_EFFECT_VISIBLE=YES/NO"
Write-Host "ENEMY_TAKES_DAMAGE=YES/NO"
Write-Host "ENEMY_CAN_DIE=YES/NO"
Write-Host "PLAYER_TAKES_DAMAGE=YES/NO"
Write-Host "PLAYER_ENTERS_DOWNED_OR_DEATH=YES/NO"
Write-Host "BLEEDOUT_OR_ELIMINATION_COMPLETES=YES/NO/NOT_APPLICABLE"
Write-Host "RESPAWN_RETURNS_LIVE_PLAYER=YES/NO"
Write-Host "POST_RESPAWN_MOVEMENT_WORKS=YES/NO"
Write-Host "POST_RESPAWN_FIRE_WORKS=YES/NO"
Write-Host "FIRST_VISIBLE_BLOCKER=<NONE or exact first failure>"
Write-Host ""
Write-Host "PACKAGED_COMBAT_QA=MANUAL_CONFIRMATION_REQUIRED" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
