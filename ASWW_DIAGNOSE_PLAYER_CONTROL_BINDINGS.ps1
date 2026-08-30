[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PLAYER_CONTROL_BINDING_DIAGNOSTIC=STOPPED" -ForegroundColor Red
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

$GameMode = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Game\ASGameMode.cpp"
$Character = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"
$Controller = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASPlayerController.cpp"
$InputIni = Join-Path $ProjectRoot "Config\DefaultInput.ini"

foreach ($f in @($GameMode,$Character,$Controller,$InputIni)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
        Stop-Gate "MISSING_$f" 11
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " DEFAULT PAWN / CONTROLLER CONFIG" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Select-String -LiteralPath $GameMode `
    -Pattern "DefaultPawnClass|PlayerControllerClass|HUDClass|PlayerStateClass|GameStateClass|RestartPlayer|ChoosePlayerStart|FindPlayerStart|SpawnDefaultPawn|HandleStartingNewPlayer|PostLogin" `
    -Context 2,4 |
    Select-Object -First 120

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CHARACTER INPUT BINDINGS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$CharText = Get-Content -Raw -LiteralPath $Character

$BindAxisMatches = [regex]::Matches($CharText, 'BindAxis\s*\(\s*TEXT\("([^"]+)"\)|BindAxis\s*\(\s*"([^"]+)"')
$BindActionMatches = [regex]::Matches($CharText, 'BindAction\s*\(\s*TEXT\("([^"]+)"\)|BindAction\s*\(\s*"([^"]+)"')

$BoundAxes = @()
foreach ($m in $BindAxisMatches) {
    $name = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
    if ($name) { $BoundAxes += $name }
}
$BoundAxes = @($BoundAxes | Sort-Object -Unique)

$BoundActions = @()
foreach ($m in $BindActionMatches) {
    $name = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
    if ($name) { $BoundActions += $name }
}
$BoundActions = @($BoundActions | Sort-Object -Unique)

Write-Host ("BOUND_AXES=" + ($BoundAxes -join ","))
Write-Host ("BOUND_ACTIONS=" + ($BoundActions -join ","))

Select-String -LiteralPath $Character `
    -Pattern "SetupPlayerInputComponent|BindAxis|BindAction|UCameraComponent|CameraBoom|FollowCamera|BeginPlay|GetLocalPlayer|EnhancedInput|MappingContext|AddMappingContext|SetIgnoreMoveInput|SetIgnoreLookInput|DisableInput|EnableInput" `
    -Context 2,5 |
    Select-Object -First 220

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " DEFAULTINPUT.INI MAPPINGS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$IniText = Get-Content -Raw -LiteralPath $InputIni

$AxisNames = @(
    [regex]::Matches($IniText, '(?im)^\s*\+?AxisMappings=.*?AxisName="([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value } |
    Sort-Object -Unique
)

$ActionNames = @(
    [regex]::Matches($IniText, '(?im)^\s*\+?ActionMappings=.*?ActionName="([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value } |
    Sort-Object -Unique
)

Write-Host ("INI_AXES=" + ($AxisNames -join ","))
Write-Host ("INI_ACTIONS=" + ($ActionNames -join ","))

Select-String -LiteralPath $InputIni `
    -Pattern "AxisMappings|ActionMappings|DefaultPlayerInputClass|DefaultInputComponentClass|EnhancedInput|InputSettings" `
    -Context 0,1 |
    Select-Object -First 220

$MissingAxes = @($BoundAxes | Where-Object { $_ -notin $AxisNames })
$MissingActions = @($BoundActions | Where-Object { $_ -notin $ActionNames })

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PLAYER CONTROLLER INPUT MODE / BLOCKERS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Select-String -LiteralPath $Controller `
    -Pattern "BeginPlay|SetupInputComponent|SetInputMode|FInputMode|bShowMouseCursor|SetIgnoreMoveInput|SetIgnoreLookInput|DisableInput|EnableInput|Pause|SetPause|SetCinematicMode|GetPawn|Possess|UnPossess" `
    -Context 3,6 |
    Select-Object -First 220

$ControllerText = Get-Content -Raw -LiteralPath $Controller
$InputModeUIOnly = $ControllerText -match "FInputModeUIOnly|SetInputMode\s*\(\s*FInputModeUIOnly"
$IgnoreMove = $ControllerText -match "SetIgnoreMoveInput\s*\(\s*true\s*\)"
$IgnoreLook = $ControllerText -match "SetIgnoreLookInput\s*\(\s*true\s*\)"
$DisableInput = $ControllerText -match "DisableInput\s*\("

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "BOUND_AXIS_COUNT=$($BoundAxes.Count)"
Write-Host "BOUND_ACTION_COUNT=$($BoundActions.Count)"
Write-Host "INI_AXIS_COUNT=$($AxisNames.Count)"
Write-Host "INI_ACTION_COUNT=$($ActionNames.Count)"
Write-Host ("MISSING_BOUND_AXES=" + $(if ($MissingAxes.Count) { $MissingAxes -join "," } else { "NONE" }))
Write-Host ("MISSING_BOUND_ACTIONS=" + $(if ($MissingActions.Count) { $MissingActions -join "," } else { "NONE" }))
Write-Host "PLAYERCONTROLLER_UI_ONLY_INPUT_MODE_SEEN=$InputModeUIOnly"
Write-Host "PLAYERCONTROLLER_IGNORE_MOVE_TRUE_SEEN=$IgnoreMove"
Write-Host "PLAYERCONTROLLER_IGNORE_LOOK_TRUE_SEEN=$IgnoreLook"
Write-Host "PLAYERCONTROLLER_DISABLE_INPUT_SEEN=$DisableInput"

if (($MissingAxes.Count -gt 0) -or ($MissingActions.Count -gt 0)) {
    Write-Host "PLAYER_CONTROL_CONFIG_CLASSIFICATION=MISSING_LEGACY_INPUT_MAPPINGS" -ForegroundColor Red
    Write-Host "NEXT_GATE=PATCH_ONLY_MISSING_INPUT_MAPPINGS_THEN_REBUILD_PACKAGE" -ForegroundColor Yellow
}
elseif ($InputModeUIOnly -or $IgnoreMove -or $IgnoreLook -or $DisableInput) {
    Write-Host "PLAYER_CONTROL_CONFIG_CLASSIFICATION=PLAYERCONTROLLER_INPUT_BLOCKER_PRESENT" -ForegroundColor Red
    Write-Host "NEXT_GATE=INSPECT_EXACT_CONTROLLER_INPUT_BLOCKER_PATH" -ForegroundColor Yellow
}
else {
    Write-Host "PLAYER_CONTROL_CONFIG_CLASSIFICATION=SOURCE_BINDINGS_APPEAR_COMPLETE" -ForegroundColor Green
    Write-Host "NEXT_GATE=ADD_TEMPORARY_RUNTIME_SPAWN_POSSESSION_INPUT_TELEMETRY" -ForegroundColor Yellow
}

Write-Host "PLAYER_CONTROL_BINDING_DIAGNOSTIC=PASS" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
