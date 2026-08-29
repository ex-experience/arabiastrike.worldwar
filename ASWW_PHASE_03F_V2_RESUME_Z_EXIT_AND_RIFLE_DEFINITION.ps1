[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$StageRoot = "D:\ASWW_STAGE",
    [string]$ArchiveRoot = "D:\ASWW_ARCHIVE\Phase03F_V2_Z_Reload"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_03F_V2_Z_RELOAD_RUNTIME_FIX=STOPPED" -ForegroundColor Red
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
$DefaultGameIni = Join-Path $ProjectRoot "Config\DefaultGame.ini"
$DefinitionUasset = Join-Path $ProjectRoot "Content\Weapons\Definitions\DA_ASWW_Rifle_01.uasset"

foreach ($Required in @($ProjectFile,$EditorCmd,$BuildBat,$RunUAT,$V2Cpp,$DefaultGameIni,$DefinitionUasset)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

$V2 = Get-Content -Raw -LiteralPath $V2Cpp
$GameIni = Get-Content -Raw -LiteralPath $DefaultGameIni

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY PHASE 03E + CREATED RIFLE DEFINITION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Unarmed = $V2 -match "/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed"
$RifleMesh = $V2 -match "/Game/Weapons/Rifle/Meshes/SKM_Rifle"
$SafeZEnter = $V2 -match 'void\s+AASPlayerCharacterV2::EnterProne\(\)[\s\S]{0,1400}Crouch\(false\)'
$ReloadKey = $V2 -match "ASWW_QA_RELOAD_KEY_PRESSED"
$AlreadyPatched = $V2 -match "ASWW_PHASE03F_DEFAULT_RIFLE_LOADOUT_BEGIN"

Write-Host "ABP_UNARMED_SELECTED=$Unarmed"
Write-Host "SKM_RIFLE_SELECTED=$RifleMesh"
Write-Host "SAFE_Z_ENTER_PRESENT=$SafeZEnter"
Write-Host "RELOAD_KEY_DIAGNOSTIC_PRESENT=$ReloadKey"
Write-Host "RIFLE_DEFINITION_UASSET_EXISTS=True"
Write-Host "PHASE03F_SOURCE_PATCH_ALREADY_PRESENT=$AlreadyPatched"

if (-not ($Unarmed -and $RifleMesh -and $SafeZEnter -and $ReloadKey)) {
    Stop-Gate "CURRENT_SOURCE_NOT_PHASE03E_EXPECTED_STATE" 12
}
if ($AlreadyPatched) {
    Stop-Gate "PHASE03F_SOURCE_PATCH_ALREADY_PRESENT_REVIEW_BEFORE_RERUN" 13
}

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 14
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\Phase03F_V2_$Stamp"
$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\Phase03F_V2_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

Copy-Item -LiteralPath $V2Cpp -Destination (Join-Path $BackupRoot "ASPlayerCharacterV2.cpp.before_phase03f_v2") -Force
Copy-Item -LiteralPath $DefaultGameIni -Destination (Join-Path $BackupRoot "DefaultGame.ini.before_phase03f_v2") -Force
Write-Host "BACKUP_ROOT=$BackupRoot"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY RIFLE DEFINITION LOADS IN UE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Py = Join-Path $EvidenceRoot "verify_rifle_definition.py"
$PyLog = Join-Path $EvidenceRoot "verify_rifle_definition.log"

$PyText = @'
import unreal

asset_path = "/Game/Weapons/Definitions/DA_ASWW_Rifle_01"
asset = unreal.EditorAssetLibrary.load_asset(asset_path)

print(f"ASWW_P03F_V2_ASSET_LOAD={asset is not None}")
if asset:
    print(f"ASWW_P03F_V2_ASSET_CLASS={asset.get_class().get_name()}")
    print(f"ASWW_P03F_V2_MAGAZINE_SIZE={asset.get_editor_property('magazine_size')}")
    print(f"ASWW_P03F_V2_RELOAD_SECONDS={asset.get_editor_property('reload_seconds')}")
print("ASWW_P03F_V2_VERIFY_DONE=True")
'@

[IO.File]::WriteAllText($Py, $PyText, [Text.UTF8Encoding]::new($false))
$PyForward = $Py.Replace('\','/')

& $EditorCmd `
    $ProjectFile `
    "-unattended" "-nop4" "-nosplash" "-NullRHI" "-stdout" "-FullStdOutLogOutput" `
    "-ExecutePythonScript=$PyForward" `
    2>&1 | Tee-Object -FilePath $PyLog | Out-Host

$PyExit = $LASTEXITCODE
$PyOut = Get-Content -Raw -LiteralPath $PyLog
$AssetLoad = $PyOut -match "ASWW_P03F_V2_ASSET_LOAD=True"
$VerifyDone = $PyOut -match "ASWW_P03F_V2_VERIFY_DONE=True"
$PyError = $PyOut -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)|RuntimeError:"
$PyFatal = $PyOut -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

Write-Host "RIFLE_DEF_VERIFY_EXIT=$PyExit"
Write-Host "RIFLE_DEF_ASSET_LOAD=$AssetLoad"
Write-Host "RIFLE_DEF_VERIFY_DONE=$VerifyDone"

if ($PyExit -ne 0 -or -not $AssetLoad -or -not $VerifyDone -or $PyError -or $PyFatal) {
    Stop-Gate "RIFLE_DEFINITION_LOAD_NOT_PROVEN" 20
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PATCH DEFAULT RIFLE LOADOUT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if ($V2 -notmatch '#include "Combat/ASWeaponDefinition.h"') {
    $IncludeAnchor = '#include "Player/ASPlayerCharacterV2.h"'
    if ($V2.IndexOf($IncludeAnchor, [StringComparison]::Ordinal) -lt 0) {
        Stop-Gate "V2_INCLUDE_ANCHOR_NOT_FOUND" 21
    }

    $V2 = $V2.Replace(
        $IncludeAnchor,
        $IncludeAnchor + "`r`n" +
        '#include "Combat/ASWeaponDefinition.h"' + "`r`n" +
        '#include "Combat/ASWeaponInventoryComponent.h"'
    )
}

# Insert only into AASPlayerCharacterV2::BeginPlay, not a generic Super::BeginPlay elsewhere.
$BeginPattern = '(?ms)(void\s+AASPlayerCharacterV2::BeginPlay\(\)\s*\{\s*Super::BeginPlay\(\);)'
$BeginMatches = [regex]::Matches($V2, $BeginPattern)
Write-Host "V2_BEGINPLAY_MATCH_COUNT=$($BeginMatches.Count)"
if ($BeginMatches.Count -ne 1) {
    Stop-Gate "EXPECTED_ONE_V2_BEGINPLAY_MATCH_$($BeginMatches.Count)" 22
}

$LoadoutBlock = @'
$1

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
            UE_LOG(
                LogTemp,
                Error,
                TEXT("ASWW_QA_RIFLE_DEFINITION_EQUIP load=0 accepted=0 asset=NONE"));
        }
    }
    // ASWW_PHASE03F_DEFAULT_RIFLE_LOADOUT_END
'@

$V2 = [regex]::Replace($V2, $BeginPattern, $LoadoutBlock, 1)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PATCH Z EXIT — STATE FIRST + UNCONDITIONAL UNCROUCH" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$ExitPattern = '(?ms)void\s+AASPlayerCharacterV2::ExitProne\(\)\s*\{.*?^\}'
$ExitMatches = [regex]::Matches($V2, $ExitPattern)
Write-Host "EXIT_PRONE_MATCH_COUNT=$($ExitMatches.Count)"

if ($ExitMatches.Count -ne 1) {
    Stop-Gate "EXPECTED_ONE_EXITPRONE_FOUND_$($ExitMatches.Count)" 23
}

$ExitReplacement = @'
void AASPlayerCharacterV2::ExitProne()
{
    // Recover gameplay state before asking CharacterMovement to restore the capsule.
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

# Add a recovery guard to the existing Tick body without replacing the whole function.
$TickSuperPattern = '(?ms)(void\s+AASPlayerCharacterV2::Tick\(float\s+DeltaSeconds\)\s*\{\s*Super::Tick\(DeltaSeconds\);)'
$TickMatches = [regex]::Matches($V2, $TickSuperPattern)
Write-Host "V2_TICK_MATCH_COUNT=$($TickMatches.Count)"

if ($TickMatches.Count -ne 1) {
    Stop-Gate "EXPECTED_ONE_V2_TICK_MATCH_$($TickMatches.Count)" 24
}

$TickBlock = @'
$1

    if (MovementStance == EASMovementStance::Standing && bIsCrouched)
    {
        UnCrouch(false);
    }
'@

$V2 = [regex]::Replace($V2, $TickSuperPattern, $TickBlock, 1)

# Robustly insert the Z-enter marker immediately after the Prone state assignment.
$EnterStatePattern = '(?m)(^\s*MovementStance\s*=\s*EASMovementStance::Prone\s*;\s*$)'
$EnterStateMatches = [regex]::Matches($V2, $EnterStatePattern)
Write-Host "PRONE_STATE_ASSIGNMENT_MATCH_COUNT=$($EnterStateMatches.Count)"

if ($EnterStateMatches.Count -lt 1) {
    Stop-Gate "PRONE_STATE_ASSIGNMENT_NOT_FOUND" 25
}

# Only patch the first assignment inside EnterProne. Scope by matching the full function.
$EnterFunctionPattern = '(?ms)void\s+AASPlayerCharacterV2::EnterProne\(\)\s*\{.*?^\}'
$EnterFunctionMatches = [regex]::Matches($V2, $EnterFunctionPattern)
if ($EnterFunctionMatches.Count -ne 1) {
    Stop-Gate "EXPECTED_ONE_ENTERPRONE_FOUND_$($EnterFunctionMatches.Count)" 26
}

$EnterFunction = $EnterFunctionMatches[0].Value
if ($EnterFunction -notmatch "ASWW_QA_Z_ENTER") {
    $ScopedStateMatches = [regex]::Matches($EnterFunction, $EnterStatePattern)
    if ($ScopedStateMatches.Count -ne 1) {
        Stop-Gate "ENTERPRONE_STATE_ASSIGNMENT_COUNT_$($ScopedStateMatches.Count)" 27
    }

    $EnterStateReplacement = @'
$1

    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_QA_Z_ENTER crouchedNow=%d capsuleHalfHeight=%.2f"),
        bIsCrouched ? 1 : 0,
        GetCapsuleComponent() ? GetCapsuleComponent()->GetUnscaledCapsuleHalfHeight() : -1.f);
'@

    $PatchedEnterFunction = [regex]::Replace(
        $EnterFunction,
        $EnterStatePattern,
        $EnterStateReplacement,
        1)

    $V2 = $V2.Remove($EnterFunctionMatches[0].Index, $EnterFunctionMatches[0].Length)
    $V2 = $V2.Insert($EnterFunctionMatches[0].Index, $PatchedEnterFunction)
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FORCE RIFLE DEFINITION INTO COOK" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

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
$IniDisk = Get-Content -Raw -LiteralPath $DefaultGameIni

$LoadoutPatch = $V2Disk -match "ASWW_PHASE03F_DEFAULT_RIFLE_LOADOUT_BEGIN"
$DefinitionPath = $V2Disk -match "/Game/Weapons/Definitions/DA_ASWW_Rifle_01.DA_ASWW_Rifle_01"
$ZEnterMarker = $V2Disk -match "ASWW_QA_Z_ENTER"
$ZExitMarker = $V2Disk -match "ASWW_QA_Z_EXIT_REQUEST"
$UnconditionalExit = $V2Disk -match 'void\s+AASPlayerCharacterV2::ExitProne\(\)[\s\S]{0,900}UnCrouch\(false\)'
$StandingGuard = $V2Disk -match 'MovementStance\s*==\s*EASMovementStance::Standing\s*&&\s*bIsCrouched'
$AlwaysCookCount = ([regex]::Matches($IniDisk, [regex]::Escape($AlwaysCookLine))).Count

Write-Host "REAL_RIFLE_LOADOUT_PATCH=$LoadoutPatch"
Write-Host "REAL_RIFLE_DEFINITION_PATH=$DefinitionPath"
Write-Host "Z_ENTER_MARKER=$ZEnterMarker"
Write-Host "Z_EXIT_MARKER=$ZExitMarker"
Write-Host "Z_EXIT_UNCONDITIONAL_UNCROUCH=$UnconditionalExit"
Write-Host "Z_STANDING_RECOVERY_GUARD=$StandingGuard"
Write-Host "WEAPON_DEFINITION_ALWAYS_COOK_COUNT=$AlwaysCookCount"

if (-not ($LoadoutPatch -and $DefinitionPath -and $ZEnterMarker -and $ZExitMarker -and $UnconditionalExit -and $StandingGuard)) {
    Stop-Gate "SOURCE_POST_PATCH_VERIFY_FAILED" 28
}
if ($AlwaysCookCount -ne 1) {
    Stop-Gate "ALWAYS_COOK_LINE_COUNT_$AlwaysCookCount" 29
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"

if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 30
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
    $Code = 31
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
    $Code = 32
    if ($GameExit -gt 0) { $Code = $GameExit }
    Stop-Gate "GAME_BUILD_FAILED_EXIT_$GameExit" $Code
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COOK + STAGE + PACKAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRE_PHASE03F_V2_$Stamp"
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
    $Code = 33
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

if (-not $Exe) { Stop-Gate "PACKAGED_EXE_NOT_FOUND" 34 }
if ($Containers.Count -eq 0) { Stop-Gate "PACKAGED_CONTAINERS_NOT_FOUND" 35 }

Write-Host "PACKAGED_EXE=$($Exe.FullName)"
Write-Host "PACKAGED_CONTAINER_COUNT=$($Containers.Count)"

Write-Host ""
Write-Host "PHASE_03F_V2_Z_RELOAD_RUNTIME_FIX=PASS" -ForegroundColor Green
Write-Host "RIFLE_DEFINITION_ASSET=VERIFIED_EXISTING" -ForegroundColor Green
Write-Host "RUNTIME_RIFLE_LOADOUT_EQUIP=INSTALLED" -ForegroundColor Green
Write-Host "Z_EXIT_RECOVERY=STATE_FIRST_UNCONDITIONAL_UNCROUCH_PLUS_GUARD" -ForegroundColor Green
Write-Host "TRUE_PRONE_ANIMATION=NOT_YET_IMPLEMENTED" -ForegroundColor Yellow
Write-Host "NEXT_GATE=RUN_PHASE_03F_Z_RELOAD_RUNTIME_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
