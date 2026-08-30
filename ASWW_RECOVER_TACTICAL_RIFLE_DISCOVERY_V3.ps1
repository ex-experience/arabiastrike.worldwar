[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\TacticalRifleDiscoveryV2"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "TACTICAL_RIFLE_DISCOVERY_V2=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Read-AssetStrings {
    param([string]$Path)

    $Bytes = [IO.File]::ReadAllBytes($Path)
    $Ascii = [Text.Encoding]::ASCII.GetString($Bytes)
    $Unicode = [Text.Encoding]::Unicode.GetString($Bytes)
    return ($Ascii + "`n" + $Unicode)
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

foreach ($Required in @($ProjectFile,$EditorCmd)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " WHY V1 WAS A FALSE NEGATIVE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "The previous probe reported hand_r=False and hand_l=False."
Write-Host "Manny visibly animates, so those results cannot be accepted as proof that the bones do not exist."
Write-Host "V2 verifies bone names from actual local asset packages and separately audits Unreal socket APIs."

$MeshCandidates = @(
    (Join-Path $ProjectRoot "Content\Characters\Mannequins\Meshes\SKM_Manny_Simple.uasset"),
    (Join-Path $ProjectRoot "Content\Characters\Mannequins\Meshes\SK_Mannequin.uasset")
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " MANNY BONE-NAME PACKAGE EVIDENCE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$BoneNames = @("hand_r","hand_l","ik_hand_gun","ik_hand_r","ik_hand_l")
$BoneEvidence = @{}

foreach ($Bone in $BoneNames) {
    $BoneEvidence[$Bone] = $false
}

foreach ($Asset in $MeshCandidates) {
    Write-Host "MANNY_PACKAGE_SCAN=$Asset"
    $Strings = Read-AssetStrings $Asset

    foreach ($Bone in $BoneNames) {
        $Found = $Strings.IndexOf($Bone, [StringComparison]::OrdinalIgnoreCase) -ge 0
        if ($Found) { $BoneEvidence[$Bone] = $true }
        Write-Host "PACKAGE_BONE_EVIDENCE|FILE=$(Split-Path -Leaf $Asset)|BONE=$Bone|FOUND=$Found"
    }
}

foreach ($Bone in $BoneNames) {
    Write-Host "BONE_STRING_$($Bone.ToUpper())=$($BoneEvidence[$Bone])"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FILESYSTEM ANIM BLUEPRINT DISCOVERY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$SearchRoots = @(
    (Join-Path $ProjectRoot "Content\Characters\Mannequins"),
    (Join-Path $UERoot "Templates\TemplateResources\High\Characters\Content\Mannequins"),
    (Join-Path $UERoot "Templates\TemplateResources\Standard"),
    (Join-Path $UERoot "Templates\TP_ThirdPersonBP"),
    (Join-Path $UERoot "Templates\TP_FirstPersonBP")
) | Where-Object { Test-Path -LiteralPath $_ -PathType Container }

$ABPFiles = @()
foreach ($Root in $SearchRoots) {
    $ABPFiles += Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "ABP*.uasset" -ErrorAction SilentlyContinue
}
$ABPFiles = @($ABPFiles | Sort-Object FullName -Unique)

Write-Host "FILESYSTEM_ANIM_BLUEPRINT_FILE_COUNT=$($ABPFiles.Count)"

$Ranked = @()

foreach ($File in $ABPFiles) {
    $Strings = Read-AssetStrings $File
    $HasRifle = $Strings -match '(?i)Rifle'
    $HasIKLeft = $Strings -match '(?i)ik_hand_l|left.?hand.?ik'
    $HasIKGun = $Strings -match '(?i)ik_hand_gun'
    $HasAim = $Strings -match '(?i)Aim|ADS|AimOffset'
    $HasUnarmed = $Strings -match '(?i)Unarmed'

    $Score = 0
    if ($File.BaseName -match '(?i)Rifle|Weapon|Combat|Armed|Shooter') { $Score += 300 }
    if ($HasRifle) { $Score += 250 }
    if ($HasIKLeft) { $Score += 120 }
    if ($HasIKGun) { $Score += 100 }
    if ($HasAim) { $Score += 80 }
    if ($File.FullName -match '(?i)High\\Characters') { $Score += 40 }
    if ($File.FullName -match [regex]::Escape($ProjectRoot)) { $Score += 20 }
    if ($HasUnarmed -and -not $HasRifle) { $Score -= 100 }

    $Ranked += [pscustomobject]@{
        Score = $Score
        Name = $File.BaseName
        Path = $File.FullName
        RifleRef = $HasRifle
        IKLeft = $HasIKLeft
        IKGun = $HasIKGun
        AimRef = $HasAim
    }
}

$Ranked = @($Ranked | Sort-Object -Property @{Expression='Score';Descending=$true}, @{Expression='Path';Descending=$false})

$i = 0
foreach ($R in $Ranked | Select-Object -First 30) {
    $i++
    Write-Host ("ABP_CANDIDATE_{0}|SCORE={1}|NAME={2}|RIFLE_REF={3}|IK_LEFT_REF={4}|IK_GUN_REF={5}|AIM_REF={6}|PATH={7}" -f
        $i,$R.Score,$R.Name,$R.RifleRef,$R.IKLeft,$R.IKGun,$R.AimRef,$R.Path)
}

$BestABP = $null
if ($Ranked.Count -gt 0) {
    $BestABP = $Ranked[0]
    Write-Host "BEST_ABP_CANDIDATE_SCORE=$($BestABP.Score)"
    Write-Host "BEST_ABP_CANDIDATE_NAME=$($BestABP.Name)"
    Write-Host "BEST_ABP_CANDIDATE_RIFLE_REF=$($BestABP.RifleRef)"
    Write-Host "BEST_ABP_CANDIDATE_IK_LEFT_REF=$($BestABP.IKLeft)"
    Write-Host "BEST_ABP_CANDIDATE_IK_GUN_REF=$($BestABP.IKGun)"
    Write-Host "BEST_ABP_CANDIDATE_PATH=$($BestABP.Path)"
}
else {
    Write-Host "BEST_ABP_CANDIDATE_SCORE=-1"
    Write-Host "BEST_ABP_CANDIDATE_NAME=NONE"
    Write-Host "BEST_ABP_CANDIDATE_PATH=NONE"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " UNREAL REGISTRY + SOCKET API AUDIT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$PyFile = Join-Path $EvidenceRoot "recover_tactical_discovery_v2_$Stamp.py"
$StdOut = Join-Path $EvidenceRoot "recover_tactical_discovery_v2_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "recover_tactical_discovery_v2_$Stamp.stderr.log"

$Python = @'
import unreal

MANNY = "/Game/Characters/Mannequins/Meshes/SKM_Manny_Simple.SKM_Manny_Simple"

registry = unreal.AssetRegistryHelpers.get_asset_registry()
registry.scan_paths_synchronous(["/Game/Characters/Mannequins"], True)

mesh = unreal.load_asset(MANNY)
print(f"ASWW_V2_MANNY_LOAD={mesh is not None}")
print(f"ASWW_V2_MANNY_CLASS={mesh.get_class().get_name() if mesh else 'NONE'}")

if mesh:
    skel = None
    try:
        skel = mesh.get_editor_property("skeleton")
    except Exception as exc:
        print(f"ASWW_V2_SKELETON_PROPERTY_ERROR={exc}")

    print(f"ASWW_V2_SKELETON={skel.get_path_name() if skel else 'NONE'}")

    # Introspection is evidence about API availability, not gameplay proof.
    mesh_methods = [x for x in dir(mesh) if "bone" in x.lower() or "socket" in x.lower()]
    skel_methods = [x for x in dir(skel) if "bone" in x.lower() or "socket" in x.lower()] if skel else []
    print("ASWW_V2_MESH_BONE_SOCKET_METHODS=" + ",".join(mesh_methods))
    print("ASWW_V2_SKELETON_BONE_SOCKET_METHODS=" + ",".join(skel_methods))

    # SkeletalMeshComponent exposes socket queries more reliably than the asset in many UE Python builds.
    comp = None
    try:
        comp = unreal.new_object(unreal.SkeletalMeshComponent)
        try:
            comp.set_skeletal_mesh_asset(mesh)
        except Exception:
            try:
                comp.set_skeletal_mesh(mesh)
            except Exception as exc:
                print(f"ASWW_V2_COMPONENT_SET_MESH_ERROR={exc}")

        names = []
        try:
            names = list(comp.get_all_socket_names())
        except Exception as exc:
            print(f"ASWW_V2_GET_ALL_SOCKET_NAMES_ERROR={exc}")

        print(f"ASWW_V2_COMPONENT_SOCKET_OR_BONE_NAME_COUNT={len(names)}")
        lower = {str(x).lower() for x in names}

        for n in ("hand_r","hand_l","ik_hand_gun","ik_hand_r","ik_hand_l"):
            print(f"ASWW_V2_COMPONENT_NAME_{n.upper()}={n.lower() in lower}")

        for n in names:
            s = str(n)
            if any(k in s.lower() for k in ("weapon","rifle","gun","hand")):
                print(f"ASWW_V2_SOCKET_OR_BONE_CANDIDATE={s}")

    except Exception as exc:
        print(f"ASWW_V2_COMPONENT_PROBE_ERROR={exc}")

assets = registry.get_assets_by_path("/Game/Characters/Mannequins", recursive=True)
abps = []
for d in assets:
    try:
        cls = str(d.asset_class_path.asset_name)
        if cls == "AnimBlueprint":
            abps.append(d)
    except Exception:
        pass

print(f"ASWW_V2_PROJECT_ANIMBLUEPRINT_COUNT={len(abps)}")
for d in abps:
    print(
        f"ASWW_V2_PROJECT_ABP|PACKAGE={d.package_name}|NAME={d.asset_name}|"
        f"CLASS={d.asset_class_path.asset_name}"
    )

print("ASWW_V2_UNREAL_DISCOVERY_DONE=True")
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

$Combined = ""
if (Test-Path -LiteralPath $StdOut) {
    $Combined += Get-Content -Raw -LiteralPath $StdOut
    Select-String -LiteralPath $StdOut -Pattern "ASWW_V2_" |
        ForEach-Object { Write-Host $_.Line }
}
if (Test-Path -LiteralPath $StdErr) {
    $Combined += "`n" + (Get-Content -Raw -LiteralPath $StdErr)
}

$PythonError = $Combined -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$Fatal = $Combined -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

Write-Host "UNREAL_EDITOR_CMD_EXIT=$Exit"
Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "FATAL_ERROR_SEEN=$Fatal"

if ($Exit -ne 0 -or $PythonError -or $Fatal) {
    Stop-Gate "UNREAL_V2_DISCOVERY_FAILED" $(if ($Exit -gt 0) { $Exit } else { 30 })
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RECOVERY CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$PackageHandsVerified = $BoneEvidence["hand_r"] -and $BoneEvidence["hand_l"]
$PackageIKVerified = $BoneEvidence["ik_hand_gun"] -or ($BoneEvidence["ik_hand_r"] -and $BoneEvidence["ik_hand_l"])

Write-Host "MANNY_HAND_BONES_PACKAGE_VERIFIED=$PackageHandsVerified"
Write-Host "MANNY_IK_BONES_PACKAGE_VERIFIED=$PackageIKVerified"

$StrongABP = $false
if ($BestABP) {
    $StrongABP = ($BestABP.Score -ge 250 -and $BestABP.RifleRef)
}
Write-Host "STRONG_RIFLE_ABP_FILESYSTEM_CANDIDATE=$StrongABP"

if ($StrongABP -and $PackageHandsVerified) {
    Write-Host "TACTICAL_RECOVERY_CLASSIFICATION=RIFLE_ABP_CANDIDATE_FOUND_V1_PROBE_WAS_FALSE_NEGATIVE" -ForegroundColor Green
    Write-Host "NEXT_GATE=VERIFY_AND_IMPORT_SELECTED_RIFLE_ABP_DEPENDENCIES_THEN_PACKAGE" -ForegroundColor Green
}
elseif (-not $StrongABP -and $PackageHandsVerified) {
    Write-Host "TACTICAL_RECOVERY_CLASSIFICATION=MANNY_BONES_VERIFIED_NO_READY_RIFLE_ABP_FOUND" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=BUILD_ASWW_RIFLE_ANIMBLUEPRINT_FROM_OFFICIAL_RIFLE_ANIMS" -ForegroundColor Yellow
}
else {
    Write-Host "TACTICAL_RECOVERY_CLASSIFICATION=NEEDS_MANNEQUIN_PACKAGE_DEPENDENCY_RECHECK" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=VERIFY_MANNY_SKELETON_PACKAGE_AND_TEMPLATE_DEPENDENCIES" -ForegroundColor Yellow
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"

Write-Host ""
Write-Host "TACTICAL_RIFLE_DISCOVERY_V2=PASS" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
