[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$StageRoot = "D:\ASWW_STAGE",
    [string]$ArchiveRoot = "D:\ASWW_ARCHIVE\Phase03E_Z_Reload"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_03E_Z_RELOAD_FIX=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "QA_RELOAD_TELEMETRY=TEMPORARY_DO_NOT_COMMIT" -ForegroundColor Yellow
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
$BuildBat = Join-Path $UERoot "Engine\Build\BatchFiles\Build.bat"
$RunUAT = Join-Path $UERoot "Engine\Build\BatchFiles\RunUAT.bat"
$V2Cpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASPlayerCharacterV2.cpp"
$WeaponCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Combat\ASWeaponComponent.cpp"
$InputIni = Join-Path $ProjectRoot "Config\DefaultInput.ini"

foreach ($Required in @($ProjectFile,$BuildBat,$RunUAT,$V2Cpp,$WeaponCpp,$InputIni)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

$V2 = Get-Content -Raw -LiteralPath $V2Cpp
$Weapon = Get-Content -Raw -LiteralPath $WeaponCpp
$Input = Get-Content -Raw -LiteralPath $InputIni

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY CURRENT PLAYER BASELINE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Unarmed = $V2 -match "/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed"
$Rifle = $V2 -match "/Game/Weapons/Rifle/Meshes/SKM_Rifle"
$ProneDirectCapsule = $V2 -match 'SetCapsuleHalfHeight\('
$ReloadBinding = $V2 -match 'BindAction\("Reload",\s*IE_Pressed,\s*this,\s*&AASPlayerCharacterV2::ReloadPressedV2\)'
$ReloadWrapper = $V2 -match 'void\s+AASPlayerCharacterV2::ReloadPressedV2\(\)'

Write-Host "ABP_UNARMED_SELECTED=$Unarmed"
Write-Host "SKM_RIFLE_SELECTED=$Rifle"
Write-Host "DIRECT_PRONE_CAPSULE_RESIZE_PRESENT=$ProneDirectCapsule"
Write-Host "RELOAD_BINDING_PRESENT=$ReloadBinding"
Write-Host "RELOAD_WRAPPER_PRESENT=$ReloadWrapper"

if (-not ($Unarmed -and $Rifle -and $ReloadBinding -and $ReloadWrapper)) {
    Stop-Gate "PLAYER_BASELINE_NOT_AS_EXPECTED" 12
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\Phase03E_Z_Reload_$Stamp"
$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\Phase03E_Z_Reload_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

Copy-Item -LiteralPath $V2Cpp -Destination (Join-Path $BackupRoot "ASPlayerCharacterV2.cpp.before_phase03e") -Force
Copy-Item -LiteralPath $WeaponCpp -Destination (Join-Path $BackupRoot "ASWeaponComponent.cpp.before_phase03e") -Force
Copy-Item -LiteralPath $InputIni -Destination (Join-Path $BackupRoot "DefaultInput.ini.before_phase03e") -Force

Write-Host "BACKUP_ROOT=$BackupRoot"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REMOVE OLD PHASE03D QA MARKERS IF PRESENT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Restore clean ReloadPressedV2 body regardless of prior narrow QA marker installation.
$ReloadFunctionPattern = '(?ms)void\s+AASPlayerCharacterV2::ReloadPressedV2\(\)\s*\{.*?^\}'
$ReloadFunctionClean = @'
void AASPlayerCharacterV2::ReloadPressedV2()
{
    UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_RELOAD_KEY_PRESSED"));
    Reload();
}
'@

$ReloadFunctionMatches = [regex]::Matches($V2, $ReloadFunctionPattern)
if ($ReloadFunctionMatches.Count -ne 1) {
    Stop-Gate "EXPECTED_EXACTLY_ONE_RELOADPRESSEDV2_FUNCTION_FOUND_$($ReloadFunctionMatches.Count)" 20
}
$V2 = [regex]::Replace($V2, $ReloadFunctionPattern, $ReloadFunctionClean, 1)

# Remove the previous jump-only telemetry block if it exists.
$JumpLogPattern = '(?ms)\s*UE_LOG\(\s*LogTemp,\s*Warning,\s*TEXT\("ASWW_QA_JUMP_INPUT.*?\);\s*'
$V2 = [regex]::Replace($V2, $JumpLogPattern, "`r`n    ")

Write-Host "OLD_JUMP_QA_MARKER_REMAINS=$($V2 -match 'ASWW_QA_JUMP_INPUT')"
Write-Host "NEW_RELOAD_KEY_MARKER_INSTALLED=$($V2 -match 'ASWW_QA_RELOAD_KEY_PRESSED')"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FIX Z: USE UE CROUCH PIPELINE INSTEAD OF RAW CAPSULE SHRINK" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$EnterPattern = '(?ms)void\s+AASPlayerCharacterV2::EnterProne\(\)\s*\{.*?^\}'
$ExitPattern  = '(?ms)void\s+AASPlayerCharacterV2::ExitProne\(\)\s*\{.*?^\}'

$EnterReplacement = @'
void AASPlayerCharacterV2::EnterProne()
{
    GetWorldTimerManager().ClearTimer(SlideTimerHandle);

    // Phase 03E safety correction:
    // Do NOT resize the capsule directly. ACharacter crouch manages capsule,
    // floor/base preservation and mesh translation without pushing Manny below ground.
    if (MovementStance == EASMovementStance::Sliding)
    {
        StopSlide();
    }

    if (!bIsCrouched)
    {
        Crouch(false);
    }

    MovementStance = EASMovementStance::Prone;
    bSprintHeldV2 = false;
    UpdateMovementProfile();
}
'@

$ExitReplacement = @'
void AASPlayerCharacterV2::ExitProne()
{
    // Until the dedicated prone animation/IK layer exists, exit through the
    // engine crouch pipeline as well. This prevents floor clipping and capsule pops.
    if (bIsCrouched)
    {
        UnCrouch(false);
    }

    MovementStance = EASMovementStance::Standing;
    UpdateMovementProfile();
}
'@

$EnterMatches = [regex]::Matches($V2, $EnterPattern)
$ExitMatches = [regex]::Matches($V2, $ExitPattern)

if ($EnterMatches.Count -ne 1) {
    Stop-Gate "EXPECTED_ONE_ENTERPRONE_FOUND_$($EnterMatches.Count)" 21
}
if ($ExitMatches.Count -ne 1) {
    Stop-Gate "EXPECTED_ONE_EXITPRONE_FOUND_$($ExitMatches.Count)" 22
}

$V2 = [regex]::Replace($V2, $EnterPattern, $EnterReplacement, 1)
$V2 = [regex]::Replace($V2, $ExitPattern, $ExitReplacement, 1)

# Ensure prone speed applies while CharacterMovement is technically crouched.
$ProneProfilePattern = '(?ms)if\s*\(MovementStance\s*==\s*EASMovementStance::Prone\)\s*\{\s*Move->MaxWalkSpeed\s*=\s*ProneMoveSpeed;\s*return;\s*\}'
$ProneProfileReplacement = @'
if (MovementStance == EASMovementStance::Prone)
    {
        Move->MaxWalkSpeed = ProneMoveSpeed;
        Move->MaxWalkSpeedCrouched = ProneMoveSpeed;
        return;
    }
'@

if ([regex]::Matches($V2, $ProneProfilePattern).Count -ne 1) {
    Stop-Gate "PRONE_MOVEMENT_PROFILE_SHAPE_NOT_FOUND" 23
}
$V2 = [regex]::Replace($V2, $ProneProfilePattern, $ProneProfileReplacement, 1)

# Ensure ordinary crouch restores its own speed after exiting prone.
$CrouchProfilePattern = '(?ms)if\s*\(MovementStance\s*==\s*EASMovementStance::Crouched\)\s*\{\s*Move->MaxWalkSpeed\s*=\s*CrouchMoveSpeed;\s*Move->MaxWalkSpeedCrouched\s*=\s*CrouchMoveSpeed;\s*return;\s*\}'
if ([regex]::Matches($V2, $CrouchProfilePattern).Count -ne 1) {
    Stop-Gate "CROUCH_MOVEMENT_PROFILE_SHAPE_NOT_FOUND" 24
}

Write-Host "DIRECT_PRONE_CAPSULE_RESIZE_AFTER_PATCH=$($V2 -match 'EnterProne\(\)[\s\S]{0,1000}SetCapsuleHalfHeight')"
Write-Host "PRONE_USES_CROUCH_PIPELINE=$($V2 -match 'EnterProne\(\)[\s\S]{0,800}Crouch\(false\)')"
Write-Host "PRONE_CROUCHED_SPEED_SET=$($V2 -match 'MaxWalkSpeedCrouched = ProneMoveSpeed')"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CANONICALIZE R -> RELOAD INPUT MAPPING" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$ReloadRLine = '+ActionMappings=(ActionName="Reload",bShift=False,bCtrl=False,bAlt=False,bCmd=False,Key=R)'
$InputLines = $Input -split "`r?`n"
$Filtered = New-Object System.Collections.Generic.List[string]
foreach ($Line in $InputLines) {
    if ($Line -match '^\+ActionMappings=\(ActionName="Reload".*Key=R\)\s*$') {
        continue
    }
    $Filtered.Add($Line)
}

$Input = ($Filtered -join "`r`n").TrimEnd() + "`r`n" + $ReloadRLine + "`r`n"
$ReloadRCount = ([regex]::Matches($Input, [regex]::Escape($ReloadRLine))).Count
Write-Host "RELOAD_R_MAPPING_COUNT=$ReloadRCount"

if ($ReloadRCount -ne 1) {
    Stop-Gate "FAILED_TO_CANONICALIZE_RELOAD_R_MAPPING" 25
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ADD TEMPORARY RELOAD ACCEPT/REJECT DIAGNOSTICS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$ServerReloadPattern = '(?ms)void\s+UASWeaponComponent::ServerReload_Implementation\(\)\s*\{.*?^\}'
$FinishReloadPattern = '(?ms)void\s+UASWeaponComponent::FinishReload\(\)\s*\{.*?^\}'

$ServerReloadReplacement = @'
void UASWeaponComponent::ServerReload_Implementation()
{
    if (!WeaponDefinition)
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_RELOAD_REJECT_NO_DEFINITION"));
        return;
    }

    if (bReloading)
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_RELOAD_REJECT_ALREADY_RELOADING"));
        return;
    }

    if (Ammo.Magazine >= WeaponDefinition->MagazineSize)
    {
        UE_LOG(
            LogTemp,
            Warning,
            TEXT("ASWW_QA_RELOAD_REJECT_FULL_MAG mag=%d size=%d reserve=%d"),
            Ammo.Magazine,
            WeaponDefinition->MagazineSize,
            Ammo.Reserve);
        return;
    }

    if (Ammo.Reserve <= 0)
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_RELOAD_REJECT_NO_RESERVE mag=%d"), Ammo.Magazine);
        return;
    }

    if (!GetWorld())
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_RELOAD_REJECT_NO_WORLD"));
        return;
    }

    bReloading = true;

    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_QA_RELOAD_ACCEPTED mag=%d reserve=%d seconds=%.2f"),
        Ammo.Magazine,
        Ammo.Reserve,
        WeaponDefinition->ReloadSeconds);

    GetWorld()->GetTimerManager().SetTimer(
        ReloadTimer,
        this,
        &UASWeaponComponent::FinishReload,
        WeaponDefinition->ReloadSeconds,
        false);
}
'@

