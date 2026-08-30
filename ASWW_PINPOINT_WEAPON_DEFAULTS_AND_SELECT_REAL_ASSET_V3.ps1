[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "WEAPON_PINPOINT_V3=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Read-All([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return Get-Content -Raw -LiteralPath $Path
    }
    return ""
}

function Extract-FunctionBody {
    param(
        [string]$Text,
        [string]$SignatureRegex
    )

    $m = [regex]::Match(
        $Text,
        $SignatureRegex,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    if (-not $m.Success) {
        return $null
    }

    $start = $m.Index + $m.Length
    $brace = $Text.IndexOf('{', $start)
    if ($brace -lt 0) {
        return $null
    }

    $depth = 0
    for ($i = $brace; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $Text.Substring($brace, $i - $brace + 1)
            }
        }
    }

    return $null
}

Set-Location $ProjectRoot
$env:GIT_PAGER = "cat"

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

$CharacterCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"
$WeaponH = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Combat\ASWeaponComponent.h"
$WeaponCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Combat\ASWeaponComponent.cpp"
$ProjectileH = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Combat\ASProjectile.h"
$ProjectileCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Combat\ASProjectile.cpp"
$InventoryH = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Combat\ASWeaponInventoryComponent.h"
$InventoryCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Combat\ASWeaponInventoryComponent.cpp"

