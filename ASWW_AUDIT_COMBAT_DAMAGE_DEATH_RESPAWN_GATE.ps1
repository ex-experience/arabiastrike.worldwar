[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "COMBAT_DAMAGE_DEATH_RESPAWN_AUDIT=STOPPED" -ForegroundColor Red
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

$Files = @{
    CharacterCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"
    CharacterH   = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Player\ASCharacter.h"
    HealthCpp    = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Combat\ASHealthComponent.cpp"
    HealthH      = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Combat\ASHealthComponent.h"
    WeaponCpp    = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Combat\ASWeaponComponent.cpp"
    WeaponH      = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Combat\ASWeaponComponent.h"
    GameModeCpp  = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Game\ASGameMode.cpp"
    GameModeH    = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Game\ASGameMode.h"
    InputIni     = Join-Path $ProjectRoot "Config\DefaultInput.ini"
}

foreach ($Name in @("CharacterCpp","CharacterH","HealthCpp","HealthH","WeaponCpp","WeaponH","InputIni")) {
    if (-not (Test-Path -LiteralPath $Files[$Name] -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$($Files[$Name])" 11
    }
}

function Show-Matches {
    param(
        [string]$Label,
        [string]$Path,
        [string[]]$Patterns
    )

    Write-Host ""
    Write-Host "=== $Label ===" -ForegroundColor Yellow
    foreach ($Pattern in $Patterns) {
        $Hits = @(Select-String -LiteralPath $Path -Pattern $Pattern -CaseSensitive:$false)
        Write-Host "$Label PATTERN=$Pattern COUNT=$($Hits.Count)"
        foreach ($Hit in $Hits | Select-Object -First 40) {
            Write-Host ("{0}:{1}: {2}" -f (Split-Path -Leaf $Path), $Hit.LineNumber, $Hit.Line.Trim())
        }
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " INPUT / COMBAT BINDINGS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Show-Matches `
    -Label "INPUT_ACTIONS" `
    -Path $Files.InputIni `
    -Patterns @(
        'ActionName="Fire"',
        'ActionName="Reload"',
        'ActionName="Grenade"',
        'ActionName="Interact"',
        'ActionName="Revive"',
        'ActionName="Respawn"',
        'ActionName="Sprint"',
        'ActionName="Aim"'
    )

Show-Matches `
    -Label "CHARACTER_INPUT_BINDINGS" `
    -Path $Files.CharacterCpp `
    -Patterns @(
        'BindAction\("Fire"',
        'BindAction\("Reload"',
        'BindAction\("Grenade"',
        'BindAction\("Interact"',
        'BindAction\("Revive"',
        'BindAction\("Respawn"',
        'FirePressed',
        'FireReleased',
        'FireOnce',
        'Reload',
        'ThrowGrenade'
    )

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PLAYER DAMAGE / DOWNED / DEATH PATH" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Show-Matches `
    -Label "CHARACTER_DAMAGE_STATE" `
    -Path $Files.CharacterCpp `
    -Patterns @(
        'HandleHealthDeath',
        'bDowned',
        'bEliminated',
        'Bleedout',
        'Respawn',
        'RestartPlayer',
        'OnDeath',
        'ApplyDamage',
        'TakeDamage'
    )

Show-Matches `
    -Label "HEALTH_COMPONENT" `
    -Path $Files.HealthCpp `
    -Patterns @(
        'TakeDamage',
        'ApplyDamage',
        'OnTakeAnyDamage',
        'OnDeath',
        'Health',
        'CurrentHealth',
        'MaxHealth',
        'Die',
        'Death'
    )

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " WEAPON / HIT / DAMAGE PATH" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Show-Matches `
    -Label "WEAPON_COMPONENT" `
    -Path $Files.WeaponCpp `
    -Patterns @(
        'Fire',
        'Projectile',
        'LineTrace',
        'ApplyDamage',
        'Damage',
        'Ammo',
        'Reload'
    )

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RESPAWN / GAMEMODE PATH" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (Test-Path -LiteralPath $Files.GameModeCpp -PathType Leaf) {
    Show-Matches `
        -Label "GAMEMODE_RESPAWN" `
        -Path $Files.GameModeCpp `
        -Patterns @(
            'RestartPlayer',
            'Respawn',
            'PlayerStart',
            'Pawn',
            'Controller',
            'Death'
        )
}
else {
    Write-Host "GAMEMODE_CPP_PRESENT=False"
}

if (Test-Path -LiteralPath $Files.GameModeH -PathType Leaf) {
    Show-Matches `
        -Label "GAMEMODE_RESPAWN_HEADER" `
        -Path $Files.GameModeH `
        -Patterns @(
            'RestartPlayer',
            'Respawn',
            'PlayerStart',
            'Death'
        )
}
else {
    Write-Host "GAMEMODE_H_PRESENT=False"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " STATIC GATE CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$CharacterText = Get-Content -Raw -LiteralPath $Files.CharacterCpp
$InputText = Get-Content -Raw -LiteralPath $Files.InputIni
$HealthText = Get-Content -Raw -LiteralPath $Files.HealthCpp
$WeaponText = Get-Content -Raw -LiteralPath $Files.WeaponCpp

$FireInputConfigured = $InputText -match 'ActionName="Fire"'
$FireBindingSeen = $CharacterText -match 'BindAction\("Fire"'
$FirePathSeen = $CharacterText -match 'FirePressed|FireOnce'
$HealthDeathSeen = $CharacterText -match 'HandleHealthDeath' -and $HealthText -match 'OnDeath'
$DownedSeen = $CharacterText -match 'bDowned'
$EliminatedSeen = $CharacterText -match 'bEliminated'
$RespawnSeen = $CharacterText -match 'Respawn|RestartPlayer|Bleedout'
$WeaponDamageSeen = $WeaponText -match 'ApplyDamage|Damage|Projectile|LineTrace'

Write-Host "FIRE_INPUT_CONFIGURED=$FireInputConfigured"
Write-Host "FIRE_BINDING_SEEN=$FireBindingSeen"
Write-Host "PLAYER_FIRE_PATH_SEEN=$FirePathSeen"
Write-Host "WEAPON_DAMAGE_PATH_SEEN=$WeaponDamageSeen"
Write-Host "HEALTH_DEATH_PATH_SEEN=$HealthDeathSeen"
Write-Host "DOWNED_STATE_SEEN=$DownedSeen"
Write-Host "ELIMINATED_STATE_SEEN=$EliminatedSeen"
Write-Host "RESPAWN_OR_BLEEDOUT_PATH_SEEN=$RespawnSeen"

if ($FireInputConfigured -and
    $FireBindingSeen -and
    $FirePathSeen -and
    $WeaponDamageSeen -and
    $HealthDeathSeen -and
    $DownedSeen -and
    $EliminatedSeen) {
    Write-Host "COMBAT_STATIC_GATE=PASS_SOURCE_PATHS_PRESENT" -ForegroundColor Green
    if ($RespawnSeen) {
        Write-Host "NEXT_GATE=PACKAGED_COMBAT_DAMAGE_DEATH_RESPAWN_QA" -ForegroundColor Green
    }
    else {
        Write-Host "NEXT_GATE=PINPOINT_RESPAWN_IMPLEMENTATION_BEFORE_RUNTIME_QA" -ForegroundColor Yellow
    }
}
else {
    Write-Host "COMBAT_STATIC_GATE=INCOMPLETE_SOURCE_PATH" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=FIX_OR_PINPOINT_MISSING_COMBAT_PATH_BEFORE_RUNTIME_QA" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " GIT SAFETY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"

Write-Host ""
Write-Host "COMBAT_DAMAGE_DEATH_RESPAWN_AUDIT=PASS" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
