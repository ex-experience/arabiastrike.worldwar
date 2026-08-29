[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\WeaponRuntimeDefaultsV2"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "WEAPON_RUNTIME_DEFAULT_AUDIT_V2=STOPPED" -ForegroundColor Red
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

$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"

$WeaponH = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Combat\ASWeaponComponent.h"
$WeaponCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Combat\ASWeaponComponent.cpp"
$InventoryH = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Combat\ASWeaponInventoryComponent.h"
$InventoryCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Combat\ASWeaponInventoryComponent.cpp"
$CharacterCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"
$ProjectileH = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Combat\ASProjectile.h"
$ProjectileCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Combat\ASProjectile.cpp"

foreach ($Required in @($ProjectFile,$EditorCmd,$WeaponH,$WeaponCpp,$CharacterCpp,$ProjectileH,$ProjectileCpp)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " EXACT SOURCE DEFAULT / PROPERTY EXTRACTION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

function Show-SourceEvidence {
    param([string]$Path, [string[]]$Patterns)

    foreach ($Pattern in $Patterns) {
        Select-String -LiteralPath $Path -Pattern $Pattern -CaseSensitive:$false -Context 2,5 |
            Select-Object -First 60 |
            ForEach-Object {
                Write-Host ("SOURCE_EVIDENCE|FILE={0}|LINE={1}|TEXT={2}" -f
                    (Split-Path -Leaf $_.Path),
                    $_.LineNumber,
                    $_.Line.Trim())
            }
    }
}

Show-SourceEvidence -Path $WeaponH -Patterns @(
    'UPROPERTY',
    'ProjectileClass',
    'Damage',
    'Ammo',
    'Magazine',
    'Reload',
    'FireRate',
    'Muzzle',
    'Range'
)

Show-SourceEvidence -Path $WeaponCpp -Patterns @(
    'UASWeaponComponent::UASWeaponComponent',
    'ProjectileClass\s*=',
    'Damage\s*=',
    'Ammo\s*=',
    'Magazine',
    'Reload',
    'FireRate\s*=',
    'Muzzle',
    'SpawnActor',
    'ApplyDamage',
    'LineTrace'
)

if (Test-Path -LiteralPath $InventoryH -PathType Leaf) {
    Show-SourceEvidence -Path $InventoryH -Patterns @('UPROPERTY','Loadout','Weapon','Equip','Default')
}
if (Test-Path -LiteralPath $InventoryCpp -PathType Leaf) {
    Show-SourceEvidence -Path $InventoryCpp -Patterns @('Loadout','Weapon','Equip','Default')
}

Show-SourceEvidence -Path $CharacterCpp -Patterns @(
    'FireOnce',
    'FirePressed',
    'Weapon->',
    'Inventory->'
)

Show-SourceEvidence -Path $ProjectileH -Patterns @('UPROPERTY','Damage','Speed','Collision')
Show-SourceEvidence -Path $ProjectileCpp -Patterns @('ApplyDamage','ApplyPointDamage','Damage','ProjectileMovement','Collision')

# Static classification from exact source text.
$WeaponHeaderText = Get-Content -Raw -LiteralPath $WeaponH
$WeaponCppText = Get-Content -Raw -LiteralPath $WeaponCpp
$CharacterText = Get-Content -Raw -LiteralPath $CharacterCpp
$ProjectileText = (Get-Content -Raw -LiteralPath $ProjectileH) + "`n" + (Get-Content -Raw -LiteralPath $ProjectileCpp)
$InventoryText = ""
if (Test-Path -LiteralPath $InventoryH -PathType Leaf) { $InventoryText += Get-Content -Raw -LiteralPath $InventoryH }
if (Test-Path -LiteralPath $InventoryCpp -PathType Leaf) { $InventoryText += "`n" + (Get-Content -Raw -LiteralPath $InventoryCpp) }

$SourceProjectileProperty = $WeaponHeaderText -match 'ProjectileClass'
$SourceProjectileAssignment = $WeaponCppText -match 'ProjectileClass\s*='
$SourceSpawnActor = $WeaponCppText -match 'SpawnActor'
$SourceDirectDamage = $WeaponCppText -match 'ApplyDamage|ApplyPointDamage'
$SourceLineTrace = $WeaponCppText -match 'LineTrace|SweepSingle'
$SourceAmmo = ($WeaponHeaderText + "`n" + $WeaponCppText) -match '\bAmmo\b|Magazine|Rounds|Clip'
$SourceReload = ($WeaponHeaderText + "`n" + $WeaponCppText) -match '\bReload\b'
$SourceCharacterCallsWeapon = $CharacterText -match 'Weapon\s*->\s*[A-Za-z0-9_]*Fire|Weapon\s*->\s*Fire|Weapon\s*->\s*TryFire'
$SourceInventoryLoadout = $InventoryText -match 'Loadout|DefaultWeapon|Equip|WeaponClass'
$SourceProjectileDamage = $ProjectileText -match 'ApplyDamage|ApplyPointDamage|TakeDamage'

Write-Host "SOURCE_PROJECTILE_PROPERTY_PRESENT=$SourceProjectileProperty"
Write-Host "SOURCE_PROJECTILE_DEFAULT_ASSIGNMENT_PRESENT=$SourceProjectileAssignment"
Write-Host "SOURCE_WEAPON_SPAWN_ACTOR_PATH_PRESENT=$SourceSpawnActor"
Write-Host "SOURCE_WEAPON_DIRECT_DAMAGE_PATH_PRESENT=$SourceDirectDamage"
Write-Host "SOURCE_WEAPON_LINE_TRACE_PATH_PRESENT=$SourceLineTrace"
Write-Host "SOURCE_WEAPON_AMMO_PATH_PRESENT=$SourceAmmo"
Write-Host "SOURCE_WEAPON_RELOAD_PATH_PRESENT=$SourceReload"
Write-Host "SOURCE_CHARACTER_CALLS_WEAPON_FIRE=$SourceCharacterCallsWeapon"
Write-Host "SOURCE_INVENTORY_LOADOUT_PATH_PRESENT=$SourceInventoryLoadout"
Write-Host "SOURCE_PROJECTILE_DAMAGE_PATH_PRESENT=$SourceProjectileDamage"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " UNREAL REFLECTION / CDO VALUES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$PyFile = Join-Path $EvidenceRoot "weapon_runtime_defaults_v2_$Stamp.py"
$StdOut = Join-Path $EvidenceRoot "weapon_runtime_defaults_v2_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "weapon_runtime_defaults_v2_$Stamp.stderr.log"

$Python = @'
import unreal

def fmt(v):
    try:
        if v is None:
            return "NONE"
        if isinstance(v, bool):
            return "True" if v else "False"
        if isinstance(v, (int, float, str)):
            return str(v)
        if hasattr(v, "get_path_name"):
            return v.get_path_name()
        return str(v)
    except Exception as e:
        return f"<ERR:{e}>"

def emit(name, value):
    print(f"{name}={fmt(value)}")

char_cls = unreal.load_class(None, "/Script/ArabiaStrikeWorldWar.ASCharacter")
weapon_cls = unreal.load_class(None, "/Script/ArabiaStrikeWorldWar.ASWeaponComponent")
inventory_cls = unreal.load_class(None, "/Script/ArabiaStrikeWorldWar.ASWeaponInventoryComponent")
projectile_cls = unreal.load_class(None, "/Script/ArabiaStrikeWorldWar.ASProjectile")

emit("ASWW_REFLECT_CHARACTER_CLASS", char_cls is not None)
emit("ASWW_REFLECT_WEAPON_CLASS", weapon_cls is not None)
emit("ASWW_REFLECT_INVENTORY_CLASS", inventory_cls is not None)
emit("ASWW_REFLECT_PROJECTILE_CLASS", projectile_cls is not None)

classes = [
    ("WEAPON", weapon_cls),
    ("INVENTORY", inventory_cls),
    ("PROJECTILE", projectile_cls),
]

for label, cls in classes:
    if not cls:
        continue

    cdo = unreal.get_default_object(cls)
    emit(f"ASWW_{label}_CDO_LOAD", cdo is not None)

    if not cdo:
        continue

    # Inspect all exposed names, but only weapon/combat-relevant non-callables.
    tokens = (
        "projectile","damage","ammo","magazine","clip","round","reload","fire",
        "rate","range","trace","muzzle","weapon","spread","burst","automatic",
        "cooldown","speed","radius","impact","loadout","equip"
    )

    seen = set()
    for name in sorted(dir(cdo)):
        if name.startswith("_"):
            continue
        low = name.lower()
        if not any(t in low for t in tokens):
            continue
        if name in seen:
            continue
        seen.add(name)
        try:
            value = getattr(cdo, name)
        except Exception:
            continue
        if callable(value):
            continue
        print(f"ASWW_{label}_REFLECT|PROP={name}|VALUE={fmt(value)}")

    # Probe common snake_case names explicitly.
    probes = [
        "projectile_class","damage","base_damage","ammo","current_ammo",
        "magazine_size","ammo_in_magazine","reserve_ammo","fire_rate",
        "fire_interval","weapon_range","range","muzzle_offset","spread",
        "reload_time","projectile_speed","explosion_radius","loadout",
        "default_weapon_class","weapon_class"
    ]

    for pname in probes:
        try:
            value = cdo.get_editor_property(pname)
            print(f"ASWW_{label}_PROBE|PROP={pname}|VALUE={fmt(value)}")
        except Exception:
            pass

# Inspect player CDO subobject instances, which can carry overrides distinct from
# the component class CDO.
if char_cls:
    char_cdo = unreal.get_default_object(char_cls)
    try:
        comps = char_cdo.get_components_by_class(unreal.ActorComponent)
    except Exception:
        comps = []

    for comp in comps:
        cname = comp.get_class().get_name()
        if "Weapon" in cname or "Inventory" in cname:
            print(f"ASWW_PLAYER_SUBOBJECT|CLASS={cname}|NAME={comp.get_name()}")
            for pname in [
                "projectile_class","damage","ammo","current_ammo","magazine_size",
                "ammo_in_magazine","reserve_ammo","fire_rate","fire_interval",
                "weapon_range","range","muzzle_offset","spread","loadout",
                "default_weapon_class","weapon_class"
            ]:
                try:
                    value = comp.get_editor_property(pname)
                    print(f"ASWW_PLAYER_SUBOBJECT_PROBE|CLASS={cname}|PROP={pname}|VALUE={fmt(value)}")
                except Exception:
                    pass

# Strict asset discovery: no tiny token like "ak" that can match "Lake".
registry = unreal.AssetRegistryHelpers.get_asset_registry()
assets = registry.get_all_assets()

strict_tokens = (
    "rifle","weapon","pistol","shotgun","carbine","firearm","machinegun",
    "machine_gun","assault_rifle","assaultrifle","smg","sniper","revolver",
    "grenade_launcher","rocket_launcher","gun_mesh","weapon_mesh",
    "m4a1","m16","ak47","ak_47","ak74","ak_74"
)

candidates = []
for a in assets:
    try:
        asset_name = str(a.asset_name)
        package = str(a.package_name)
        class_name = str(a.asset_class_path.asset_name)
    except Exception:
        continue

    if class_name not in ("StaticMesh","SkeletalMesh"):
        continue

    hay = (asset_name + " " + package).lower()
    if not any(t in hay for t in strict_tokens):
        continue

    # Exclude obvious editor/debug/material/water false positives.
    if any(x in hay for x in (
        "/editor","/debug","water","lake","material","function","icon","speaker",
        "tutorial","niagara","bake","break","makefloat","fake"
    )):
        continue

    score = 0
    if package.startswith("/Game/"):
        score += 100
    elif package.startswith("/Engine/"):
        score += 40
    else:
        score += 20

    if "rifle" in hay:
        score += 40
    if "assault" in hay:
        score += 35
    if "weapon" in hay:
        score += 25
    if "pistol" in hay:
        score += 20
    if class_name == "SkeletalMesh":
        score += 10

    candidates.append((score, package, asset_name, class_name))

candidates.sort(key=lambda x: (-x[0], x[1].lower(), x[2].lower()))
emit("ASWW_STRICT_MOUNTED_WEAPON_MESH_CANDIDATE_COUNT", len(candidates))

for score, package, asset_name, class_name in candidates[:100]:
    print(
        f"ASWW_STRICT_WEAPON_MESH_CANDIDATE|SCORE={score}|CLASS={class_name}|"
        f"PACKAGE={package}|NAME={asset_name}"
    )

print("ASWW_WEAPON_RUNTIME_DEFAULT_AUDIT_V2_PYTHON_DONE=TRUE")
'@

[IO.File]::WriteAllText($PyFile, $Python, [Text.UTF8Encoding]::new($false))
$PyForward = $PyFile.Replace('\','/')

$Args = @(
    $ProjectFile
    "-unattended"
    "-nop4"
    "-nosplash"
    "-NullRHI"
    "-stdout"
    "-FullStdOutLogOutput"
    "-ExecutePythonScript=$PyForward"
)

& $EditorCmd @Args 1> $StdOut 2> $StdErr
$Exit = $LASTEXITCODE
Write-Host "UNREAL_EDITOR_CMD_EXIT=$Exit"

$Combined = ""
if (Test-Path -LiteralPath $StdOut) {
    $Combined += Get-Content -Raw -LiteralPath $StdOut
    Select-String -LiteralPath $StdOut `
        -Pattern "ASWW_REFLECT_|ASWW_WEAPON_CDO|ASWW_INVENTORY_CDO|ASWW_PROJECTILE_CDO|ASWW_WEAPON_REFLECT|ASWW_WEAPON_PROBE|ASWW_INVENTORY_REFLECT|ASWW_INVENTORY_PROBE|ASWW_PROJECTILE_REFLECT|ASWW_PROJECTILE_PROBE|ASWW_PLAYER_SUBOBJECT|ASWW_PLAYER_SUBOBJECT_PROBE|ASWW_STRICT_" |
        ForEach-Object { Write-Host $_.Line }
}
if (Test-Path -LiteralPath $StdErr) {
    $Combined += "`n" + (Get-Content -Raw -LiteralPath $StdErr)
}

$PythonError = $Combined -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$Fatal = $Combined -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "FATAL_ERROR_SEEN=$Fatal"

if ($Exit -ne 0 -or $PythonError -or $Fatal) {
    Stop-Gate "UNREAL_REFLECTION_AUDIT_FAILED" $(if ($Exit -gt 0) { $Exit } else { 30 })
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " STRICT FILESYSTEM WEAPON-ASSET DISCOVERY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Roots = @(
    (Join-Path $UERoot "Templates"),
    (Join-Path $UERoot "TemplateResources"),
    (Join-Path $UERoot "FeaturePacks"),
    (Join-Path $UERoot "Engine\Content"),
    (Join-Path $UERoot "Engine\Plugins")
) | Where-Object { Test-Path -LiteralPath $_ -PathType Container }

$StrictRegex = '(?i)(^|[_\-\s])(rifle|pistol|shotgun|carbine|firearm|machinegun|machine_gun|assault_rifle|assaultrifle|smg|sniper|revolver|weapon_mesh|gun_mesh|m4a1|m16|ak47|ak_47|ak74|ak_74)([_\-\s]|$)'

$Loose = @()
foreach ($Root in $Roots) {
    $Loose += Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "*.uasset" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.BaseName -match $StrictRegex -or
            $_.DirectoryName -match '(?i)\\(Weapons?|Guns?|Firearms?|Rifles?|Pistols?|Shotguns?|SMG|Snipers?)\\'
        }
}

$Loose = @(
    $Loose |
    Where-Object {
        $_.FullName -notmatch '(?i)\\Editor|\\Debug|\\Materials?\\|\\Functions?\\|\\Icons?\\|\\Water\\|Lake'
    } |
    Sort-Object FullName -Unique
)

Write-Host "STRICT_LOOSE_WEAPON_UASSET_CANDIDATE_COUNT=$($Loose.Count)"
foreach ($Item in $Loose | Select-Object -First 150) {
    Write-Host "STRICT_LOOSE_WEAPON_UASSET=$($Item.FullName)"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Pull simple evidence from combined output.
$MountedCount = -1
$M = [regex]::Match($Combined, 'ASWW_STRICT_MOUNTED_WEAPON_MESH_CANDIDATE_COUNT=(\d+)')
if ($M.Success) { $MountedCount = [int]$M.Groups[1].Value }

$ProjectileRuntimeSet = $Combined -match 'ASWW_(WEAPON|PLAYER_SUBOBJECT)_PROBE\|.*PROP=projectile_class\|VALUE=(?!NONE|null|None)'
$AnyWeaponRuntimeDefaults = $Combined -match 'ASWW_WEAPON_(REFLECT|PROBE)\|'
$AnyPlayerWeaponOverrides = $Combined -match 'ASWW_PLAYER_SUBOBJECT_PROBE\|'

Write-Host "RUNTIME_PROJECTILE_CLASS_NONEMPTY_SEEN=$ProjectileRuntimeSet"
Write-Host "RUNTIME_WEAPON_DEFAULTS_EXPOSED=$AnyWeaponRuntimeDefaults"
Write-Host "PLAYER_WEAPON_SUBOBJECT_OVERRIDES_EXPOSED=$AnyPlayerWeaponOverrides"
Write-Host "STRICT_MOUNTED_WEAPON_MESH_CANDIDATE_COUNT=$MountedCount"
Write-Host "STRICT_LOOSE_WEAPON_UASSET_CANDIDATE_COUNT=$($Loose.Count)"

if ($MountedCount -gt 0 -or $Loose.Count -gt 0) {
    Write-Host "REAL_WEAPON_ASSET_SOURCE=FOUND_CANDIDATES_REVIEW_OUTPUT" -ForegroundColor Green
} else {
    Write-Host "REAL_WEAPON_ASSET_SOURCE=NONE_FOUND_IN_CURRENT_UE_INSTALL" -ForegroundColor Yellow
}

if ($ProjectileRuntimeSet) {
    Write-Host "COMBAT_LOGIC_DEFAULT_CLASSIFICATION=PROJECTILE_CLASS_NONEMPTY" -ForegroundColor Green
} elseif ($SourceProjectileProperty -and -not $SourceProjectileAssignment) {
    Write-Host "COMBAT_LOGIC_DEFAULT_CLASSIFICATION=PROJECTILE_PROPERTY_EXISTS_BUT_NO_CPP_DEFAULT_ASSIGNMENT" -ForegroundColor Yellow
} else {
    Write-Host "COMBAT_LOGIC_DEFAULT_CLASSIFICATION=REVIEW_SOURCE_AND_REFLECTION_EVIDENCE" -ForegroundColor Yellow
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"

Write-Host ""
Write-Host "WEAPON_RUNTIME_DEFAULT_AUDIT_V2=PASS" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "NEXT_GATE=FIX_ONLY_PROVEN_WEAPON_RUNTIME_DEFAULT_AND_VISUAL_ASSET_GAPS" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