$FinishReloadReplacement = @'
void UASWeaponComponent::FinishReload()
{
    if (!WeaponDefinition)
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_RELOAD_FINISH_ABORT_NO_DEFINITION"));
        return;
    }

    const int32 Need = WeaponDefinition->MagazineSize - Ammo.Magazine;
    const int32 Take = FMath::Min(Need, Ammo.Reserve);

    Ammo.Magazine += Take;
    Ammo.Reserve -= Take;
    bReloading = false;
    OnRep_Ammo();

    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_QA_RELOAD_FINISHED mag=%d reserve=%d"),
        Ammo.Magazine,
        Ammo.Reserve);
}
'@

if ([regex]::Matches($Weapon, $ServerReloadPattern).Count -ne 1) {
    Stop-Gate "SERVER_RELOAD_FUNCTION_SHAPE_NOT_FOUND" 26
}
if ([regex]::Matches($Weapon, $FinishReloadPattern).Count -ne 1) {
    Stop-Gate "FINISH_RELOAD_FUNCTION_SHAPE_NOT_FOUND" 27
}

$Weapon = [regex]::Replace($Weapon, $ServerReloadPattern, $ServerReloadReplacement, 1)
$Weapon = [regex]::Replace($Weapon, $FinishReloadPattern, $FinishReloadReplacement, 1)

