[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$StageRoot = "D:\ASWW_STAGE",
    [string]$ArchiveRoot = "D:\ASWW_ARCHIVE\Phase03F_Z_Reload"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_03F_Z_RELOAD_RUNTIME_FIX=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "QA_MARKERS=TEMPORARY_DO_NOT_COMMIT" -ForegroundColor Yellow
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Write-Utf8Bom([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($true))
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
$BuildBat = Join-Path $UERoot "Engine\Build\BatchFiles\Build.bat"
$RunUAT = Join-Path $UERoot "Engine\Build\BatchFiles\RunUAT.bat"
$V2Cpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASPlayerCharacterV2.cpp"
$WeaponCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Combat\ASWeaponComponent.cpp"
$DefaultGameIni = Join-Path $ProjectRoot "Config\DefaultGame.ini"

foreach ($Required in @($ProjectFile,$EditorCmd,$BuildBat,$RunUAT,$V2Cpp,$WeaponCpp,$DefaultGameIni)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

$V2 = Get-Content -Raw -LiteralPath $V2Cpp
$Weapon = Get-Content -Raw -LiteralPath $WeaponCpp
$GameIni = Get-Content -Raw -LiteralPath $DefaultGameIni

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY PHASE 03E STATE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$SafeEnter = $V2 -match 'EnterProne\(\)[\s\S]{0,900}Crouch\(false\)'
$CurrentExit = $V2 -match 'void\s+AASPlayerCharacterV2::ExitProne\(\)'
$ReloadKeyMarker = $V2 -match 'ASWW_QA_RELOAD_KEY_PRESSED'
$ReloadDiagnostics = $Weapon -match 'ASWW_QA_RELOAD_REJECT_NO_DEFINITION'
$AlreadyPatched = $V2 -match 'ASWW_PHASE03F_DEFAULT_RIFLE_LOADOUT_BEGIN'

Write-Host "SAFE_Z_ENTER_PRESENT=$SafeEnter"
Write-Host "EXIT_PRONE_PRESENT=$CurrentExit"
Write-Host "RELOAD_KEY_DIAGNOSTIC_PRESENT=$ReloadKeyMarker"
Write-Host "WEAPON_RELOAD_DIAGNOSTICS_PRESENT=$ReloadDiagnostics"
Write-Host "PHASE03F_ALREADY_PATCHED=$AlreadyPatched"

if (-not ($SafeEnter -and $CurrentExit -and $ReloadKeyMarker -and $ReloadDiagnostics)) {
    Stop-Gate "CURRENT_SOURCE_NOT_PHASE03E_EXPECTED_STATE" 12
}
if ($AlreadyPatched) {
    Stop-Gate "PHASE03F_PATCH_ALREADY_PRESENT_REVIEW_BEFORE_RERUN" 13
}

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 14
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\Phase03F_$Stamp"
$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\Phase03F_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

Copy-Item -LiteralPath $V2Cpp -Destination (Join-Path $BackupRoot "ASPlayerCharacterV2.cpp.before_phase03f") -Force
Copy-Item -LiteralPath $DefaultGameIni -Destination (Join-Path $BackupRoot "DefaultGame.ini.before_phase03f") -Force
Write-Host "BACKUP_ROOT=$BackupRoot"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CREATE / VERIFY REAL ASWW RIFLE DEFINITION DATA ASSET" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Py = Join-Path $EvidenceRoot "create_rifle_definition.py"
$PyLog = Join-Path $EvidenceRoot "create_rifle_definition.log"

$PyText = @'
import unreal

asset_path = "/Game/Weapons/Definitions/DA_ASWW_Rifle_01"
asset_name = "DA_ASWW_Rifle_01"
package_path = "/Game/Weapons/Definitions"

cls = unreal.load_class(None, "/Script/ArabiaStrikeWorldWar.ASWeaponDefinition")
print(f"ASWW_P03F_CLASS_LOAD={cls is not None}")
if cls is None:
    raise RuntimeError("ASWeaponDefinition class could not be loaded")

if unreal.EditorAssetLibrary.does_asset_exist(asset_path):
    asset = unreal.EditorAssetLibrary.load_asset(asset_path)
    print("ASWW_P03F_ASSET_CREATED=False")
else:
    factory = unreal.DataAssetFactory()
    factory.set_editor_property("data_asset_class", cls)
    tools = unreal.AssetToolsHelpers.get_asset_tools()
    asset = tools.create_asset(asset_name, package_path, cls, factory)
    print(f"ASWW_P03F_ASSET_CREATED={asset is not None}")

if asset is None:
    raise RuntimeError("Failed to create/load DA_ASWW_Rifle_01")

# Explicit ASWW rifle baseline. These are real gameplay values, not visual-only placeholders.
asset.set_editor_property("weapon_id", "RIFLE_01")
asset.set_editor_property("damage", 24.0)
asset.set_editor_property("range", 20000.0)
asset.set_editor_property("rounds_per_minute", 720.0)
asset.set_editor_property("spread_degrees", 0.6)
asset.set_editor_property("magazine_size", 30)
asset.set_editor_property("reload_seconds", 1.8)

saved = unreal.EditorAssetLibrary.save_loaded_asset(asset, only_if_is_dirty=False)
loaded = unreal.EditorAssetLibrary.load_asset(asset_path)

print(f"ASWW_P03F_ASSET_SAVE={saved}")
print(f"ASWW_P03F_ASSET_LOAD={loaded is not None}")
print(f"ASWW_P03F_ASSET_CLASS={loaded.get_class().get_name() if loaded else 'NONE'}")
if loaded:
    print(f"ASWW_P03F_MAGAZINE_SIZE={loaded.get_editor_property('magazine_size')}")
    print(f"ASWW_P03F_RELOAD_SECONDS={loaded.get_editor_property('reload_seconds')}")
print("ASWW_P03F_PY_DONE=True")
'@

[IO.File]::WriteAllText($Py, $PyText, [Text.UTF8Encoding]::new($false))
$PyForward = $Py.Replace('\','/')

& $EditorCmd `
    $ProjectFile `
    "-unattended" "-nop4" "-nosplash" "-NullRHI" "-stdout" "-FullStdOutLogOutput" `
    "-ExecutePythonScript=$PyForward" `
    2>&1 | Tee-Object -FilePath $PyLog | Out-Host

$PyExit = $LASTEXITCODE
$PyTextOut = Get-Content -Raw -LiteralPath $PyLog

$PyDone = $PyTextOut -match "ASWW_P03F_PY_DONE=True"
$ClassLoad = $PyTextOut -match "ASWW_P03F_CLASS_LOAD=True"
$AssetLoad = $PyTextOut -match "ASWW_P03F_ASSET_LOAD=True"
$PyError = $PyTextOut -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)|RuntimeError:"
$Fatal = $PyTextOut -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

Write-Host "WEAPON_DEF_PY_EXIT=$PyExit"
Write-Host "WEAPON_DEF_CLASS_LOAD=$ClassLoad"
Write-Host "WEAPON_DEF_ASSET_LOAD=$AssetLoad"
Write-Host "WEAPON_DEF_PY_DONE=$PyDone"

if ($PyExit -ne 0 -or -not $PyDone -or -not $ClassLoad -or -not $AssetLoad -or $PyError -or $Fatal) {
    Stop-Gate "WEAPON_DEFINITION_ASSET_CREATION_NOT_PROVEN" 20
}

$DefinitionUasset = Join-Path $ProjectRoot "Content\Weapons\Definitions\DA_ASWW_Rifle_01.uasset"
$DefinitionExists = Test-Path -LiteralPath $DefinitionUasset -PathType Leaf
Write-Host "WEAPON_DEFINITION_UASSET_EXISTS=$DefinitionExists"
if (-not $DefinitionExists) {
    Stop-Gate "WEAPON_DEFINITION_UASSET_NOT_FOUND_ON_DISK" 21
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PATCH DEFAULT RIFLE LOADOUT + ROBUST Z EXIT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Includes required for the real DataAsset loadout path.
if ($V2 -notmatch '#include "Combat/ASWeaponDefinition.h"') {
    $Anchor = '#include "Player/ASPlayerCharacterV2.h"'
    if ($V2 -notmatch [regex]::Escape($Anchor)) {
        Stop-Gate "V2_INCLUDE_ANCHOR_NOT_FOUND" 22
    }
    $V2 = $V2.Replace(
        $Anchor,
        $Anchor + "`r`n" +
        '#include "Combat/ASWeaponDefinition.h"' + "`r`n" +
        '#include "Combat/ASWeaponInventoryComponent.h"'
    )
}

# Add the real rifle definition to Inventory on authority in BeginPlay.
$BeginNeedle = "Super::BeginPlay();"
if ($V2.IndexOf($BeginNeedle, [StringComparison]::Ordinal) -lt 0) {
    Stop-Gate "BEGINPLAY_SUPER_NOT_FOUND" 23
}

$BeginInsert = @'
Super::BeginPlay();

    // ASWW_PHASE03F_DEFAULT_RIFLE_LOADOUT_BEGIN
    if (HasAuthority() && Inventory)
    {
        UASWeaponDefinition* RifleDefinition = LoadObject<UASWeaponDefinition>(
            nullptr,
            TEXT("/Game/Weapons/Definitions/DA_ASWW_Rifle_01.DA_ASWW_Rifle_01"));

        if (RifleDefinition)
        {
            const bool bLoadoutAccepted = Inventory->AddWeapon(RifleDefinition, true);
            UE_LOG(
                LogTemp,
                Warning,
                TEXT("ASWW_QA_RIFLE_DEFINITION_EQUIP load=1 accepted=%d asset=%s"),
                bLoadoutAccepted ? 1 : 0,
                *GetNameSafe(RifleDefinition));
        }
        else
        {
            UE_LOG(LogTemp, Error, TEXT("ASWW_QA_RIFLE_DEFINITION_EQUIP load=0 accepted=0 asset=NONE"));
        }
    }
    // ASWW_PHASE03F_DEFAULT_RIFLE_LOADOUT_END
'@

$V2 = $V2.Replace($BeginNeedle, $BeginInsert)

# Replace ExitProne with an unconditional engine uncrouch.
$ExitPattern = '(?ms)void\s+AASPlayerCharacterV2::ExitProne\(\)\s*\{.*?^\}'
$ExitMatches = [regex]::Matches($V2, $ExitPattern)
if ($ExitMatches.Count -ne 1) {
    Stop-Gate "EXPECTED_ONE_EXITPRONE_FOUND_$($ExitMatches.Count)" 24
}

$ExitReplacement = @'
void AASPlayerCharacterV2::ExitProne()
{
    // State first, then request the engine-managed capsule recovery.
    // Calling UnCrouch unconditionally avoids a stale bIsCrouched timing gate.
    MovementStance = EASMovementStance::Standing;
    bSprintHeldV2 = false;

    if (UCharacterMovementComponent* Move = GetCharacterMovement())
    {
        Move->MaxWalkSpeedCrouched = CrouchMoveSpeed;
    }

    UnCrouch(false);
    UpdateMovementProfile();

    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_QA_Z_EXIT_REQUEST crouchedNow=%d capsuleHalfHeight=%.2f"),
        bIsCrouched ? 1 : 0,
        GetCapsuleComponent() ? GetCapsuleComponent()->GetUnscaledCapsuleHalfHeight() : -1.f);
}
'@

$V2 = [regex]::Replace($V2, $ExitPattern, $ExitReplacement, 1)

# Add a small consistency guard: only Standing+still-crouched gets an UnCrouch retry.
$TickPattern = '(?ms)void\s+AASPlayerCharacterV2::Tick\(float\s+DeltaSeconds\)\s*\{.*?^\}'
$TickMatches = [regex]::Matches($V2, $TickPattern)
if ($TickMatches.Count -ne 1) {
    Stop-Gate "EXPECTED_ONE_TICK_FOUND_$($TickMatches.Count)" 25
}

$TickReplacement = @'
void AASPlayerCharacterV2::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);

    if (MovementStance == EASMovementStance::Standing && bIsCrouched)
    {
        UnCrouch(false);
    }

    UpdateCamera(DeltaSeconds);
}
'@

$V2 = [regex]::Replace($V2, $TickPattern, $TickReplacement, 1)

# Add enter marker without changing the safe crouch behavior.
$EnterMarkerNeedle = "MovementStance = EASMovementStance::Prone;`r`n    bSprintHeldV2 = false;"
if ($V2.IndexOf($EnterMarkerNeedle, [StringComparison]::Ordinal) -ge 0) {
    $EnterMarkerReplacement = @'
MovementStance = EASMovementStance::Prone;
    bSprintHeldV2 = false;

    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_QA_Z_ENTER crouchedNow=%d capsuleHalfHeight=%.2f"),
        bIsCrouched ? 1 : 0,
        GetCapsuleComponent() ? GetCapsuleComponent()->GetUnscaledCapsuleHalfHeight() : -1.f);
'@
    $V2 = $V2.Replace($EnterMarkerNeedle, $EnterMarkerReplacement)
}
elseif ($V2 -notmatch "ASWW_QA_Z_ENTER") {
    Stop-Gate "ENTER_PRONE_MARKER_INSERTION_POINT_NOT_FOUND" 26
}