foreach ($Required in @($CharacterCpp,$WeaponH,$WeaponCpp,$ProjectileH,$ProjectileCpp)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

$CharacterText = Read-All $CharacterCpp
$WeaponHeaderText = Read-All $WeaponH
$WeaponCppText = Read-All $WeaponCpp
$ProjectileText = (Read-All $ProjectileH) + "`n" + (Read-All $ProjectileCpp)
$InventoryText = (Read-All $InventoryH) + "`n" + (Read-All $InventoryCpp)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " EXACT COMBAT SOURCE CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$FireOnceBody = Extract-FunctionBody -Text $CharacterText -SignatureRegex 'void\s+AASCharacter::FireOnce\s*\([^)]*\)'
$WeaponCtorBody = Extract-FunctionBody -Text $WeaponCppText -SignatureRegex 'UASWeaponComponent::UASWeaponComponent\s*\([^)]*\)'
$WeaponFireBody = $null

foreach ($sig in @(
    'void\s+UASWeaponComponent::Fire\s*\([^)]*\)',
    'bool\s+UASWeaponComponent::Fire\s*\([^)]*\)',
    'void\s+UASWeaponComponent::TryFire\s*\([^)]*\)',
    'bool\s+UASWeaponComponent::TryFire\s*\([^)]*\)',
    'void\s+UASWeaponComponent::StartFire\s*\([^)]*\)',
    'bool\s+UASWeaponComponent::StartFire\s*\([^)]*\)'
)) {
    $WeaponFireBody = Extract-FunctionBody -Text $WeaponCppText -SignatureRegex $sig
    if ($WeaponFireBody) { break }
}

$ProjectileClassDeclared = $WeaponHeaderText -match 'TSubclassOf\s*<\s*AASProjectile\s*>\s+ProjectileClass|ProjectileClass'
$ProjectileCtorAssignment = $false
$ProjectileCtorValue = "NONE_FOUND"

if ($WeaponCtorBody) {
    $pm = [regex]::Match(
        $WeaponCtorBody,
        'ProjectileClass\s*=\s*([^;]+);',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if ($pm.Success) {
        $ProjectileCtorAssignment = $true
        $ProjectileCtorValue = ($pm.Groups[1].Value -replace '\s+',' ').Trim()
    }
}

$ProjectileUsedToSpawn = $WeaponCppText -match 'SpawnActor\s*<\s*AASProjectile\s*>|SpawnActor.*ProjectileClass'
$DirectDamageSeen = $WeaponCppText -match 'UGameplayStatics::ApplyDamage|ApplyPointDamage|TakeDamage'
$TraceSeen = $WeaponCppText -match 'LineTrace|SweepSingle'
$ProjectileDamageSeen = $ProjectileText -match 'UGameplayStatics::ApplyDamage|ApplyPointDamage|TakeDamage'

$FireOnceCallsWeapon = $false
$FireOnceCallText = "NONE_FOUND"
if ($FireOnceBody) {
    $fm = [regex]::Match(
        $FireOnceBody,
        '(Weapon\s*->\s*[A-Za-z0-9_]+\s*\([^;]*\);)',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if ($fm.Success) {
        $FireOnceCallsWeapon = $true
        $FireOnceCallText = ($fm.Groups[1].Value -replace '\s+',' ').Trim()
    }
}

$HasAmmoPath = ($WeaponHeaderText + "`n" + $WeaponCppText) -match '\bAmmo\b|Magazine|Rounds|Clip'
$HasReloadPath = ($WeaponHeaderText + "`n" + $WeaponCppText) -match '\bReload\b'
$HasLoadoutPath = $InventoryText -match 'Loadout|Equip|DefaultWeapon|WeaponClass'

Write-Host "PROJECTILE_CLASS_DECLARED=$ProjectileClassDeclared"
Write-Host "PROJECTILE_CLASS_CPP_DEFAULT_ASSIGNED=$ProjectileCtorAssignment"
Write-Host "PROJECTILE_CLASS_CPP_DEFAULT_VALUE=$ProjectileCtorValue"
Write-Host "PROJECTILE_CLASS_USED_BY_SPAWN_PATH=$ProjectileUsedToSpawn"
Write-Host "WEAPON_DIRECT_DAMAGE_PATH=$DirectDamageSeen"
Write-Host "WEAPON_TRACE_PATH=$TraceSeen"
Write-Host "PROJECTILE_DAMAGE_PATH=$ProjectileDamageSeen"
Write-Host "FIREONCE_CALLS_WEAPON_COMPONENT=$FireOnceCallsWeapon"
Write-Host "FIREONCE_CALL=$FireOnceCallText"
Write-Host "AMMO_PATH_PRESENT=$HasAmmoPath"
Write-Host "RELOAD_PATH_PRESENT=$HasReloadPath"
Write-Host "INVENTORY_LOADOUT_PATH_PRESENT=$HasLoadoutPath"

Write-Host ""
Write-Host "=== FireOnce body ===" -ForegroundColor Yellow
if ($FireOnceBody) { Write-Host $FireOnceBody } else { Write-Host "NOT_FOUND" }

Write-Host ""
Write-Host "=== Weapon constructor body ===" -ForegroundColor Yellow
if ($WeaponCtorBody) { Write-Host $WeaponCtorBody } else { Write-Host "NOT_FOUND" }

Write-Host ""
Write-Host "=== Weapon fire-like body ===" -ForegroundColor Yellow
if ($WeaponFireBody) { Write-Host $WeaponFireBody } else { Write-Host "NOT_FOUND" }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " STRICT REAL WEAPON ASSET CANDIDATES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Roots = @(
    (Join-Path $UERoot "Templates"),
    (Join-Path $UERoot "TemplateResources"),
    (Join-Path $UERoot "FeaturePacks"),
    (Join-Path $UERoot "Engine\Plugins")
) | Where-Object { Test-Path -LiteralPath $_ -PathType Container }

# Strong token filter. Avoid broad substring matches such as "ak".
$NameRegex = '(?i)(rifle|assault[_\-\s]?rifle|pistol|shotgun|carbine|smg|sniper|revolver|firearm|machine[_\-\s]?gun|weapon[_\-\s]?mesh|gun[_\-\s]?mesh|m4a1|m16|ak47|ak[_\-\s]?47|ak74|ak[_\-\s]?74)'

$Candidates = @()

foreach ($Root in $Roots) {
    $Found = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "*.uasset" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.BaseName -match $NameRegex -or
            $_.DirectoryName -match '(?i)\\(Weapons?|Rifles?|Pistols?|Firearms?|Guns?)\\'
        } |
        Where-Object {
            $_.FullName -notmatch '(?i)\\Editor|\\Debug|\\Materials?\\|\\Functions?\\|\\Icons?\\|\\Water\\|Lake|\\Niagara\\'
        }

    foreach ($Item in $Found) {
        $score = 0
        $n = $Item.BaseName.ToLowerInvariant()
        $path = $Item.FullName.ToLowerInvariant()

        if ($n -match 'rifle|assault') { $score += 60 }
        if ($n -match 'm4a1|m16|ak47|ak_47|ak74|ak_74') { $score += 50 }
        if ($n -match 'sm_|sk_|skeletal|static') { $score += 15 }
        if ($path -match '\\templates\\|\\templateresources\\') { $score += 20 }
        if ($path -match '\\weapons?\\|\\rifles?\\|\\firearms?\\') { $score += 25 }
        if ($n -match 'pistol') { $score += 10 }
        if ($n -match 'shotgun') { $score += 10 }

        # Penalize things obviously unlikely to be a visible weapon mesh.
        if ($n -match 'anim|montage|sound|audio|niagara|material|texture|icon|curve|data|input|bp_') {
            $score -= 40
        }

        $Candidates += [pscustomobject]@{
            Score = $score
            Name = $Item.BaseName
            FullName = $Item.FullName
        }
    }
}

$Candidates = @(
    $Candidates |
    Sort-Object @{Expression='Score';Descending=$true}, FullName -Unique
)

Write-Host "STRICT_REAL_WEAPON_CANDIDATE_COUNT=$($Candidates.Count)"

$Top = @($Candidates | Select-Object -First 30)
$i = 0
foreach ($C in $Top) {
    $i++
    Write-Host "WEAPON_ASSET_CANDIDATE_$i|SCORE=$($C.Score)|NAME=$($C.Name)|PATH=$($C.FullName)"
}

$Best = $null
if ($Top.Count -gt 0) {
    $Best = $Top[0]
    Write-Host "BEST_WEAPON_ASSET_CANDIDATE_SCORE=$($Best.Score)"
    Write-Host "BEST_WEAPON_ASSET_CANDIDATE_NAME=$($Best.Name)"
    Write-Host "BEST_WEAPON_ASSET_CANDIDATE_PATH=$($Best.FullName)"
}
else {
    Write-Host "BEST_WEAPON_ASSET_CANDIDATE_SCORE=-1"
    Write-Host "BEST_WEAPON_ASSET_CANDIDATE_NAME=NONE"
    Write-Host "BEST_WEAPON_ASSET_CANDIDATE_PATH=NONE"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FINAL PINPOINT CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$FunctionalBlockers = New-Object System.Collections.Generic.List[string]

if (-not $FireOnceCallsWeapon) {
    $FunctionalBlockers.Add("FIREONCE_DOES_NOT_CALL_WEAPON_COMPONENT")
}

if ($ProjectileClassDeclared -and $ProjectileUsedToSpawn -and -not $ProjectileCtorAssignment) {
    $FunctionalBlockers.Add("PROJECTILE_CLASS_HAS_NO_CPP_DEFAULT")
}

if (-not $ProjectileUsedToSpawn -and -not $DirectDamageSeen -and -not $TraceSeen) {
    $FunctionalBlockers.Add("WEAPON_HAS_NO_CONFIRMED_DAMAGE_DELIVERY_PATH")
}

if ($ProjectileUsedToSpawn -and -not $ProjectileDamageSeen -and -not $DirectDamageSeen) {
    $FunctionalBlockers.Add("PROJECTILE_SPAWN_PATH_EXISTS_BUT_DAMAGE_APPLICATION_NOT_FOUND")
}

if ($FunctionalBlockers.Count -eq 0) {
    Write-Host "COMBAT_FUNCTIONAL_DEFAULT_CLASSIFICATION=NO_STATIC_BLOCKER_FOUND" -ForegroundColor Green
}
else {
    foreach ($B in $FunctionalBlockers) {
        Write-Host "COMBAT_FUNCTIONAL_BLOCKER=$B" -ForegroundColor Yellow
    }
    Write-Host "COMBAT_FUNCTIONAL_DEFAULT_CLASSIFICATION=BLOCKER_CONFIRMED" -ForegroundColor Yellow
}

if ($Best -and $Best.Score -ge 40) {
    Write-Host "WEAPON_VISUAL_ASSET_CLASSIFICATION=STRONG_LOCAL_CANDIDATE_FOUND" -ForegroundColor Green
}
elseif ($Best) {
    Write-Host "WEAPON_VISUAL_ASSET_CLASSIFICATION=WEAK_LOCAL_CANDIDATE_REVIEW_REQUIRED" -ForegroundColor Yellow
}
else {
    Write-Host "WEAPON_VISUAL_ASSET_CLASSIFICATION=NO_LOCAL_CANDIDATE" -ForegroundColor Yellow
}

if ($FunctionalBlockers.Count -gt 0) {
    Write-Host "NEXT_GATE=PATCH_ONLY_CONFIRMED_FUNCTIONAL_BLOCKERS_THEN_ADD_WEAPON_VISUAL" -ForegroundColor Green
}
elseif ($Best -and $Best.Score -ge 40) {
    Write-Host "NEXT_GATE=INTEGRATE_STRONG_REAL_WEAPON_VISUAL_AND_RUNTIME_PROOF" -ForegroundColor Green
}
else {
    Write-Host "NEXT_GATE=REVIEW_TOP_WEAPON_ASSET_CANDIDATES_BEFORE_ANY_WRITE" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " GIT SAFETY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"

Write-Host ""
Write-Host "WEAPON_PINPOINT_V3=PASS" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
