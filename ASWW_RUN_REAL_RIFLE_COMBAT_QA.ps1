[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\RealRifleCombatQA"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "REAL_RIFLE_COMBAT_QA=STOPPED" -ForegroundColor Red
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
$StdOut = Join-Path $EvidenceRoot "real_rifle_qa_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "real_rifle_qa_$Stamp.stderr.log"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REAL RIFLE + COMBAT RUNTIME QA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "1) Confirm Manny is still visible and moves normally." -ForegroundColor Yellow
Write-Host "2) Inspect the rifle: visible, attached to right hand, follows animation." -ForegroundColor Yellow
Write-Host "3) Press Fire several times while facing an enemy." -ForegroundColor Yellow
Write-Host "4) Report ANY visible/audio firing response." -ForegroundColor Yellow
Write-Host "5) If firing works, test whether the enemy takes damage / dies." -ForegroundColor Yellow
Write-Host "6) Do NOT infer damage from code; report only what you actually see." -ForegroundColor DarkYellow
Write-Host "7) Close the game normally." -ForegroundColor Yellow
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
$RifleMesh = $Text -match "ASWW_COMBAT_PROOF RIFLE_VISUAL mesh=(?!None|NONE|null)"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Crash = $Text -match "GPU Crashed|EXCEPTION_ACCESS_VIOLATION"
$OldTemp = $Text -match "ASWW_TELEMETRY|ASWW_MOVE_STATE|ASWW_Telemetry_|ASWW_MoveState_|ASWW_VISUAL_PROOF|ASWW_PlayerVisualProof"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RUNTIME HEALTH / RIFLE LOAD" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "JEDDAH_RUNTIME_SEEN=$Jeddah"
Write-Host "REAL_MANNY_MARKER_SEEN=$Manny"
Write-Host "REAL_RIFLE_PROOF_MARKER_SEEN=$Rifle"
Write-Host "REAL_RIFLE_MESH_NONEMPTY_SEEN=$RifleMesh"
Write-Host "OLD_TEMP_QA_MARKERS_SEEN=$OldTemp"
Write-Host "FATAL_ERROR_SEEN=$Fatal"
Write-Host "CRASH_MARKER_SEEN=$Crash"

if ($Jeddah -and $Manny -and $Rifle -and $RifleMesh -and -not $OldTemp -and -not $Fatal -and -not $Crash) {
    Write-Host "REAL_RIFLE_RUNTIME_HEALTH=PASS" -ForegroundColor Green
}
else {
    Write-Host "REAL_RIFLE_RUNTIME_HEALTH=INCONCLUSIVE_OR_FAIL" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REPORT WHAT YOU ACTUALLY SAW" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "MANNY_STILL_WORKS=YES/NO"
Write-Host "RIFLE_VISIBLE=YES/NO"
Write-Host "RIFLE_ATTACHED_TO_RIGHT_HAND=YES/NO"
Write-Host "RIFLE_ORIENTATION_ACCEPTABLE=YES/NO"
Write-Host "RIFLE_FOLLOWS_MANNY_ANIMATION=YES/NO"
Write-Host "PLAYER_FIRE_INPUT_CAUSES_RESPONSE=YES/NO"
Write-Host "FIRE_RESPONSE_TYPE=<NONE / AUDIO / MUZZLE / PROJECTILE / HIT / OTHER>"
Write-Host "ENEMY_TAKES_DAMAGE=YES/NO/NOT_TESTABLE"
Write-Host "ENEMY_CAN_DIE=YES/NO/NOT_TESTABLE"
Write-Host "FIRST_VISIBLE_BLOCKER=<NONE or exact first failure>"
Write-Host ""
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
