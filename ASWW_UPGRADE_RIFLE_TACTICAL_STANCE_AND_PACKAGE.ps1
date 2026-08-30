[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$StageRoot = "D:\ASWW_STAGE"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "TACTICAL_RIFLE_UPGRADE=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
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
$BuildScript = Join-Path $ProjectRoot "BuildScripts\build_win64.ps1"
$CharacterCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"

$SourceRifleAnimRoot = Join-Path $UERoot "Templates\TemplateResources\High\Characters\Content\Mannequins\Anims\Rifle"
$DestRifleAnimRoot = Join-Path $ProjectRoot "Content\Characters\Mannequins\Anims\Rifle"

foreach ($Required in @($ProjectFile,$EditorCmd,$BuildScript,$CharacterCpp,$SourceRifleAnimRoot)) {
    if (-not (Test-Path -LiteralPath $Required)) {
        Stop-Gate "MISSING_REQUIRED_PATH_$Required" 11
    }
}

$Original = Get-Content -Raw -LiteralPath $CharacterCpp

if ($Original -notmatch "ASWW_REAL_PLAYER_MANNY") {
    Stop-Gate "REAL_MANNY_INTEGRATION_NOT_FOUND" 12
}
if ($Original -notmatch "ASWW_REAL_RIFLE_VISUAL_BEGIN") {
    Stop-Gate "CURRENT_REAL_RIFLE_VISUAL_BLOCK_NOT_FOUND" 13
}
if ($Original -match "ASWW_TACTICAL_RIFLE_PRESENTATION_BEGIN") {
    Stop-Gate "TACTICAL_RIFLE_PRESENTATION_ALREADY_PRESENT" 14
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COPY OFFICIAL UE RIFLE ANIMATION FAMILY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\TacticalRifleUpgrade_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
Copy-Item -LiteralPath $CharacterCpp -Destination (Join-Path $BackupRoot "ASCharacter.cpp.before_tactical_rifle") -Force

$DestAlreadyExists = Test-Path -LiteralPath $DestRifleAnimRoot -PathType Container
if ($DestAlreadyExists) {
    $ExistingFileCount = @(
        Get-ChildItem -LiteralPath $DestRifleAnimRoot -Recurse -File -ErrorAction SilentlyContinue
    ).Count
    Write-Host "DEST_RIFLE_ANIM_ROOT_PREEXISTED=True"
    Write-Host "DEST_RIFLE_ANIM_EXISTING_FILE_COUNT=$ExistingFileCount"

    if ($ExistingFileCount -gt 0) {
        $AnimBackup = Join-Path $BackupRoot "RifleAnims.before_upgrade"
        Copy-Item -LiteralPath $DestRifleAnimRoot -Destination $AnimBackup -Recurse -Force
        Write-Host "RIFLE_ANIM_BACKUP=$AnimBackup"
    }
}
else {
    Write-Host "DEST_RIFLE_ANIM_ROOT_PREEXISTED=False"
}

New-Item -ItemType Directory -Force -Path $DestRifleAnimRoot | Out-Null

$Children = @(Get-ChildItem -LiteralPath $SourceRifleAnimRoot -Force -ErrorAction Stop)
Write-Host "SOURCE_RIFLE_ANIM_CHILD_COUNT=$($Children.Count)"
if ($Children.Count -eq 0) {
    Stop-Gate "SOURCE_RIFLE_ANIM_ROOT_EMPTY" 20
}

foreach ($Child in $Children) {
    Copy-Item -LiteralPath $Child.FullName -Destination $DestRifleAnimRoot -Recurse -Force
}

$AnimFiles = @(Get-ChildItem -LiteralPath $DestRifleAnimRoot -Recurse -File -Filter "*.uasset" -ErrorAction Stop)
Write-Host "COPIED_RIFLE_ANIM_UASSET_COUNT=$($AnimFiles.Count)"
if ($AnimFiles.Count -lt 1) {
    Stop-Gate "NO_RIFLE_ANIMATION_UASSETS_COPIED" 21
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " DISCOVER RIFLE ABP + WEAPON SOCKET + IK BONES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\TacticalRifleDiscovery"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

$Py = Join-Path $EvidenceRoot "discover_tactical_rifle_$Stamp.py"
$Out = Join-Path $EvidenceRoot "discover_tactical_rifle_$Stamp.stdout.log"
$Err = Join-Path $EvidenceRoot "discover_tactical_rifle_$Stamp.stderr.log"

$PyText = @'
import unreal

MANNY_MESH = "/Game/Characters/Mannequins/Meshes/SKM_Manny_Simple.SKM_Manny_Simple"
RIFLE_ROOT = "/Game/Characters/Mannequins/Anims/Rifle"

registry = unreal.AssetRegistryHelpers.get_asset_registry()
registry.scan_paths_synchronous(["/Game/Characters/Mannequins"], True)

mesh = unreal.load_asset(MANNY_MESH)
print(f"ASWW_TACTICAL_MANNY_LOAD={mesh is not None}")
if not mesh:
    raise RuntimeError("Manny mesh failed to load")

skeleton = mesh.get_editor_property("skeleton")
print(f"ASWW_TACTICAL_MANNY_SKELETON={skeleton.get_path_name() if skeleton else 'NONE'}")
if not skeleton:
    raise RuntimeError("Manny skeleton missing")

assets = registry.get_assets_by_path(RIFLE_ROOT, recursive=True)
print(f"ASWW_TACTICAL_RIFLE_ASSET_COUNT={len(assets)}")

abps = []
for d in assets:
    cls = str(d.asset_class_path.asset_name)
    name = str(d.asset_name)
    pkg = str(d.package_name)
    if cls == "AnimBlueprint":
        score = 0
        low = (name + " " + pkg).lower()
        if name.lower() == "abp_rifle":
            score += 1000
        if "rifle" in low:
            score += 200
        if "armed" in low:
            score += 100
        abps.append((score, pkg, name))

abps.sort(key=lambda x: (-x[0], x[1].lower()))
print(f"ASWW_TACTICAL_RIFLE_ABP_COUNT={len(abps)}")
for score,pkg,name in abps[:20]:
    print(f"ASWW_TACTICAL_RIFLE_ABP|SCORE={score}|PACKAGE={pkg}|NAME={name}")

best = None
for score,pkg,name in abps:
    obj = unreal.load_asset(f"{pkg}.{name}")
    if not obj:
        continue
    try:
        target_skeleton = obj.get_editor_property("target_skeleton")
    except Exception:
        target_skeleton = None
    same = bool(target_skeleton and target_skeleton.get_path_name() == skeleton.get_path_name())
    print(
        f"ASWW_TACTICAL_RIFLE_ABP_VERIFY|PACKAGE={pkg}|NAME={name}|"
        f"LOAD=True|TARGET_SKELETON={target_skeleton.get_path_name() if target_skeleton else 'NONE'}|"
        f"SAME_SKELETON={same}"
    )
    if same and best is None:
        best = (pkg,name)
        break

if best:
    print(f"ASWW_TACTICAL_SELECTED_ABP_PACKAGE={best[0]}")
    print(f"ASWW_TACTICAL_SELECTED_ABP_NAME={best[1]}")
    print(f"ASWW_TACTICAL_SELECTED_ABP_OBJECT={best[0]}.{best[1]}")
else:
    print("ASWW_TACTICAL_SELECTED_ABP_PACKAGE=NONE")
    print("ASWW_TACTICAL_SELECTED_ABP_NAME=NONE")
    print("ASWW_TACTICAL_SELECTED_ABP_OBJECT=NONE")

# Bones
ref = mesh.get_editor_property("skeleton").get_reference_skeleton() if hasattr(mesh.get_editor_property("skeleton"), "get_reference_skeleton") else None
# UE Python API varies; use SkeletalMesh bone-name helpers first.
bone_names = []
try:
    bone_count = mesh.get_editor_property("ref_skeleton").get_num()
except Exception:
    bone_count = 0

# Asset API fallback: search known bone names with find_bone_index if available.
known_bones = ["hand_r","hand_l","ik_hand_gun","ik_hand_r","ik_hand_l","weapon_r","weapon_l"]
for b in known_bones:
    found = False
    try:
        idx = mesh.find_bone_index(b)
        found = int(idx) >= 0
    except Exception:
        try:
            idx = skeleton.find_bone_index(b)
            found = int(idx) >= 0
        except Exception:
            pass
    print(f"ASWW_TACTICAL_BONE_{b.upper()}={found}")

# Sockets: best effort.
socket_names = []
try:
    sockets = skeleton.get_editor_property("sockets")
    for s in sockets:
        try:
            n = str(s.get_editor_property("socket_name"))
        except Exception:
            try:
                n = str(s.socket_name)
            except Exception:
                continue
        socket_names.append(n)
except Exception as exc:
    print(f"ASWW_TACTICAL_SOCKET_ENUM_WARNING={exc}")

print(f"ASWW_TACTICAL_SOCKET_COUNT={len(socket_names)}")
for n in socket_names:
    if any(k in n.lower() for k in ("weapon","rifle","gun","hand")):
        print(f"ASWW_TACTICAL_SOCKET_CANDIDATE={n}")

priority = [
    "weapon_r","Weapon_R","weapon_socket","WeaponSocket",
    "rifle_socket","RifleSocket","gun_r","Gun_R"
]
selected_socket = None
for p in priority:
    if p in socket_names:
        selected_socket = p
        break

if not selected_socket:
    # If there is no dedicated socket, do not silently keep the bad hand_r zero-transform setup.
    selected_socket = "NONE"

print(f"ASWW_TACTICAL_SELECTED_WEAPON_SOCKET={selected_socket}")

print("ASWW_TACTICAL_DISCOVERY_DONE=True")
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
$DiscoverExit = $LASTEXITCODE

$Combined = ""
if (Test-Path -LiteralPath $Out) {
    $Combined += Get-Content -Raw -LiteralPath $Out
    Select-String -LiteralPath $Out -Pattern "ASWW_TACTICAL_" |
        ForEach-Object { Write-Host $_.Line }
}
if (Test-Path -LiteralPath $Err) {
    $Combined += "`n" + (Get-Content -Raw -LiteralPath $Err)
}

$PythonError = $Combined -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$Fatal = $Combined -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

Write-Host "TACTICAL_DISCOVERY_EDITOR_EXIT=$DiscoverExit"
Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "FATAL_ERROR_SEEN=$Fatal"

if ($DiscoverExit -ne 0 -or $PythonError -or $Fatal) {
    Stop-Gate "TACTICAL_RIFLE_UNREAL_DISCOVERY_FAILED" 30
}

function Read-Value([string]$Name) {
    $m = [regex]::Match($Combined, [regex]::Escape($Name) + "=([^\r\n]+)")
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ""
}

$SelectedABP = Read-Value "ASWW_TACTICAL_SELECTED_ABP_OBJECT"
$SelectedABPPackage = Read-Value "ASWW_TACTICAL_SELECTED_ABP_PACKAGE"
$SelectedSocket = Read-Value "ASWW_TACTICAL_SELECTED_WEAPON_SOCKET"
$IKGun = Read-Value "ASWW_TACTICAL_BONE_IK_HAND_GUN"
$IKLeft = Read-Value "ASWW_TACTICAL_BONE_IK_HAND_L"
$HandLeft = Read-Value "ASWW_TACTICAL_BONE_HAND_L"
$HandRight = Read-Value "ASWW_TACTICAL_BONE_HAND_R"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TACTICAL UPGRADE PREREQUISITE CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "SELECTED_RIFLE_ABP=$SelectedABP"
Write-Host "SELECTED_WEAPON_SOCKET=$SelectedSocket"
Write-Host "IK_HAND_GUN_BONE_PRESENT=$IKGun"
Write-Host "IK_HAND_L_BONE_PRESENT=$IKLeft"
Write-Host "HAND_L_BONE_PRESENT=$HandLeft"
Write-Host "HAND_R_BONE_PRESENT=$HandRight"

if ([string]::IsNullOrWhiteSpace($SelectedABP) -or $SelectedABP -eq "NONE") {
    Stop-Gate "NO_COMPATIBLE_RIFLE_ANIM_BLUEPRINT_FOUND_STOP_BEFORE_SOURCE_WRITE" 31
}

if ([string]::IsNullOrWhiteSpace($SelectedSocket) -or $SelectedSocket -eq "NONE") {
    Stop-Gate "NO_DEDICATED_WEAPON_SOCKET_FOUND_STOP_BEFORE_SOURCE_WRITE" 32
}

if ($HandLeft -ne "True" -or $HandRight -ne "True") {
    Stop-Gate "REQUIRED_HAND_BONES_NOT_VERIFIED" 33
}

# Read the selected ABP file and look for explicit IK-related names as supporting evidence.
$SelectedABPRelative = $SelectedABPPackage -replace '^/Game/',''
$SelectedABPFile = Join-Path $ProjectRoot ("Content\" + ($SelectedABPRelative.Replace('/','\')) + ".uasset")
$IKStringEvidence = $false

if (Test-Path -LiteralPath $SelectedABPFile -PathType Leaf) {
    $ABPBytes = [IO.File]::ReadAllBytes($SelectedABPFile)
    $ABPAscii = [Text.Encoding]::ASCII.GetString($ABPBytes)
    $IKStringEvidence = $ABPAscii -match '(?i)ik_hand_l|ik_hand_gun|left.?hand.?ik|two.?bone.?ik'
}

Write-Host "RIFLE_ABP_IK_STRING_EVIDENCE=$IKStringEvidence"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PATCH ARMED ABP + OFFICIAL WEAPON SOCKET" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Text = $Original

# Replace current Unarmed ABP path only once.
$UnarmedPattern = '/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed'
$UnarmedCount = ([regex]::Matches($Text, [regex]::Escape($UnarmedPattern))).Count
Write-Host "UNARMED_ABP_PATH_COUNT=$UnarmedCount"
if ($UnarmedCount -ne 1) {
    Stop-Gate "EXPECTED_EXACTLY_ONE_UNARMED_ABP_PATH_FOUND_$UnarmedCount" 40
}

$Text = $Text.Replace($UnarmedPattern, $SelectedABPPackage)

# Replace only the current rifle attachment socket inside the marked block.
$BlockPattern = '(?s)// ASWW_REAL_RIFLE_VISUAL_BEGIN.*?// ASWW_REAL_RIFLE_VISUAL_END'
$BlockMatch = [regex]::Match($Text, $BlockPattern)
if (-not $BlockMatch.Success) {
    Stop-Gate "RIFLE_VISUAL_BLOCK_NOT_FOUND_FOR_PATCH" 41
}

$Block = $BlockMatch.Value
$AttachCount = ([regex]::Matches($Block, 'SetupAttachment\(GetMesh\(\),\s*TEXT\("[^"]+"\)\)')).Count
if ($AttachCount -ne 1) {
    Stop-Gate "EXPECTED_ONE_RIFLE_SETUPATTACHMENT_FOUND_$AttachCount" 42
}

$Block = [regex]::Replace(
    $Block,
    'SetupAttachment\(GetMesh\(\),\s*TEXT\("[^"]+"\)\)',
    'SetupAttachment(GetMesh(), TEXT("' + $SelectedSocket + '"))',
    1
)

# Dedicated weapon socket should already encode the grip orientation/offset.
# Keep only scale at 1 and use identity local transform.
$Block = [regex]::Replace(
    $Block,
    'RifleVisual->SetRelativeLocation\([^;]+;\s*RifleVisual->SetRelativeRotation\([^;]+;\s*RifleVisual->SetRelativeScale3D\([^;]+;',
    'RifleVisual->SetRelativeTransform(FTransform::Identity);',
    1,
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

$Block = $Block -replace 'socket=hand_r', ('socket=' + $SelectedSocket)

$Text = $Text.Substring(0, $BlockMatch.Index) + $Block + $Text.Substring($BlockMatch.Index + $BlockMatch.Length)

# Insert a persistent marker comment only, no extra runtime telemetry.
$Marker = @"

    // ASWW_TACTICAL_RIFLE_PRESENTATION_BEGIN
    // Rifle locomotion/ready stance uses the compatible official rifle AnimBlueprint.
    // Weapon visual is attached to the discovered dedicated weapon socket.
    // Left-hand support grip/IK remains subject to packaged visual QA.
    // ASWW_TACTICAL_RIFLE_PRESENTATION_END

"@

$MannyLogPattern = '(?m)^\s*UE_LOG\(LogTemp,\s*Warning,\s*$\r?\n^\s*TEXT\("ASWW_REAL_PLAYER_MANNY mesh=%s animClass=%s"\),'
$MannyAnchor = [regex]::Match($Text, $MannyLogPattern)
if (-not $MannyAnchor.Success) {
    Stop-Gate "MANNY_LOG_ANCHOR_NOT_FOUND_FOR_MARKER" 43
}
$Text = $Text.Insert($MannyAnchor.Index, $Marker)

[IO.File]::WriteAllText($CharacterCpp, $Text, [Text.UTF8Encoding]::new($true))

$Disk = Get-Content -Raw -LiteralPath $CharacterCpp
$TacticalMarkerCount = ([regex]::Matches($Disk, "ASWW_TACTICAL_RIFLE_PRESENTATION_BEGIN")).Count
$SelectedABPPathCount = ([regex]::Matches($Disk, [regex]::Escape($SelectedABPPackage))).Count
$SelectedSocketCount = ([regex]::Matches($Disk, 'SetupAttachment\(GetMesh\(\),\s*TEXT\("' + [regex]::Escape($SelectedSocket) + '"\)\)')).Count

Write-Host "TACTICAL_PRESENTATION_MARKER_COUNT=$TacticalMarkerCount"
Write-Host "SELECTED_RIFLE_ABP_PATH_COUNT=$SelectedABPPathCount"
Write-Host "SELECTED_WEAPON_SOCKET_ATTACH_COUNT=$SelectedSocketCount"

if ($TacticalMarkerCount -ne 1 -or $SelectedABPPathCount -ne 1 -or $SelectedSocketCount -lt 1) {
    Stop-Gate "POST_PATCH_TACTICAL_SOURCE_VALIDATION_FAILED" 44
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 45
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLEAN BUILD + COOK + PACKAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 46
}

$PackageStart = Get-Date

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRETACTICAL_$Stamp"
    try {
        Move-Item -LiteralPath $StageRoot -Destination $OldStage
        Write-Host "OLD_STAGE_MOVED=$OldStage"
    }
    catch {
        Stop-Gate "STAGE_ROOT_LOCKED_$($_.Exception.Message)" 47
    }
}

$PackageEvidence = Join-Path $ProjectRoot "Saved\RuntimeEvidence\TacticalRiflePackage"
New-Item -ItemType Directory -Force -Path $PackageEvidence | Out-Null
$PackageLog = Join-Path $PackageEvidence "tactical_rifle_package_$Stamp.log"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BuildScript -UERoot $UERoot 2>&1 |
    Tee-Object -FilePath $PackageLog
$PackageExit = $LASTEXITCODE

Write-Host "PACKAGE_SCRIPT_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Write-Host ""
    Write-Host "=== PACKAGE FAILURE TAIL ===" -ForegroundColor Yellow
    Get-Content -LiteralPath $PackageLog -Tail 180
    Stop-Gate "BUILD_WIN64_FAILED_EXIT_$PackageExit" $(if ($PackageExit -gt 0) { $PackageExit } else { 50 })
}

$Exes = @(
    Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
)
if ($Exes.Count -eq 0) {
    Stop-Gate "PACKAGE_EXIT_ZERO_BUT_EXE_NOT_FOUND" 51
}

$Exe = $Exes[0]
$FreshExe = $Exe.LastWriteTime -ge $PackageStart.AddMinutes(-1)
$Containers = @(
    Get-ChildItem -LiteralPath $StageRoot -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @(".pak",".utoc",".ucas") }
)

Write-Host "PACKAGED_EXE=$($Exe.FullName)"
Write-Host "PACKAGED_EXE_FRESH=$FreshExe"
Write-Host "CONTAINER_FILE_COUNT=$($Containers.Count)"

if (-not $FreshExe -or $Containers.Count -eq 0) {
    Stop-Gate "PACKAGED_OUTPUT_NOT_FRESH_OR_NO_CONTAINERS" 52
}

Write-Host ""
Write-Host "TACTICAL_RIFLE_UPGRADE=PASS" -ForegroundColor Green
Write-Host "RIFLE_ANIM_BLUEPRINT=$SelectedABP" -ForegroundColor Green
Write-Host "WEAPON_SOCKET=$SelectedSocket" -ForegroundColor Green
Write-Host "IK_BONE_CHAIN_AVAILABLE=$($IKGun -eq 'True' -and $IKLeft -eq 'True')" -ForegroundColor Green
Write-Host "RIFLE_ABP_IK_STRING_EVIDENCE=$IKStringEvidence" -ForegroundColor Green
Write-Host "CLEAN_PACKAGE_TACTICAL_RIFLE=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_TACTICAL_RIFLE_VISUAL_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
