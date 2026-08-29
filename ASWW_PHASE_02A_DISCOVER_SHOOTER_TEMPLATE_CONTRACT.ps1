[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\Phase02A_ShooterContract"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_02A_SHOOTER_CONTRACT=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_GAMEPLAY_SOURCE_WAS_MODIFIED" -ForegroundColor Green
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
$TemplateShooterRoot = Join-Path $UERoot "Templates\TemplateResources\Standard\Variant_Shooter\Content"
$ProjectShooterRoot = Join-Path $ProjectRoot "Content\Variant_Shooter"

foreach ($Required in @($ProjectFile,$EditorCmd,$TemplateShooterRoot)) {
    if (-not (Test-Path -LiteralPath $Required)) {
        Stop-Gate "MISSING_REQUIRED_PATH_$Required" 11
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " STAGE VARIANT_SHOOTER CONTENT SAFELY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $ProjectShooterRoot | Out-Null

$Created = 0
$Identical = 0
$DifferentCollision = 0
$CollisionList = New-Object System.Collections.Generic.List[string]

$SourceFiles = @(Get-ChildItem -LiteralPath $TemplateShooterRoot -Recurse -File -ErrorAction Stop)
Write-Host "SOURCE_FILE_COUNT=$($SourceFiles.Count)"

foreach ($Source in $SourceFiles) {
    $Rel = $Source.FullName.Substring($TemplateShooterRoot.Length).TrimStart('\','/')
    $Dest = Join-Path $ProjectShooterRoot $Rel
    $DestDir = Split-Path -Parent $Dest
    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

    if (Test-Path -LiteralPath $Dest -PathType Leaf) {
        $SrcHash = (Get-FileHash -LiteralPath $Source.FullName -Algorithm SHA256).Hash
        $DstHash = (Get-FileHash -LiteralPath $Dest -Algorithm SHA256).Hash
        if ($SrcHash -eq $DstHash) {
            $Identical++
        }
        else {
            $DifferentCollision++
            $CollisionList.Add($Dest)
        }
        continue
    }

    Copy-Item -LiteralPath $Source.FullName -Destination $Dest
    $Created++
}

Write-Host "SHOOTER_FILES_CREATED=$Created"
Write-Host "SHOOTER_FILES_ALREADY_IDENTICAL=$Identical"
Write-Host "SHOOTER_DIFFERENT_COLLISION_COUNT=$DifferentCollision"

if ($DifferentCollision -gt 0) {
    foreach ($C in $CollisionList) { Write-Host "DIFFERENT_COLLISION=$C" }
    Stop-Gate "VARIANT_SHOOTER_COLLISION_WITH_DIFFERENT_PROJECT_FILE" 12
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " UNREAL ASSET / BLUEPRINT / INPUT / ANIMATION CONTRACT AUDIT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Py = Join-Path $EvidenceRoot "phase02a_shooter_contract_$Stamp.py"
$Out = Join-Path $EvidenceRoot "phase02a_shooter_contract_$Stamp.stdout.log"
$Err = Join-Path $EvidenceRoot "phase02a_shooter_contract_$Stamp.stderr.log"

$PyText = @'
import unreal

ROOTS = [
    "/Game/Variant_Shooter",
    "/Game/Characters/Mannequins",
    "/Game/Weapons",
]

registry = unreal.AssetRegistryHelpers.get_asset_registry()
registry.scan_paths_synchronous(ROOTS, True)

def asset_class_name(d):
    try:
        return str(d.asset_class_path.asset_name)
    except Exception:
        try:
            return str(d.asset_class)
        except Exception:
            return "UNKNOWN"

def safe_load(path):
    try:
        return unreal.load_asset(path)
    except Exception:
        return None

print("ASWW_P02A_BEGIN=True")

# --- Inventory all shooter assets ---
assets = registry.get_assets_by_path("/Game/Variant_Shooter", recursive=True)
print(f"ASWW_P02A_SHOOTER_ASSET_COUNT={len(assets)}")

class_counts = {}
for d in assets:
    cls = asset_class_name(d)
    class_counts[cls] = class_counts.get(cls, 0) + 1
for cls in sorted(class_counts):
    print(f"ASWW_P02A_CLASS_COUNT|CLASS={cls}|COUNT={class_counts[cls]}")

# --- Candidate gameplay blueprints ---
bp_candidates = []
for d in assets:
    cls = asset_class_name(d)
    name = str(d.asset_name)
    pkg = str(d.package_name)
    low = (name + " " + pkg + " " + cls).lower()

    if cls in ("Blueprint", "AnimBlueprint", "WidgetBlueprint"):
        score = 0
        if "character" in low: score += 300
        if "player" in low: score += 250
        if "shooter" in low: score += 220
        if "rifle" in low: score += 200
        if "weapon" in low: score += 180
        if "third" in low or "tp_" in low: score += 170
        if "input" in low: score += 120
        bp_candidates.append((score, cls, pkg, name))

bp_candidates.sort(key=lambda x: (-x[0], x[2].lower(), x[3].lower()))
print(f"ASWW_P02A_BP_CANDIDATE_COUNT={len(bp_candidates)}")
for i,(score,cls,pkg,name) in enumerate(bp_candidates[:50], 1):
    print(f"ASWW_P02A_BP_{i}|SCORE={score}|CLASS={cls}|PACKAGE={pkg}|NAME={name}")

# --- Explicitly inspect ABP_TP_Rifle ---
abp_path = "/Game/Variant_Shooter/Anims/ABP_TP_Rifle.ABP_TP_Rifle"
abp = safe_load(abp_path)
print(f"ASWW_P02A_ABP_TP_RIFLE_LOAD={abp is not None}")
if abp:
    print(f"ASWW_P02A_ABP_TP_RIFLE_CLASS={abp.get_class().get_name()}")
    try:
        sk = abp.get_editor_property("target_skeleton")
    except Exception:
        sk = None
    print(f"ASWW_P02A_ABP_TP_RIFLE_SKELETON={sk.get_path_name() if sk else 'NONE'}")

    # Generated class introspection
    try:
        gen_cls = abp.generated_class()
    except Exception:
        try:
            gen_cls = abp.get_editor_property("generated_class")
        except Exception:
            gen_cls = None

    print(f"ASWW_P02A_ABP_TP_RIFLE_GENERATED_CLASS={gen_cls.get_name() if gen_cls else 'NONE'}")

    if gen_cls:
        try:
            cdo = unreal.get_default_object(gen_cls)
        except Exception:
            cdo = None

        if cdo:
            props = [p for p in dir(cdo) if not p.startswith("_")]
            interesting = []
            for p in props:
                low = p.lower()
                if any(k in low for k in (
                    "speed","direction","aim","ads","rifle","weapon","move","fall",
                    "crouch","sprint","jump","pitch","yaw","strafe","velocity","ik","hand"
                )):
                    interesting.append(p)
            print(f"ASWW_P02A_ABP_CDO_INTERESTING_COUNT={len(interesting)}")
            for p in sorted(interesting)[:200]:
                try:
                    v = getattr(cdo, p)
                    if callable(v):
                        continue
                    print(f"ASWW_P02A_ABP_CDO_PROP|NAME={p}|VALUE={v}")
                except Exception:
                    print(f"ASWW_P02A_ABP_CDO_PROP|NAME={p}|VALUE=UNREADABLE")

# --- Dependency contract for TP rifle ABP ---
try:
    dep_opts = unreal.AssetRegistryDependencyOptions(
        include_soft_package_references=True,
        include_hard_package_references=True,
        include_searchable_names=False,
        include_soft_management_references=False,
        include_hard_management_references=False
    )
    deps = registry.get_dependencies("/Game/Variant_Shooter/Anims/ABP_TP_Rifle", dep_opts)
    print(f"ASWW_P02A_ABP_DEP_COUNT={len(deps)}")
    for d in deps:
        print(f"ASWW_P02A_ABP_DEP={d}")
except Exception as exc:
    print(f"ASWW_P02A_ABP_DEP_ERROR={exc}")

# --- Character/Pawn Blueprint parent classes + components ---
for score,cls,pkg,name in bp_candidates:
    if cls != "Blueprint":
        continue
    low = (pkg + "/" + name).lower()
    if not any(k in low for k in ("character","player","shooter")):
        continue

    obj = safe_load(f"{pkg}.{name}")
    if not obj:
        print(f"ASWW_P02A_GAMEPLAY_BP|PACKAGE={pkg}|NAME={name}|LOAD=False")
        continue

    try:
        gen = obj.generated_class()
    except Exception:
        gen = None

    parent_name = "NONE"
    if gen:
        try:
            parent_name = gen.get_super_class().get_name()
        except Exception:
            try:
                parent_name = str(gen.get_editor_property("super_struct"))
            except Exception:
                pass

    print(
        f"ASWW_P02A_GAMEPLAY_BP|PACKAGE={pkg}|NAME={name}|LOAD=True|"
        f"GENERATED={gen.get_name() if gen else 'NONE'}|PARENT={parent_name}"
    )

    if gen:
        try:
            cdo = unreal.get_default_object(gen)
        except Exception:
            cdo = None
        if cdo:
            comps = []
            try:
                comps = cdo.get_components_by_class(unreal.ActorComponent)
            except Exception:
                comps = []
            print(f"ASWW_P02A_GAMEPLAY_BP_COMPONENT_COUNT|NAME={name}|COUNT={len(comps)}")
            for c in comps:
                print(
                    f"ASWW_P02A_GAMEPLAY_BP_COMPONENT|BP={name}|"
                    f"COMP={c.get_name()}|CLASS={c.get_class().get_name()}"
                )

# --- Enhanced Input assets ---
for d in assets:
    cls = asset_class_name(d)
    name = str(d.asset_name)
    pkg = str(d.package_name)
    if cls in ("InputMappingContext","InputAction") or "Input" in cls:
        print(f"ASWW_P02A_INPUT_ASSET|CLASS={cls}|PACKAGE={pkg}|NAME={name}")

# --- Animation assets important for tactical locomotion ---
for d in assets:
    cls = asset_class_name(d)
    name = str(d.asset_name)
    pkg = str(d.package_name)
    low = (name + " " + pkg).lower()
    if any(k in low for k in ("rifle","aim","ads","reload","fire","equip","strafe","crouch","sprint")):
        if cls in (
            "AnimSequence","AnimMontage","AimOffsetBlendSpace","BlendSpace",
            "BlendSpace1D","PoseAsset","AnimBlueprint"
        ):
            print(f"ASWW_P02A_TACTICAL_ANIM|CLASS={cls}|PACKAGE={pkg}|NAME={name}")

# --- Manny sockets/bones ---
manny = safe_load("/Game/Characters/Mannequins/Meshes/SKM_Manny_Simple.SKM_Manny_Simple")
print(f"ASWW_P02A_MANNY_LOAD={manny is not None}")
if manny:
    comp = unreal.new_object(unreal.SkeletalMeshComponent)
    try:
        comp.set_skeletal_mesh_asset(manny)
    except Exception:
        try:
            comp.set_skeletal_mesh(manny)
        except Exception:
            pass

    names = []
    try:
        names = [str(x) for x in comp.get_all_socket_names()]
    except Exception:
        names = []

    lower = {x.lower() for x in names}
    for n in (
        "hand_r","hand_l","ik_hand_gun","ik_hand_r","ik_hand_l",
        "HandGrip_R","HandGrip_L","weapon_r_muzzle"
    ):
        print(f"ASWW_P02A_MANNY_NAME|NAME={n}|FOUND={n.lower() in lower}")

    for n in ("HandGrip_R","HandGrip_L","weapon_r_muzzle"):
        socket = None
        try:
            socket = manny.find_socket(n)
        except Exception:
            socket = None
        print(f"ASWW_P02A_MANNY_SOCKET|NAME={n}|FOUND={socket is not None}")
        if socket:
            try:
                bone = socket.get_editor_property("bone_name")
                loc = socket.get_editor_property("relative_location")
                rot = socket.get_editor_property("relative_rotation")
                print(f"ASWW_P02A_MANNY_SOCKET_XFORM|NAME={n}|BONE={bone}|LOC={loc}|ROT={rot}")
            except Exception as exc:
                print(f"ASWW_P02A_MANNY_SOCKET_XFORM_ERROR|NAME={n}|ERR={exc}")

# --- Current project Player V2 / GameMode blueprint/code assets in registry ---
project_assets = registry.get_assets_by_path("/Game", recursive=True)
for d in project_assets:
    cls = asset_class_name(d)
    name = str(d.asset_name)
    pkg = str(d.package_name)
    low = (name + " " + pkg).lower()
    if "playercharacterv2" in low or "asplayercharacterv2" in low:
        print(f"ASWW_P02A_CURRENT_PLAYER_ASSET|CLASS={cls}|PACKAGE={pkg}|NAME={name}")

print("ASWW_P02A_END=True")
'@

[IO.File]::WriteAllText($Py, $PyText, [Text.UTF8Encoding]::new($false))
$PyForward = $Py.Replace('\','/')

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

& $EditorCmd @Args 1> $Out 2> $Err
$Exit = $LASTEXITCODE

$Combined = ""
if (Test-Path -LiteralPath $Out) {
    $Combined += Get-Content -Raw -LiteralPath $Out
    Select-String -LiteralPath $Out -Pattern "ASWW_P02A_" |
        ForEach-Object { Write-Host $_.Line }
}
if (Test-Path -LiteralPath $Err) {
    $Combined += "`n" + (Get-Content -Raw -LiteralPath $Err)
}

$PythonError = $Combined -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$Fatal = $Combined -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

Write-Host ""
Write-Host "UNREAL_EDITOR_CMD_EXIT=$Exit"
Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "FATAL_ERROR_SEEN=$Fatal"

if ($Exit -ne 0 -or $PythonError -or $Fatal) {
    Stop-Gate "PHASE_02A_UNREAL_DISCOVERY_FAILED" $(if ($Exit -gt 0) { $Exit } else { 20 })
}

$ABPLoad = $Combined -match "ASWW_P02A_ABP_TP_RIFLE_LOAD=True"
$MannyLoad = $Combined -match "ASWW_P02A_MANNY_LOAD=True"
$RightGrip = $Combined -match "ASWW_P02A_MANNY_SOCKET\|NAME=HandGrip_R\|FOUND=True"
$LeftGrip = $Combined -match "ASWW_P02A_MANNY_SOCKET\|NAME=HandGrip_L\|FOUND=True"
$IKGun = $Combined -match "ASWW_P02A_MANNY_NAME\|NAME=ik_hand_gun\|FOUND=True"
$IKLeft = $Combined -match "ASWW_P02A_MANNY_NAME\|NAME=ik_hand_l\|FOUND=True"
$GameplayBPCount = ([regex]::Matches($Combined, "ASWW_P02A_GAMEPLAY_BP\|")).Count
$InputAssetCount = ([regex]::Matches($Combined, "ASWW_P02A_INPUT_ASSET\|")).Count
$TacticalAnimCount = ([regex]::Matches($Combined, "ASWW_P02A_TACTICAL_ANIM\|")).Count

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PHASE 02A CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "ABP_TP_RIFLE_LOAD=$ABPLoad"
Write-Host "MANNY_LOAD=$MannyLoad"
Write-Host "HANDGRIP_R_SOCKET=$RightGrip"
Write-Host "HANDGRIP_L_SOCKET=$LeftGrip"
Write-Host "IK_HAND_GUN=$IKGun"
Write-Host "IK_HAND_L=$IKLeft"
Write-Host "GAMEPLAY_BLUEPRINT_CANDIDATE_COUNT=$GameplayBPCount"
Write-Host "ENHANCED_INPUT_ASSET_COUNT=$InputAssetCount"
Write-Host "TACTICAL_ANIMATION_ASSET_COUNT=$TacticalAnimCount"

if ($ABPLoad -and $MannyLoad -and $RightGrip -and $LeftGrip -and $IKGun -and $IKLeft) {
    Write-Host "PHASE_02A_SHOOTER_CONTRACT=PASS" -ForegroundColor Green
    Write-Host "NEXT_GATE=BUILD_ASWW_COMBAT_PLAYER_FROM_VERIFIED_SHOOTER_CONTRACT" -ForegroundColor Green
}
else {
    Write-Host "PHASE_02A_SHOOTER_CONTRACT=PARTIAL" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=FIX_ONLY_MISSING_SHOOTER_CONTRACT_DEPENDENCIES" -ForegroundColor Yellow
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"

Write-Host "NO_GAMEPLAY_SOURCE_WAS_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