# Make the rifle definition directory an explicit cooked content root because
# the runtime load uses a path and not a reflected UPROPERTY reference.
$AlwaysCookLine = '+DirectoriesToAlwaysCook=(Path="/Game/Weapons/Definitions")'
$IniLines = $GameIni -split "`r?`n"
$FilteredIni = New-Object System.Collections.Generic.List[string]
foreach ($Line in $IniLines) {
    if ($Line.Trim() -eq $AlwaysCookLine) { continue }
    $FilteredIni.Add($Line)
}
$GameIni = ($FilteredIni -join "`r`n").TrimEnd() + "`r`n" + $AlwaysCookLine + "`r`n"

Write-Utf8Bom $V2Cpp $V2
Write-Utf8Bom $DefaultGameIni $GameIni

$V2Disk = Get-Content -Raw -LiteralPath $V2Cpp
$GameIniDisk = Get-Content -Raw -LiteralPath $DefaultGameIni

$LoadoutPatch = $V2Disk -match "ASWW_PHASE03F_DEFAULT_RIFLE_LOADOUT_BEGIN"
$LoadObjectPath = $V2Disk -match "/Game/Weapons/Definitions/DA_ASWW_Rifle_01.DA_ASWW_Rifle_01"
$UnconditionalExit = $V2Disk -match 'void\s+AASPlayerCharacterV2::ExitProne\(\)[\s\S]{0,500}UnCrouch\(false\)'
$StandingGuard = $V2Disk -match 'MovementStance == EASMovementStance::Standing && bIsCrouched'
$AlwaysCookCount = ([regex]::Matches($GameIniDisk, [regex]::Escape($AlwaysCookLine))).Count

