[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\CombatRuntimePinpoint"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "COMBAT_RUNTIME_PINPOINT=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Read-Text([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return Get-Content -Raw -LiteralPath $Path
    }
    return ""
}

function Bool-Line([string]$Name, [bool]$Value) {
    Write-Host "$Name=$Value"
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

$CharacterCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"
$WeaponCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Combat\ASWeaponComponent.cpp"
$WeaponH = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Combat\ASWeaponComponent.h"
$InventoryCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Combat\ASWeaponInventoryComponent.cpp"
$InventoryH = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Combat\ASWeaponInventoryComponent.h"
$ProjectileCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Combat\ASProjectile.cpp"
$ProjectileH = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Combat\ASProjectile.h"
$InputIni = Join-Path $ProjectRoot "Config\DefaultInput.ini"

foreach ($Required in @($CharacterCpp,$WeaponCpp,$WeaponH,$ProjectileCpp,$ProjectileH,$InputIni)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_SOURCE_$Required" 13
    }
}

$CharacterText = Read-Text $CharacterCpp
$WeaponText = (Read-Text $WeaponH) + "`n" + (Read-Text $WeaponCpp)
$InventoryText = (Read-Text $InventoryH) + "`n" + (Read-Text $InventoryCpp)
$ProjectileText = (Read-Text $ProjectileH) + "`n" + (Read-Text $ProjectileCpp)
$InputText = Read-Text $InputIni

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SOURCE RUNTIME PREREQUISITES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$FireInput = $InputText -match 'ActionName="Fire"'
$FireBinding = $CharacterText -match 'BindAction\("Fire"'
$FireOnce = $CharacterText -match 'void\s+AASCharacter::FireOnce\s*\('
$CharacterCallsWeapon = $CharacterText -match 'Weapon\s*->\s*[A-Za-z0-9_]*Fire|Weapon\s*->\s*Fire|Weapon\s*->\s*TryFire'
$CharacterCreatesWeapon = $CharacterText -match 'CreateDefaultSubobject<UASWeaponComponent>'
$CharacterCreatesInventory = $CharacterText -match 'CreateDefaultSubobject<UASWeaponInventoryComponent>'
$WeaponHasProjectileClass = $WeaponText -match 'ProjectileClass|TSubclassOf<\s*AASProjectile'
$WeaponSpawnsActor = $WeaponText -match 'SpawnActor|SpawnActorDeferred'
$WeaponHasTrace = $WeaponText -match 'LineTrace|SweepSingle|TraceChannel'
$WeaponAppliesDamage = $WeaponText -match 'ApplyDamage|ApplyPointDamage|TakeDamage'
$WeaponHasAmmo = $WeaponText -match 'Ammo|Magazine|Clip|Rounds'
$WeaponHasReload = $WeaponText -match 'Reload'
$ProjectileAppliesDamage = $ProjectileText -match 'ApplyDamage|ApplyPointDamage|TakeDamage|Damage'
$ProjectileHasCollision = $ProjectileText -match 'Collision|SphereComponent|BoxComponent|CapsuleComponent'
$InventoryHasLoadout = $InventoryText -match 'Loadout|Equip|WeaponClass|AddWeapon|DefaultWeapon'
$VisibleWeaponMeshSource = $CharacterText -match 'WeaponMesh|SkeletalMeshComponent.*Weapon|StaticMeshComponent.*Weapon' -or
                           $WeaponText -match 'WeaponMesh|SkeletalMeshComponent|StaticMeshComponent'

Bool-Line "FIRE_INPUT_CONFIGURED" $FireInput
Bool-Line "FIRE_BINDING_PRESENT" $FireBinding
Bool-Line "FIREONCE_FUNCTION_PRESENT" $FireOnce
Bool-Line "CHARACTER_CALLS_WEAPON_FIRE" $CharacterCallsWeapon
Bool-Line "WEAPON_COMPONENT_CREATED" $CharacterCreatesWeapon
Bool-Line "INVENTORY_COMPONENT_CREATED" $CharacterCreatesInventory
Bool-Line "WEAPON_PROJECTILE_CLASS_PATH_SEEN" $WeaponHasProjectileClass
Bool-Line "WEAPON_SPAWN_ACTOR_PATH_SEEN" $WeaponSpawnsActor
Bool-Line "WEAPON_TRACE_PATH_SEEN" $WeaponHasTrace
Bool-Line "WEAPON_DIRECT_DAMAGE_PATH_SEEN" $WeaponAppliesDamage
Bool-Line "WEAPON_AMMO_PATH_SEEN" $WeaponHasAmmo
Bool-Line "WEAPON_RELOAD_PATH_SEEN" $WeaponHasReload
Bool-Line "PROJECTILE_DAMAGE_PATH_SEEN" $ProjectileAppliesDamage
Bool-Line "PROJECTILE_COLLISION_PATH_SEEN" $ProjectileHasCollision
Bool-Line "INVENTORY_LOADOUT_PATH_SEEN" $InventoryHasLoadout
Bool-Line "VISIBLE_WEAPON_MESH_SOURCE_SEEN" $VisibleWeaponMeshSource

Write-Host ""
Write-Host "=== FIRE / WEAPON SOURCE HINTS ===" -ForegroundColor Yellow
foreach ($Path in @($CharacterCpp,$WeaponH,$WeaponCpp,$InventoryH,$InventoryCpp,$ProjectileH,$ProjectileCpp)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { continue }
    Select-String -LiteralPath $Path `
        -Pattern 'FireOnce|FirePressed|FireReleased|ProjectileClass|SpawnActor|ApplyDamage|ApplyPointDamage|LineTrace|WeaponMesh|Equip|Loadout|Ammo|Reload' `
        -CaseSensitive:$false |
        Select-Object -First 90 |
        ForEach-Object {
            Write-Host ("{0}:{1}: {2}" -f (Split-Path -Leaf $_.Path), $_.LineNumber, $_.Line.Trim())
        }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " JEDDAH RUNTIME-CONTENT INSPECTION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$PyFile = Join-Path $EvidenceRoot "pinpoint_combat_$Stamp.py"
$StdOut = Join-Path $EvidenceRoot "pinpoint_combat_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "pinpoint_combat_$Stamp.stderr.log"

$Python = @'
import unreal
import math

MAP = "/Game/Maps/Jeddah_RedSea_Assault"

def safe_label(actor):
    try:
        return actor.get_actor_label()
    except Exception:
        return actor.get_name()

def safe_loc(actor):
    try:
        return actor.get_actor_location()
    except Exception:
        return unreal.Vector(0,0,0)

def dist(a,b):
    try:
        return math.sqrt((a.x-b.x)**2 + (a.y-b.y)**2 + (a.z-b.z)**2)
    except Exception:
        return -1.0

world = unreal.EditorLoadingAndSavingUtils.load_map(MAP)
print(f"ASWW_COMBAT_MAP_LOAD={world is not None}")

if not world:
    raise RuntimeError("Could not load Jeddah map")

sub = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

# First inspect actors already loaded in the partition.
loaded = sub.get_all_level_actors()
print(f"ASWW_COMBAT_LOADED_ACTOR_COUNT={len(loaded)}")

def classify_actor(actor):
    label = safe_label(actor)
    cls = actor.get_class().get_name()
    text = f"{label} {cls}".lower()

    is_player_start = ("playerstart" in text) or ("player_start" in text)
    is_enemy = any(k in text for k in (
        "enemy", "soldier", "hostile", "prototype_enemy", "prototype enemy", "ai_character", "aicharacter"
    ))
    is_weaponish = any(k in text for k in ("weapon", "rifle", "gun", "projectile"))
    return label, cls, is_player_start, is_enemy, is_weaponish

player_starts = []
loaded_enemies = []
weaponish = []

for actor in loaded:
    if not actor:
        continue
    label, cls, ps, enemy, weap = classify_actor(actor)
    loc = safe_loc(actor)
    if ps:
        player_starts.append((actor,label,cls,loc))
    if enemy:
        loaded_enemies.append((actor,label,cls,loc))
    if weap:
        weaponish.append((actor,label,cls,loc))

print(f"ASWW_COMBAT_LOADED_PLAYERSTART_COUNT={len(player_starts)}")
print(f"ASWW_COMBAT_LOADED_ENEMY_COUNT={len(loaded_enemies)}")
print(f"ASWW_COMBAT_LOADED_WEAPONISH_ACTOR_COUNT={len(weaponish)}")

for _,label,cls,loc in player_starts[:20]:
    print(f"ASWW_PLAYERSTART|LABEL={label}|CLASS={cls}|LOC={loc.x:.1f},{loc.y:.1f},{loc.z:.1f}")

for _,label,cls,loc in loaded_enemies[:30]:
    print(f"ASWW_LOADED_ENEMY|LABEL={label}|CLASS={cls}|LOC={loc.x:.1f},{loc.y:.1f},{loc.z:.1f}")

# World Partition descriptors: this catches actors that exist but are not currently streamed/loaded.
descs = []
try:
    descs = unreal.WorldPartitionBlueprintLibrary.get_actor_descs()
except Exception as exc:
    print(f"ASWW_DESC_ENUM_ERROR={exc}")

print(f"ASWW_COMBAT_DESCRIPTOR_COUNT={len(descs)}")

enemy_descs = []
player_descs = []

for d in descs:
    label = ""
    cls = ""
    guid = None
    for attr in ("actor_label","label"):
        try:
            v = getattr(d, attr)
            if v:
                label = str(v)
                break
        except Exception:
            pass
    try:
        cls = str(d.actor_class)
    except Exception:
        try:
            cls = str(d.native_class)
        except Exception:
            cls = ""
    try:
        guid = d.guid
    except Exception:
        guid = None

    text = f"{label} {cls}".lower()

    if any(k in text for k in (
        "enemy", "soldier", "hostile", "prototype_enemy", "prototype enemy", "ai_character", "aicharacter"
    )):
        enemy_descs.append((d,label,cls,guid))
    if ("playerstart" in text) or ("player_start" in text):
        player_descs.append((d,label,cls,guid))

print(f"ASWW_COMBAT_ENEMY_DESCRIPTOR_COUNT={len(enemy_descs)}")
print(f"ASWW_COMBAT_PLAYERSTART_DESCRIPTOR_COUNT={len(player_descs)}")

for _,label,cls,guid in enemy_descs[:30]:
    print(f"ASWW_ENEMY_DESC|LABEL={label}|CLASS={cls}|GUID={guid}")

# Best-effort load descriptor candidates, then inspect live actor positions.
candidate_guids = [x[3] for x in enemy_descs + player_descs if x[3] is not None]
if candidate_guids:
    try:
        unreal.WorldPartitionBlueprintLibrary.load_actors(candidate_guids)
        print("ASWW_COMBAT_DESCRIPTOR_LOAD=PASS")
    except Exception as exc:
        print(f"ASWW_COMBAT_DESCRIPTOR_LOAD=FAIL:{exc}")

loaded2 = sub.get_all_level_actors()
player_starts2 = []
enemies2 = []

for actor in loaded2:
    if not actor:
        continue
    label, cls, ps, enemy, _ = classify_actor(actor)
    loc = safe_loc(actor)
    if ps:
        player_starts2.append((actor,label,cls,loc))
    if enemy:
        enemies2.append((actor,label,cls,loc))

print(f"ASWW_COMBAT_AFTER_DESC_LOAD_PLAYERSTART_COUNT={len(player_starts2)}")
print(f"ASWW_COMBAT_AFTER_DESC_LOAD_ENEMY_COUNT={len(enemies2)}")

origin = player_starts2[0][3] if player_starts2 else None
min_dist = None

for actor,label,cls,loc in enemies2[:30]:
    d = dist(origin, loc) if origin else -1.0
    if d >= 0 and (min_dist is None or d < min_dist):
        min_dist = d

    controller = None
    try:
        controller = actor.get_controller()
    except Exception:
        pass

    health_comp = None
    weapon_comp = None
    try:
        comps = actor.get_components_by_class(unreal.ActorComponent)
    except Exception:
        comps = []

    for c in comps:
        cname = c.get_class().get_name()
        if "Health" in cname:
            health_comp = cname
        if "Weapon" in cname:
            weapon_comp = cname

    print(
        f"ASWW_ENEMY_RUNTIME|LABEL={label}|CLASS={cls}|"
        f"LOC={loc.x:.1f},{loc.y:.1f},{loc.z:.1f}|DIST_TO_START={d:.1f}|"
        f"CONTROLLER={controller.get_class().get_name() if controller else 'NONE'}|"
        f"HEALTH_COMP={health_comp or 'NONE'}|WEAPON_COMP={weapon_comp or 'NONE'}"
    )

print(f"ASWW_COMBAT_MIN_ENEMY_DISTANCE_TO_PLAYERSTART={min_dist if min_dist is not None else -1}")

# Inspect the native player CDO and component classes.
player_cls = unreal.load_class(None, "/Script/ArabiaStrikeWorldWar.ASCharacter")
print(f"ASWW_PLAYER_CLASS_LOAD={player_cls is not None}")

if player_cls:
    cdo = unreal.get_default_object(player_cls)
    try:
        comps = cdo.get_components_by_class(unreal.ActorComponent)
    except Exception:
        comps = []

    print(f"ASWW_PLAYER_CDO_COMPONENT_COUNT={len(comps)}")
    for c in comps:
        cname = c.get_class().get_name()
        if any(k in cname.lower() for k in ("weapon","inventory","health")):
            print(f"ASWW_PLAYER_CDO_COMBAT_COMPONENT={cname}|NAME={c.get_name()}")

print("ASWW_COMBAT_READONLY_INSPECTION_DONE=TRUE")
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

$Text = ""
if (Test-Path -LiteralPath $StdOut) {
    $Text += Get-Content -Raw -LiteralPath $StdOut
    Select-String -LiteralPath $StdOut -Pattern "ASWW_COMBAT_|ASWW_PLAYERSTART|ASWW_LOADED_ENEMY|ASWW_ENEMY_DESC|ASWW_ENEMY_RUNTIME|ASWW_PLAYER_CLASS|ASWW_PLAYER_CDO" |
        ForEach-Object { Write-Host $_.Line }
}
if (Test-Path -LiteralPath $StdErr) {
    $Text += "`n" + (Get-Content -Raw -LiteralPath $StdErr)
}

$PythonError = $Text -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "FATAL_ERROR_SEEN=$Fatal"

if ($Exit -ne 0 -or $PythonError -or $Fatal) {
    Stop-Gate "UNREAL_COMBAT_INSPECTION_FAILED" $(if ($Exit -gt 0) { $Exit } else { 30 })
}

function Read-IntFromLog([string]$Name, [int]$Default = -1) {
    $M = [regex]::Match($Text, [regex]::Escape($Name) + "=(-?\d+)")
    if ($M.Success) { return [int]$M.Groups[1].Value }
    return $Default
}

function Read-DoubleFromLog([string]$Name, [double]$Default = -1) {
    $M = [regex]::Match($Text, [regex]::Escape($Name) + "=(-?\d+(?:\.\d+)?)")
    if ($M.Success) { return [double]$M.Groups[1].Value }
    return $Default
}

$EnemyDescCount = Read-IntFromLog "ASWW_COMBAT_ENEMY_DESCRIPTOR_COUNT"
$LoadedEnemyCount = Read-IntFromLog "ASWW_COMBAT_LOADED_ENEMY_COUNT"
$AfterLoadEnemyCount = Read-IntFromLog "ASWW_COMBAT_AFTER_DESC_LOAD_ENEMY_COUNT"
$PlayerStartCount = Read-IntFromLog "ASWW_COMBAT_AFTER_DESC_LOAD_PLAYERSTART_COUNT"
$MinEnemyDistance = Read-DoubleFromLog "ASWW_COMBAT_MIN_ENEMY_DISTANCE_TO_PLAYERSTART"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COMBAT RUNTIME BLOCKER CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "JEDDAH_ENEMY_DESCRIPTOR_COUNT=$EnemyDescCount"
Write-Host "JEDDAH_ENEMY_LOADED_INITIAL_COUNT=$LoadedEnemyCount"
Write-Host "JEDDAH_ENEMY_AFTER_DESCRIPTOR_LOAD_COUNT=$AfterLoadEnemyCount"
Write-Host "JEDDAH_PLAYERSTART_COUNT=$PlayerStartCount"
Write-Host "MIN_ENEMY_DISTANCE_TO_PLAYERSTART=$MinEnemyDistance"

$Blockers = @()

if (-not $FireInput -or -not $FireBinding -or -not $FireOnce) {
    $Blockers += "PLAYER_FIRE_INPUT_PATH_INCOMPLETE"
}

if (-not $CharacterCreatesWeapon) {
    $Blockers += "PLAYER_WEAPON_COMPONENT_NOT_CREATED"
}

if (-not $WeaponHasProjectileClass -and -not $WeaponHasTrace -and -not $WeaponAppliesDamage) {
    $Blockers += "WEAPON_HAS_NO_PROJECTILE_TRACE_OR_DAMAGE_PATH"
}

if (-not $VisibleWeaponMeshSource) {
    $Blockers += "NO_VISIBLE_WEAPON_MESH_PATH_IN_PLAYER_OR_WEAPON_COMPONENT"
}

if ($EnemyDescCount -eq 0) {
    $Blockers += "JEDDAH_HAS_NO_ENEMY_DESCRIPTORS"
}
elseif ($AfterLoadEnemyCount -eq 0) {
    $Blockers += "ENEMIES_EXIST_AS_DESCRIPTORS_BUT_COULD_NOT_BE_LOADED_FOR_INSPECTION"
}

if ($MinEnemyDistance -gt 12000) {
    $Blockers += "ENEMIES_ARE_FAR_FROM_PLAYER_START"
}

if ($Blockers.Count -eq 0) {
    Write-Host "COMBAT_RUNTIME_BLOCKERS=NOT_PINPOINTED_BY_STATIC_MAP_AUDIT" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=ADD_TEMPORARY_COMBAT_PROOF_ARENA_AND_TARGETED_RUNTIME_LOGGING" -ForegroundColor Yellow
}
else {
    foreach ($B in $Blockers) {
        Write-Host "COMBAT_RUNTIME_BLOCKER=$B" -ForegroundColor Yellow
    }
    Write-Host "NEXT_GATE=FIX_ONLY_CONFIRMED_COMBAT_RUNTIME_BLOCKERS_THEN_REPACKAGE" -ForegroundColor Green
}

Write-Host ""
Write-Host "COMBAT_RUNTIME_PINPOINT=PASS" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