Write-Utf8Bom $V2Cpp $V2
Write-Utf8Bom $WeaponCpp $Weapon
Write-Utf8Bom $InputIni $Input

$V2Disk = Get-Content -Raw -LiteralPath $V2Cpp
$WeaponDisk = Get-Content -Raw -LiteralPath $WeaponCpp
$InputDisk = Get-Content -Raw -LiteralPath $InputIni

Write-Host "Z_RAW_CAPSULE_SHRINK_REMOVED=$(-not ($V2Disk -match 'EnterProne\(\)[\s\S]{0,1000}SetCapsuleHalfHeight'))"
Write-Host "Z_SAFE_CROUCH_PIPELINE_INSTALLED=$($V2Disk -match 'EnterProne\(\)[\s\S]{0,800}Crouch\(false\)')"
Write-Host "RELOAD_KEY_MARKER_INSTALLED=$($V2Disk -match 'ASWW_QA_RELOAD_KEY_PRESSED')"
Write-Host "RELOAD_ACCEPT_MARKER_INSTALLED=$($WeaponDisk -match 'ASWW_QA_RELOAD_ACCEPTED')"
Write-Host "RELOAD_FINISH_MARKER_INSTALLED=$($WeaponDisk -match 'ASWW_QA_RELOAD_FINISHED')"
Write-Host "RELOAD_R_MAPPING_PRESENT=$($InputDisk -match [regex]::Escape($ReloadRLine))"

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 28
}

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 29
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
    Get-Content -LiteralPath $EditorLog -Tail 300
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
    Get-Content -LiteralPath $GameLog -Tail 300
    $Code = 31
    if ($GameExit -gt 0) { $Code = $GameExit }
    Stop-Gate "GAME_BUILD_FAILED_EXIT_$GameExit" $Code
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COOK + STAGE + PACKAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRE_PHASE03E_$Stamp"
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
    Get-Content -LiteralPath $PackageLog -Tail 360
    $Code = 32
    if ($PackageExit -gt 0) { $Code = $PackageExit }
    Stop-Gate "PACKAGE_FAILED_EXIT_$PackageExit" $Code
}

$Exe = Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $Exe) {
    Stop-Gate "PACKAGED_EXE_NOT_FOUND" 33
}

Write-Host "PACKAGED_EXE=$($Exe.FullName)"

Write-Host ""
Write-Host "PHASE_03E_Z_RELOAD_FIX=PASS" -ForegroundColor Green
Write-Host "Z_GROUND_CLIP_FIX=ENGINE_CROUCH_PIPELINE" -ForegroundColor Green
Write-Host "TRUE_PRONE_ANIMATION=NOT_YET_IMPLEMENTED" -ForegroundColor Yellow
Write-Host "R_RELOAD_MAPPING=CANONICAL_R" -ForegroundColor Green
Write-Host "RELOAD_DIAGNOSTICS=TEMPORARY_QA_ONLY" -ForegroundColor Yellow
Write-Host "NEXT_GATE=RUN_PHASE_03E_Z_RELOAD_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