Write-Host "REAL_RIFLE_LOADOUT_PATCH=$LoadoutPatch"
Write-Host "REAL_RIFLE_LOADOBJECT_PATH=$LoadObjectPath"
Write-Host "Z_EXIT_UNCONDITIONAL_UNCROUCH=$UnconditionalExit"
Write-Host "Z_STANDING_UNCROUCH_GUARD=$StandingGuard"
Write-Host "WEAPON_DEFINITION_ALWAYS_COOK_COUNT=$AlwaysCookCount"

if (-not ($LoadoutPatch -and $LoadObjectPath -and $UnconditionalExit -and $StandingGuard)) {
    Stop-Gate "SOURCE_POST_PATCH_VERIFY_FAILED" 27
}
if ($AlwaysCookCount -ne 1) {
    Stop-Gate "ALWAYS_COOK_LINE_COUNT_$AlwaysCookCount" 28
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 29
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " EDITOR BUILD — SERIAL / NO UBA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$EditorLog = Join-Path $EvidenceRoot "editor_build.log"
$EditorArgs = @(
    "ArabiaStrikeWorldWarEditor",
    "Win64",
    "Development",
    "-Project=`"$ProjectFile`"",
    "-WaitMutex",
    "-NoHotReloadFromIDE",
    "-MaxParallelActions=1",
    "-NoUBA"
)

& $BuildBat @EditorArgs 2>&1 | Tee-Object -FilePath $EditorLog | Out-Host
$EditorExit = $LASTEXITCODE
$EditorSucceeded = (Get-Content -Raw -LiteralPath $EditorLog) -match "Result:\s*Succeeded"

Write-Host "EDITOR_BUILD_EXIT=$EditorExit"
Write-Host "EDITOR_RESULT_SUCCEEDED_SEEN=$EditorSucceeded"

if ($EditorExit -ne 0 -or -not $EditorSucceeded) {
    Get-Content -LiteralPath $EditorLog -Tail 320
    $Code = 30
    if ($EditorExit -gt 0) { $Code = $EditorExit }
    Stop-Gate "EDITOR_BUILD_FAILED_EXIT_$EditorExit" $Code
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " GAME BUILD — SERIAL / NO UBA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$GameLog = Join-Path $EvidenceRoot "game_build.log"
$GameArgs = @(
    "ArabiaStrikeWorldWar",
    "Win64",
    "Development",
    "-Project=`"$ProjectFile`"",
    "-WaitMutex",
    "-MaxParallelActions=1",
    "-NoUBA"
)

& $BuildBat @GameArgs 2>&1 | Tee-Object -FilePath $GameLog | Out-Host
$GameExit = $LASTEXITCODE
$GameSucceeded = (Get-Content -Raw -LiteralPath $GameLog) -match "Result:\s*Succeeded"

Write-Host "GAME_BUILD_EXIT=$GameExit"
Write-Host "GAME_RESULT_SUCCEEDED_SEEN=$GameSucceeded"

if ($GameExit -ne 0 -or -not $GameSucceeded) {
    Get-Content -LiteralPath $GameLog -Tail 320
    $Code = 31
    if ($GameExit -gt 0) { $Code = $GameExit }
    Stop-Gate "GAME_BUILD_FAILED_EXIT_$GameExit" $Code
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COOK + STAGE + PACKAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRE_PHASE03F_$Stamp"
    Move-Item -LiteralPath $StageRoot -Destination $OldStage
    Write-Host "OLD_STAGE_MOVED=$OldStage"
}

New-Item -ItemType Directory -Force -Path $ArchiveRoot | Out-Null

$PackageLog = Join-Path $EvidenceRoot "package.log"
$UATArgs = @(
    "BuildCookRun",
    "-project=`"$ProjectFile`"",
    "-noP4",
    "-platform=Win64",
    "-clientconfig=Development",
    "-skipbuild",
    "-cook",
    "-stage",
    "-stagingdirectory=`"$StageRoot`"",
    "-pak",
    "-package",
    "-archive",
    "-archivedirectory=`"$ArchiveRoot`"",
    "-utf8output"
)

& $RunUAT @UATArgs 2>&1 | Tee-Object -FilePath $PackageLog | Out-Host
$PackageExit = $LASTEXITCODE
Write-Host "PACKAGE_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Get-Content -LiteralPath $PackageLog -Tail 380
    $Code = 32
    if ($PackageExit -gt 0) { $Code = $PackageExit }
    Stop-Gate "PACKAGE_FAILED_EXIT_$PackageExit" $Code
}

$Exe = Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

$Containers = @(
    Get-ChildItem -LiteralPath $StageRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @(".pak",".utoc",".ucas") }
)

if (-not $Exe) { Stop-Gate "PACKAGED_EXE_NOT_FOUND" 33 }
if ($Containers.Count -eq 0) { Stop-Gate "PACKAGED_CONTAINERS_NOT_FOUND" 34 }

Write-Host "PACKAGED_EXE=$($Exe.FullName)"
Write-Host "PACKAGED_CONTAINER_COUNT=$($Containers.Count)"

Write-Host ""
Write-Host "PHASE_03F_Z_RELOAD_RUNTIME_FIX=PASS" -ForegroundColor Green
Write-Host "REAL_WEAPON_DEFINITION_ASSET=DA_ASWW_Rifle_01" -ForegroundColor Green
Write-Host "RUNTIME_LOADOUT_EQUIP=INSTALLED" -ForegroundColor Green
Write-Host "Z_EXIT_RECOVERY=UNCONDITIONAL_UNCROUCH_PLUS_STANDING_GUARD" -ForegroundColor Green
Write-Host "TRUE_PRONE_ANIMATION=NOT_YET_IMPLEMENTED" -ForegroundColor Yellow
Write-Host "NEXT_GATE=RUN_PHASE_03F_Z_RELOAD_RUNTIME_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
