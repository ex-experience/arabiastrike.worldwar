[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$PackagedExe = "D:\ASWW_STAGE\Windows\ArabiaStrikeWorldWar.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PACKAGED_POSSESSION_STREAMING_DIAGNOSTIC=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

Set-Location $ProjectRoot
$env:GIT_PAGER = "cat"

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

if (-not (Test-Path -LiteralPath $PackagedExe -PathType Leaf)) {
    Stop-Gate "PACKAGED_EXE_NOT_FOUND_$PackagedExe" 11
}

$RuntimeRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\PackagedRuntime"
$LatestLog = Get-ChildItem -LiteralPath $RuntimeRoot -Filter "packaged_runtime_*.log" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $LatestLog) {
    Stop-Gate "NO_PACKAGED_RUNTIME_LOG_FOUND" 12
}

$LogPath = $LatestLog.FullName
$LogText = Get-Content -Raw -LiteralPath $LogPath

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SOURCE-SIDE PLAYER / CAMERA / STREAMING CONFIG" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$SourceFiles = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "Source") -File -Recurse -Include *.h,*.cpp -ErrorAction SilentlyContinue
$ConfigFiles = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "Config") -File -Recurse -Include *.ini -ErrorAction SilentlyContinue

$SourcePatterns = @(
    "DefaultPawnClass",
    "PlayerControllerClass",
    "HUDClass",
    "SpectatorClass",
    "RestartPlayer",
    "SpawnDefaultPawn",
    "Possess(",
    "AutoPossessPlayer",
    "AutoPossessAI",
    "SetViewTarget",
    "CameraComponent",
    "UCameraComponent",
    "SpringArm",
    "WorldPartitionStreamingSource",
    "bEnableStreamingSource",
    "StreamingSource"
)

foreach ($Pattern in $SourcePatterns) {
    $Matches = $SourceFiles | Select-String -SimpleMatch -Pattern $Pattern -ErrorAction SilentlyContinue
    if ($Matches) {
        foreach ($M in ($Matches | Select-Object -First 30)) {
            $Rel = $M.Path.Substring($ProjectRoot.Length).TrimStart('\')
            Write-Host ("SOURCE_MATCH={0}:{1}:{2}" -f $Rel,$M.LineNumber,$M.Line.Trim())
        }
    }
}

Write-Host ""
Write-Host "=== MAP / GAMEMODE CONFIG ===" -ForegroundColor Yellow
$ConfigMatches = $ConfigFiles | Select-String -Pattern "GameDefaultMap|ServerDefaultMap|GlobalDefaultGameMode|GameMode|DefaultPawn|PlayerController" -ErrorAction SilentlyContinue
if ($ConfigMatches) {
    foreach ($M in ($ConfigMatches | Select-Object -First 80)) {
        $Rel = $M.Path.Substring($ProjectRoot.Length).TrimStart('\')
        Write-Host ("CONFIG_MATCH={0}:{1}:{2}" -f $Rel,$M.LineNumber,$M.Line.Trim())
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " EXISTING PACKAGED RUNTIME — PLAYER / STREAMING EVIDENCE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "RUNTIME_LOG=$LogPath"

$Patterns = @(
    "Jeddah_RedSea_Assault",
    "ASGameMode",
    "PlayerStart",
    "PlayerController",
    "Possess",
    "Pawn",
    "Spectator",
    "Camera",
    "ASSoldierCharacter",
    "ASChaosHummerPawn",
    "ASHelicopterPawn",
    "ASBossCharacter",
    "ASObjectiveVolume",
    "ASMissionDirector",
    "ASWorldBootstrap",
    "WorldPartition",
    "StreamingSource",
    "RuntimeHash",
    "Cell",
    "Loading",
    "Unloading",
    "LogVehicle",
    "EnhancedInput",
    "Fatal",
    "Error:",
    "Warning:"
)

foreach ($Pattern in $Patterns) {
    $Matches = Select-String -LiteralPath $LogPath -SimpleMatch -Pattern $Pattern -ErrorAction SilentlyContinue
    if ($Matches) {
        foreach ($M in ($Matches | Select-Object -First 40)) {
            Write-Host ("RUNTIME_MATCH={0}:{1}" -f $M.LineNumber,$M.Line.Trim())
        }
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLASSIFICATION SIGNALS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$DefaultPawnConfigured = [bool]($SourceFiles | Select-String -SimpleMatch -Pattern "DefaultPawnClass" -ErrorAction SilentlyContinue | Select-Object -First 1)
$PlayerControllerConfigured = [bool]($SourceFiles | Select-String -SimpleMatch -Pattern "PlayerControllerClass" -ErrorAction SilentlyContinue | Select-Object -First 1)
$CameraConfigured = [bool]($SourceFiles | Select-String -Pattern "UCameraComponent|CameraComponent|SpringArm" -ErrorAction SilentlyContinue | Select-Object -First 1)
$PossessionLogged = $LogText -match "(?i)Possess|Possessed|RestartPlayer|SpawnDefaultPawn"
$PlayerControllerLogged = $LogText -match "(?i)PlayerController"
$SoldierLogged = $LogText -match "ASSoldierCharacter"
$HummerLogged = $LogText -match "ASChaosHummerPawn"
$HeliLogged = $LogText -match "ASHelicopterPawn"
$BossLogged = $LogText -match "ASBossCharacter"
$ObjectiveLogged = $LogText -match "ASObjectiveVolume"
$MissionLogged = $LogText -match "ASMissionDirector"
$BootstrapLogged = $LogText -match "ASWorldBootstrap"
$StreamingLogged = $LogText -match "(?i)WorldPartition|StreamingSource|RuntimeHash|Streaming Cell|Activate.*Cell|Load.*Cell"

Write-Host "SOURCE_DEFAULT_PAWN_CONFIG_SEEN=$DefaultPawnConfigured"
Write-Host "SOURCE_PLAYER_CONTROLLER_CONFIG_SEEN=$PlayerControllerConfigured"
Write-Host "SOURCE_CAMERA_CONFIG_SEEN=$CameraConfigured"
Write-Host "RUNTIME_POSSESSION_MARKER_SEEN=$PossessionLogged"
Write-Host "RUNTIME_PLAYER_CONTROLLER_MARKER_SEEN=$PlayerControllerLogged"
Write-Host "RUNTIME_SOLDIER_MARKER_SEEN=$SoldierLogged"
Write-Host "RUNTIME_HUMMER_MARKER_SEEN=$HummerLogged"
Write-Host "RUNTIME_HELICOPTER_MARKER_SEEN=$HeliLogged"
Write-Host "RUNTIME_BOSS_MARKER_SEEN=$BossLogged"
Write-Host "RUNTIME_OBJECTIVE_MARKER_SEEN=$ObjectiveLogged"
Write-Host "RUNTIME_MISSION_DIRECTOR_MARKER_SEEN=$MissionLogged"
Write-Host "RUNTIME_WORLD_BOOTSTRAP_MARKER_SEEN=$BootstrapLogged"
Write-Host "RUNTIME_WORLD_PARTITION_STREAMING_MARKER_SEEN=$StreamingLogged"

Write-Host ""
Write-Host "PACKAGED_POSSESSION_STREAMING_DIAGNOSTIC=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=CLASSIFY_FROM_SOURCE_AND_RUNTIME_EVIDENCE" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
