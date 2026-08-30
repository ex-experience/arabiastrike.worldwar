[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$StageRoot = "D:\ASWW_STAGE",
    [string]$ArchiveRoot = "D:\ASWW_ARCHIVE\Phase03E_Z_Reload_V2"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_03E_V2_Z_RELOAD_FIX=STOPPED" -ForegroundColor Red
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
Write-Host " VERIFY BASELINE BEFORE V2 PATCH" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Unarmed = $V2 -match "/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed"
$Rifle = $V2 -match "/Game/Weapons/Rifle/Meshes/SKM_Rifle"
$ReloadBinding = $V2 -match 'BindAction\("Reload",\s*IE_Pressed,\s*this,\s*&AASPlayerCharacterV2::ReloadPressedV2\)'
$ReloadWrapper = $V2 -match 'void\s+AASPlayerCharacterV2::ReloadPressedV2\(\)'
$OldServerReload = 'void UASWeaponComponent::ServerReload_Implementation(){if(!WeaponDefinition||bReloading||Ammo.Magazine>=WeaponDefinition->MagazineSize||Ammo.Reserve<=0||!GetWorld())return;bReloading=true;GetWorld()->GetTimerManager().SetTimer(ReloadTimer,this,&UASWeaponComponent::FinishReload,WeaponDefinition->ReloadSeconds,false);}'
$OldFinishReload = 'void UASWeaponComponent::FinishReload(){if(!WeaponDefinition)return;int32 Need=WeaponDefinition->MagazineSize-Ammo.Magazine;int32 Take=FMath::Min(Need,Ammo.Reserve);Ammo.Magazine+=Take;Ammo.Reserve-=Take;bReloading=false;OnRep_Ammo();}'

$ServerExactCount = ([regex]::Matches($Weapon, [regex]::Escape($OldServerReload))).Count
$FinishExactCount = ([regex]::Matches($Weapon, [regex]::Escape($OldFinishReload))).Count

Write-Host "ABP_UNARMED_SELECTED=$Unarmed"
Write-Host "SKM_RIFLE_SELECTED=$Rifle"
Write-Host "RELOAD_BINDING_PRESENT=$ReloadBinding"
Write-Host "RELOAD_WRAPPER_PRESENT=$ReloadWrapper"
Write-Host "SERVER_RELOAD_EXACT_SHAPE_COUNT=$ServerExactCount"
Write-Host "FINISH_RELOAD_EXACT_SHAPE_COUNT=$FinishExactCount"

if (-not ($Unarmed -and $Rifle -and $ReloadBinding -and $ReloadWrapper)) {
    Stop-Gate "PLAYER_BASELINE_NOT_AS_EXPECTED" 12
}
if ($ServerExactCount -ne 1) {
    Stop-Gate "SERVER_RELOAD_EXACT_SHAPE_COUNT_$ServerExactCount" 13
}
if ($FinishExactCount -ne 1) {
    Stop-Gate "FINISH_RELOAD_EXACT_SHAPE_COUNT_$FinishExactCount" 14
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\Phase03E_V2_$Stamp"
$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\Phase03E_V2_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

Copy-Item -LiteralPath $V2Cpp -Destination (Join-Path $BackupRoot "ASPlayerCharacterV2.cpp.before_phase03e_v2") -Force
Copy-Item -LiteralPath $WeaponCpp -Destination (Join-Path $BackupRoot "ASWeaponComponent.cpp.before_phase03e_v2") -Force
Copy-Item -LiteralPath $InputIni -Destination (Join-Path $BackupRoot "DefaultInput.ini.before_phase03e_v2") -Force
Write-Host "BACKUP_ROOT=$BackupRoot"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PATCH Z WITH SAFE CROUCH PIPELINE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$EnterPattern = '(?ms)void\s+AASPlayerCharacterV2::EnterProne\(\)\s*\{.*?^\}'
$ExitPattern  = '(?ms)void\s+AASPlayerCharacterV2::ExitProne\(\)\s*\{.*?^\}'

$EnterMatches = [regex]::Matches($V2, $EnterPattern)
$ExitMatches = [regex]::Matches($V2, $ExitPattern)

if ($EnterMatches.Count -ne 1) {
    Stop-Gate "EXPECTED_ONE_ENTERPRONE_FOUND_$($EnterMatches.Count)" 20
}
if ($ExitMatches.Count -ne 1) {
    Stop-Gate "EXPECTED_ONE_EXITPRONE_FOUND_$($ExitMatches.Count)" 21
}

$EnterReplacement = @'
void AASPlayerCharacterV2::EnterProne()
{
    GetWorldTimerManager().ClearTimer(SlideTimerHandle);

    if (MovementStance == EASMovementStance::Sliding)
    {
        StopSlide();
    }

    // Temporary safe-prone foundation.
    // ACharacter crouch preserves the character floor/base and prevents
    // the mesh from being pushed below the ground by raw capsule resizing.
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
    if (bIsCrouched)
    {
        UnCrouch(false);
    }

    MovementStance = EASMovementStance::Standing;
    UpdateMovementProfile();
}
'@

$V2 = [regex]::Replace($V2, $EnterPattern, $EnterReplacement, 1)
$V2 = [regex]::Replace($V2, $ExitPattern, $ExitReplacement, 1)

$ProneProfilePattern = '(?ms)if\s*\(MovementStance\s*==\s*EASMovementStance::Prone\)\s*\{\s*Move->MaxWalkSpeed\s*=\s*ProneMoveSpeed;\s*return;\s*\}'
$ProneProfileReplacement = @'
if (MovementStance == EASMovementStance::Prone)
    {
        Move->MaxWalkSpeed = ProneMoveSpeed;
        Move->MaxWalkSpeedCrouched = ProneMoveSpeed;
        return;
    }
'@

$ProneProfileCount = [regex]::Matches($V2, $ProneProfilePattern).Count
Write-Host "PRONE_PROFILE_MATCH_COUNT=$ProneProfileCount"
if ($ProneProfileCount -ne 1) {
    Stop-Gate "PRONE_MOVEMENT_PROFILE_SHAPE_NOT_FOUND" 22
}

$V2 = [regex]::Replace($V2, $ProneProfilePattern, $ProneProfileReplacement, 1)

# Remove old narrow jump telemetry if present.
$JumpLogPattern = '(?ms)\s*UE_LOG\(\s*LogTemp,\s*Warning,\s*TEXT\("ASWW_QA_JUMP_INPUT.*?\);\s*'
$V2 = [regex]::Replace($V2, $JumpLogPattern, "`r`n    ")

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PATCH R WRAPPER + CANONICAL INPUT MAPPING" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$ReloadFunctionPattern = '(?ms)void\s+AASPlayerCharacterV2::ReloadPressedV2\(\)\s*\{.*?^\}'
$ReloadFunctionMatches = [regex]::Matches($V2, $ReloadFunctionPattern)
if ($ReloadFunctionMatches.Count -ne 1) {
    Stop-Gate "EXPECTED_ONE_RELOADPRESSEDV2_FOUND_$($ReloadFunctionMatches.Count)" 23
}

$ReloadFunctionReplacement = @'
void AASPlayerCharacterV2::ReloadPressedV2()
{
    UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_RELOAD_KEY_PRESSED"));
    Reload();
}
'@

$V2 = [regex]::Replace($V2, $ReloadFunctionPattern, $ReloadFunctionReplacement, 1)

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

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " EXACT PATCH OF MINIFIED WEAPON RELOAD FUNCTIONS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$NewServerReload = @'
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

$NewFinishReload = @'
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

if ($Weapon.IndexOf($OldServerReload, [StringComparison]::Ordinal) -lt 0) {
    Stop-Gate "OLD_SERVER_RELOAD_EXACT_TEXT_NOT_FOUND" 24
}
if ($Weapon.IndexOf($OldFinishReload, [StringComparison]::Ordinal) -lt 0) {
    Stop-Gate "OLD_FINISH_RELOAD_EXACT_TEXT_NOT_FOUND" 25
}

$Weapon = $Weapon.Replace($OldServerReload, $NewServerReload)
$Weapon = $Weapon.Replace($OldFinishReload, $NewFinishReload)

Write-Utf8Bom $V2Cpp $V2
Write-Utf8Bom $WeaponCpp $Weapon
Write-Utf8Bom $InputIni $Input

$V2Disk = Get-Content -Raw -LiteralPath $V2Cpp
$WeaponDisk = Get-Content -Raw -LiteralPath $WeaponCpp
$InputDisk = Get-Content -Raw -LiteralPath $InputIni

$ZRawResize = $V2Disk -match 'EnterProne\(\)[\s\S]{0,1000}SetCapsuleHalfHeight'
$ZSafe = $V2Disk -match 'EnterProne\(\)[\s\S]{0,900}Crouch\(false\)'
$ReloadKeyMarker = $V2Disk -match 'ASWW_QA_RELOAD_KEY_PRESSED'
$ReloadAcceptedMarker = $WeaponDisk -match 'ASWW_QA_RELOAD_ACCEPTED'
$ReloadFinishedMarker = $WeaponDisk -match 'ASWW_QA_RELOAD_FINISHED'
$ReloadRCount = ([regex]::Matches($InputDisk, [regex]::Escape($ReloadRLine))).Count

Write-Host "Z_RAW_CAPSULE_RESIZE_REMAINS=$ZRawResize"
Write-Host "Z_SAFE_CROUCH_PIPELINE_INSTALLED=$ZSafe"
Write-Host "RELOAD_KEY_MARKER_INSTALLED=$ReloadKeyMarker"
Write-Host "RELOAD_ACCEPT_MARKER_INSTALLED=$ReloadAcceptedMarker"
Write-Host "RELOAD_FINISH_MARKER_INSTALLED=$ReloadFinishedMarker"
Write-Host "RELOAD_R_MAPPING_COUNT=$ReloadRCount"

if ($ZRawResize) {
    Stop-Gate "RAW_PRONE_CAPSULE_RESIZE_STILL_PRESENT" 26
}
if (-not ($ZSafe -and $ReloadKeyMarker -and $ReloadAcceptedMarker -and $ReloadFinishedMarker)) {
    Stop-Gate "POST_PATCH_VERIFY_FAILED" 27
}
if ($ReloadRCount -ne 1) {
    Stop-Gate "RELOAD_R_MAPPING_COUNT_$ReloadRCount" 28
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 29
}

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 30
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
    Get-Content -LiteralPath $GameLog -Tail 300
    $Code = 32
    if ($GameExit -gt 0) { $Code = $GameExit }
    Stop-Gate "GAME_BUILD_FAILED_EXIT_$GameExit" $Code
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COOK + STAGE + PACKAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRE_PHASE03E_V2_$Stamp"
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
    $Code = 33
    if ($PackageExit -gt 0) { $Code = $PackageExit }
    Stop-Gate "PACKAGE_FAILED_EXIT_$PackageExit" $Code
}

$Exe = Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $Exe) {
    Stop-Gate "PACKAGED_EXE_NOT_FOUND" 34
}

Write-Host "PACKAGED_EXE=$($Exe.FullName)"

Write-Host ""
Write-Host "PHASE_03E_V2_Z_RELOAD_FIX=PASS" -ForegroundColor Green
Write-Host "Z_GROUND_CLIP_FIX=SAFE_ENGINE_CROUCH_PIPELINE" -ForegroundColor Green
Write-Host "TRUE_PRONE_ANIMATION=NOT_YET_IMPLEMENTED" -ForegroundColor Yellow
Write-Host "R_RELOAD_MAPPING=CANONICAL_R" -ForegroundColor Green
Write-Host "RELOAD_DIAGNOSTICS=TEMPORARY_QA_ONLY" -ForegroundColor Yellow
Write-Host "NEXT_GATE=RUN_PHASE_03E_Z_RELOAD_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
