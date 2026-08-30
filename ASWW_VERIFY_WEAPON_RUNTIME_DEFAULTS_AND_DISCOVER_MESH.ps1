[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\WeaponRuntimeDefaults"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "WEAPON_RUNTIME_DEFAULT_AUDIT=STOPPED" -ForegroundColor Red
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

if (-not (Test-Path -LiteralPath $ProjectFile -PathType Leaf)) {
    Stop-Gate "UPROJECT_NOT_FOUND" 11
}
if (-not (Test-Path -LiteralPath $EditorCmd -PathType Leaf)) {
    Stop-Gate "UNREALEDITOR_CMD_NOT_FOUND" 12
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$PyFile = Join-Path $EvidenceRoot "weapon_runtime_defaults_$Stamp.py"
$StdOut = Join-Path $EvidenceRoot "weapon_runtime_defaults_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "weapon_runtime_defaults_$Stamp.stderr.log"

$Python = @'
import unreal
import re

MAP = "/Game/Maps/Jeddah_RedSea_Assault"

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

world = unreal.EditorLoadingAndSavingUtils.load_map(MAP)
emit("ASWW_WEAPON_AUDIT_MAP_LOAD", world is not None)
if not world:
    raise RuntimeError("Could not load Jeddah")

player_cls = unreal.load_class(None, "/Script/ArabiaStrikeWorldWar.ASCharacter")
emit("ASWW_PLAYER_CLASS_LOAD", player_cls is not None)
if not player_cls:
    raise RuntimeError("ASCharacter class unavailable")

cdo = unreal.get_default_object(player_cls)
emit("ASWW_PLAYER_CDO_LOAD", cdo is not None)

try:
    comps = cdo.get_components_by_class(unreal.ActorComponent)
except Exception:
    comps = []

weapon = None
inventory = None
health = None

for c in comps:
    clsname = c.get_class().get_name()
    print(f"ASWW_PLAYER_COMPONENT|CLASS={clsname}|NAME={c.get_name()}")
    low = clsname.lower()
    if "weapon" in low and "inventory" not in low and weapon is None:
        weapon = c
    if "inventory" in low and inventory is None:
        inventory = c
    if "health" in low and health is None:
        health = c

emit("ASWW_WEAPON_COMPONENT_FOUND", weapon is not None)
emit("ASWW_INVENTORY_COMPONENT_FOUND", inventory is not None)
emit("ASWW_HEALTH_COMPONENT_FOUND", health is not None)

def dump_interesting(obj, prefix):
    if not obj:
        return 0
    tokens = (
        "projectile","damage","ammo","magazine","clip","reload","fire","rate",
        "range","trace","muzzle","weapon","spread","burst","automatic","cooldown"
    )
    seen = set()
    count = 0

    for name in sorted(dir(obj)):
        if name.startswith("_"):
            continue
        low = name.lower()
        if not any(t in low for t in tokens):
            continue
        if name in seen:
            continue
        seen.add(name)

        try:
            value = getattr(obj, name)
        except Exception:
            continue

        # Skip callables; we want actual runtime defaults/properties.
        if callable(value):
            continue

        # Avoid noisy giant arrays unless weapon-related and short.
        try:
            text = fmt(value)
        except Exception:
            continue

        print(f"{prefix}|PROP={name}|VALUE={text}")
        count += 1
        if count >= 120:
            break

    return count

weapon_prop_count = dump_interesting(weapon, "ASWW_WEAPON_DEFAULT")
inventory_prop_count = dump_interesting(inventory, "ASWW_INVENTORY_DEFAULT")

emit("ASWW_WEAPON_INTERESTING_PROPERTY_COUNT", weapon_prop_count)
emit("ASWW_INVENTORY_INTERESTING_PROPERTY_COUNT", inventory_prop_count)

# Probe likely property names explicitly because some UPROPERTY names are exposed
# even when they do not show up cleanly through dir().
probe_names = [
    "projectile_class","ProjectileClass",
    "damage","Damage","base_damage","BaseDamage",
    "magazine_size","MagazineSize",
    "ammo","Ammo","current_ammo","CurrentAmmo",
    "ammo_in_magazine","AmmoInMagazine",
    "reserve_ammo","ReserveAmmo",
    "fire_rate","FireRate","fire_interval","FireInterval",
    "weapon_range","WeaponRange","range","Range",
    "muzzle_offset","MuzzleOffset",
    "spread","Spread",
]
for obj, label in ((weapon, "WEAPON"), (inventory, "INVENTORY")):
    if not obj:
        continue
    for pname in probe_names:
        try:
            v = obj.get_editor_property(pname)
            print(f"ASWW_{label}_PROBE|PROP={pname}|VALUE={fmt(v)}")
        except Exception:
            pass

# Discover mounted weapon-like meshes. Prefer project assets, but report engine/plugin
# candidates too so the next step can deliberately copy a chosen mesh into /Game.
registry = unreal.AssetRegistryHelpers.get_asset_registry()
all_assets = registry.get_all_assets()

tokens = (
    "rifle","weapon","gun","pistol","smg","shotgun","carbine","m4","ak",
    "assault","firearm","blaster","launcher"
)

candidates = []
for a in all_assets:
    try:
        asset_name = str(a.asset_name)
        package = str(a.package_name)
        class_name = str(a.asset_class_path.asset_name)
    except Exception:
        continue

    if class_name not in ("StaticMesh","SkeletalMesh"):
        continue

    hay = (asset_name + " " + package).lower()
    if not any(t in hay for t in tokens):
        continue

    score = 0
    if package.startswith("/Game/"):
        score += 100
    if package.startswith("/Engine/"):
        score += 40
    if "rifle" in hay:
        score += 30
    if "weapon" in hay:
        score += 20
    if "gun" in hay:
        score += 15
    if "pistol" in hay:
        score += 10
    if "skeletalmesh" in class_name.lower():
        score += 5

    candidates.append((score, package, asset_name, class_name))

candidates.sort(key=lambda x: (-x[0], x[1].lower(), x[2].lower()))
emit("ASWW_MOUNTED_WEAPON_MESH_CANDIDATE_COUNT", len(candidates))

for score, package, asset_name, class_name in candidates[:80]:
    print(
        f"ASWW_WEAPON_MESH_CANDIDATE|SCORE={score}|CLASS={class_name}|"
        f"PACKAGE={package}|NAME={asset_name}"
    )

# Inspect Jeddah enemy runtime classes/components again, with exact class names.
sub = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
actors = sub.get_all_level_actors()
enemy_like = []

for a in actors:
    if not a:
        continue
    try:
        label = a.get_actor_label()
    except Exception:
        label = a.get_name()
    clsname = a.get_class().get_name()
    hay = f"{label} {clsname}".lower()
    if any(t in hay for t in ("enemy","soldier","hostile","prototype_enemy","prototype enemy")):
        enemy_like.append(a)

emit("ASWW_LOADED_ENEMY_RUNTIME_COUNT", len(enemy_like))
for a in enemy_like[:20]:
    try:
        label = a.get_actor_label()
    except Exception:
        label = a.get_name()
    clsname = a.get_class().get_name()
    loc = a.get_actor_location()
    controller = None
    try:
        controller = a.get_controller()
    except Exception:
        pass

    comps2 = []
    try:
        comps2 = a.get_components_by_class(unreal.ActorComponent)
    except Exception:
        pass

    comp_names = [c.get_class().get_name() for c in comps2]
    print(
        f"ASWW_ENEMY_RUNTIME_DETAIL|LABEL={label}|CLASS={clsname}|"
        f"LOC={loc.x:.1f},{loc.y:.1f},{loc.z:.1f}|"
        f"CONTROLLER={controller.get_class().get_name() if controller else 'NONE'}|"
        f"COMPONENTS={','.join(comp_names)}"
    )

print("ASWW_WEAPON_RUNTIME_DEFAULT_AUDIT_DONE=TRUE")
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

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " UNREAL RUNTIME DEFAULTS / MOUNTED ASSETS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "UNREAL_EDITOR_CMD_EXIT=$Exit"

$Combined = ""
if (Test-Path -LiteralPath $StdOut) {
    $Combined += Get-Content -Raw -LiteralPath $StdOut
    Select-String -LiteralPath $StdOut `
        -Pattern "ASWW_WEAPON_|ASWW_INVENTORY_|ASWW_PLAYER_|ASWW_MOUNTED_|ASWW_LOADED_ENEMY_|ASWW_ENEMY_RUNTIME_DETAIL" |
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
    Stop-Gate "UNREAL_RUNTIME_DEFAULT_AUDIT_FAILED" $(if ($Exit -gt 0) { $Exit } else { 30 })
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " LOOSE TEMPLATE / ENGINE WEAPON-ASSET DISCOVERY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Roots = @(
    (Join-Path $UERoot "Templates"),
    (Join-Path $UERoot "TemplateResources"),
    (Join-Path $UERoot "Engine\Content"),
    (Join-Path $UERoot "Engine\Plugins")
) | Where-Object { Test-Path -LiteralPath $_ -PathType Container }

$Loose = @()
foreach ($Root in $Roots) {
    $Loose += Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "*.uasset" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.BaseName -match '(?i)(rifle|weapon|gun|pistol|smg|shotgun|carbine|m4|ak|assault|firearm|launcher)'
        } |
        Select-Object -First 250
}

$Loose = @($Loose | Sort-Object FullName -Unique)
Write-Host "LOOSE_WEAPON_UASSET_CANDIDATE_COUNT=$($Loose.Count)"

foreach ($Item in $Loose | Select-Object -First 100) {
    Write-Host "LOOSE_WEAPON_UASSET=$($Item.FullName)"
}

# Source-code evidence around FireOnce and weapon constructor/defaults.
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " EXACT SOURCE EVIDENCE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$SourceFiles = @(
    (Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"),
    (Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Combat\ASWeaponComponent.h"),
    (Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Combat\ASWeaponComponent.cpp"),
    (Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Combat\ASProjectile.h"),
    (Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Combat\ASProjectile.cpp")
)

foreach ($Source in $SourceFiles) {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { continue }

    Select-String -LiteralPath $Source `
        -Pattern "FireOnce|FirePressed|ProjectileClass|SpawnActor|ApplyDamage|ApplyPointDamage|Damage|Ammo|Reload|Muzzle|Trace" `
        -CaseSensitive:$false `
        -Context 2,5 |
        Select-Object -First 80 |
        ForEach-Object {
            Write-Host ("SOURCE={0} LINE={1} TEXT={2}" -f (Split-Path -Leaf $_.Path), $_.LineNumber, $_.Line.Trim())
        }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " GIT SAFETY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"

Write-Host ""
Write-Host "WEAPON_RUNTIME_DEFAULT_AUDIT=PASS" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "NEXT_GATE=CHOOSE_REAL_WEAPON_ASSET_AND_FIX_ONLY_VERIFIED_RUNTIME_DEFAULTS" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
