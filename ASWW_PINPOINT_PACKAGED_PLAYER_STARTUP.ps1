[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location $ProjectRoot
$env:GIT_PAGER = "cat"

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Write-Host "BLOCKER=WRONG_BRANCH_$Branch" -ForegroundColor Red
    exit 10
}

$RuntimeRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\PackagedRuntime"
$LatestLog = Get-ChildItem -LiteralPath $RuntimeRoot -Filter "packaged_runtime_*.log" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $LatestLog) {
    Write-Host "BLOCKER=NO_PACKAGED_RUNTIME_LOG_FOUND" -ForegroundColor Red
    exit 11
}

$SourceRoot = Join-Path $ProjectRoot "Source"
$SourceFiles = Get-ChildItem -LiteralPath $SourceRoot -File -Recurse -Include *.h,*.cpp -ErrorAction Stop

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " GAMEMODE / PLAYER STARTUP SOURCE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Patterns = @(
    "DefaultPawnClass",
    "PlayerControllerClass",
    "HUDClass",
    "SpectatorClass",
    "GameStateClass",
    "PlayerStateClass",
    "RestartPlayer",
    "RestartPlayerAtPlayerStart",
    "SpawnDefaultPawn",
    "SpawnDefaultPawnAtTransform",
    "ChoosePlayerStart",
    "FindPlayerStart",
    "HandleStartingNewPlayer",
    "PostLogin",
    "BeginPlay",
    "Possess(",
    "AutoPossessPlayer",
    "AutoPossessAI"
)

$Matches = @()
foreach ($Pattern in $Patterns) {
    $Matches += $SourceFiles | Select-String -SimpleMatch -Pattern $Pattern -ErrorAction SilentlyContinue
}

$Matches = $Matches | Sort-Object Path,LineNumber -Unique

foreach ($M in ($Matches | Select-Object -First 180)) {
    $Rel = $M.Path.Substring($ProjectRoot.Length).TrimStart('\')
    Write-Host ("SOURCE={0}:{1}:{2}" -f $Rel,$M.LineNumber,$M.Line.Trim())
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CAMERA / PAWN SOURCE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$CameraMatches = $SourceFiles | Select-String `
    -Pattern "UCameraComponent|CameraComponent|SpringArm|SetupPlayerInputComponent|ACharacter|APawn|PlayerController" `
    -ErrorAction SilentlyContinue

foreach ($M in ($CameraMatches | Sort-Object Path,LineNumber | Select-Object -First 180)) {
    $Rel = $M.Path.Substring($ProjectRoot.Length).TrimStart('\')
    Write-Host ("CAMERA_SOURCE={0}:{1}:{2}" -f $Rel,$M.LineNumber,$M.Line.Trim())
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PACKAGED RUNTIME PLAYER STARTUP / SPAWN WARNINGS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "RUNTIME_LOG=$($LatestLog.FullName)"

$RuntimePatterns = @(
    "Game class is",
    "PlayerStart",
    "PlayerController",
    "Possess",
    "Pawn",
    "SpawnActor",
    "Failed to spawn",
    "SpawnDefaultPawn",
    "RestartPlayer",
    "Spectator",
    "Camera",
    "EnhancedInput",
    "LocalPlayer",
    "Login",
    "PostLogin",
    "HandleStartingNewPlayer",
    "LogGameMode",
    "LogPlayerController",
    "LogSpawn",
    "Warning:",
    "Error:"
)

foreach ($Pattern in $RuntimePatterns) {
    $RM = Select-String -LiteralPath $LatestLog.FullName -SimpleMatch -Pattern $Pattern -ErrorAction SilentlyContinue
    foreach ($M in ($RM | Select-Object -First 60)) {
        Write-Host ("RUNTIME={0}:{1}" -f $M.LineNumber,$M.Line.Trim())
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$LogText = Get-Content -Raw -LiteralPath $LatestLog.FullName
$SpawnFailure = $LogText -match "(?i)Failed to spawn|SpawnActor failed|SpawnDefaultPawn.*fail|Couldn't spawn Pawn|No pawn class"
$Possess = $LogText -match "(?i)Possess|Possessed"
$PlayerController = $LogText -match "(?i)PlayerController"
$Camera = $LogText -match "(?i)Camera"
$EnhancedInput = $LogText -match "EnhancedInput"

Write-Host "RUNTIME_SPAWN_FAILURE_MARKER_SEEN=$SpawnFailure"
Write-Host "RUNTIME_POSSESSION_MARKER_SEEN=$Possess"
Write-Host "RUNTIME_PLAYER_CONTROLLER_MARKER_SEEN=$PlayerController"
Write-Host "RUNTIME_CAMERA_MARKER_SEEN=$Camera"
Write-Host "RUNTIME_ENHANCED_INPUT_MARKER_SEEN=$EnhancedInput"

Write-Host ""
Write-Host "PLAYER_STARTUP_PINPOINT=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=CLASSIFY_EXACT_DEFAULT_PAWN_AND_SPAWN_PATH" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
