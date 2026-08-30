[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$StageRoot = "D:\ASWW_STAGE",
    [string]$ArchiveRoot = "D:\ASWW_ARCHIVE\Phase03G_FireReload"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_03G_FIRE_RELOAD_PROOF=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "QA_TELEMETRY=TEMPORARY_DO_NOT_COMMIT" -ForegroundColor Yellow
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Write-Utf8Bom([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($true))
}

function Replace-FunctionSpan(
    [string]$Text,
    [string]$StartSignature,
    [string]$NextSignature,
    [string]$Replacement,
    [string]$Label
) {
    $Start = $Text.IndexOf($StartSignature, [StringComparison]::Ordinal)
    if ($Start -lt 0) {
        Stop-Gate "${Label}_START_SIGNATURE_NOT_FOUND" 20
    }

    $End = $Text.IndexOf($NextSignature, $Start + $StartSignature.Length, [StringComparison]::Ordinal)
    if ($End -lt 0) {
        Stop-Gate "${Label}_NEXT_SIGNATURE_NOT_FOUND" 21
    }

    return $Text.Substring(0, $Start) + $Replacement.TrimEnd() + "`r`n" + $Text.Substring($End)
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

$InputIni = Join-Path $ProjectRoot "Config\DefaultInput.ini"
$CharacterCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"
$WeaponCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Combat\ASWeaponComponent.cpp"
$DefinitionUasset = Join-Path $ProjectRoot "Content\Weapons\Definitions\DA_ASWW_Rifle_01.uasset"

foreach ($Required in @($ProjectFile,$BuildBat,$RunUAT,$InputIni,$CharacterCpp,$WeaponCpp,$DefinitionUasset)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

$Input = Get-Content -Raw -LiteralPath $InputIni
$Character = Get-Content -Raw -LiteralPath $CharacterCpp
$Weapon = Get-Content -Raw -LiteralPath $WeaponCpp

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY CURRENT PHASE 03F RUNTIME STATE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$RMapping = $Input -match 'ActionName="Reload".*Key=R'
$ProneZMapping = $Input -match 'ActionName="Prone".*Key=Z'
$ReloadDiagnostics = $Weapon -match "ASWW_QA_RELOAD_REJECT_NO_DEFINITION"
$FireDiagnosticsAlready = $Weapon -match "ASWW_QA_FIRE_AUTH_"
$FireDispatchAlready = $Character -match "ASWW_QA_FIRE_DISPATCH"

Write-Host "R_RELOAD_MAPPING_PRESENT=$RMapping"
Write-Host "Z_PRONE_MAPPING_PRESENT=$ProneZMapping"
Write-Host "RELOAD_DIAGNOSTICS_PRESENT=$ReloadDiagnostics"
Write-Host "FIRE_AUTH_DIAGNOSTICS_ALREADY_PRESENT=$FireDiagnosticsAlready"
Write-Host "FIRE_DISPATCH_DIAGNOSTICS_ALREADY_PRESENT=$FireDispatchAlready"

if (-not ($RMapping -and $ReloadDiagnostics)) {
    Stop-Gate "CURRENT_STATE_NOT_PHASE03F_EXPECTED" 12
}
if ($FireDiagnosticsAlready -or $FireDispatchAlready) {
    Stop-Gate "PHASE03G_FIRE_TELEMETRY_ALREADY_PRESENT_REVIEW_BEFORE_RERUN" 13
}

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 14
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\Phase03G_$Stamp"
$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\Phase03G_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

Copy-Item -LiteralPath $InputIni -Destination (Join-Path $BackupRoot "DefaultInput.ini.before_phase03g") -Force
Copy-Item -LiteralPath $CharacterCpp -Destination (Join-Path $BackupRoot "ASCharacter.cpp.before_phase03g") -Force
Copy-Item -LiteralPath $WeaponCpp -Destination (Join-Path $BackupRoot "ASWeaponComponent.cpp.before_phase03g") -Force
Write-Host "BACKUP_ROOT=$BackupRoot"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TEMPORARILY DISABLE Z / PRONE INPUT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Remove only Z mappings for the Prone action. Keep the underlying state code untouched
# so a proper prone implementation can replace it later.
$InputLines = $Input -split "`r?`n"
$NewLines = New-Object System.Collections.Generic.List[string]
$RemovedZCount = 0

foreach ($Line in $InputLines) {
    if ($Line -match '^\+ActionMappings=\(ActionName="Prone".*Key=Z\)\s*$') {
        $RemovedZCount++
        continue
    }
    $NewLines.Add($Line)
}

$Input = ($NewLines -join "`r`n").TrimEnd() + "`r`n"

Write-Host "Z_PRONE_MAPPING_REMOVED_COUNT=$RemovedZCount"
Write-Host "Z_PRONE_MAPPING_REMAINS=$($Input -match 'ActionName="Prone".*Key=Z')"

if ($RemovedZCount -lt 1) {
    Stop-Gate "NO_Z_PRONE_MAPPING_WAS_REMOVED" 15
}
if ($Input -match 'ActionName="Prone".*Key=Z') {
    Stop-Gate "Z_PRONE_MAPPING_STILL_PRESENT" 16
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ADD FIRE DISPATCH TELEMETRY AT CHARACTER LAYER" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$NewFireOnce = @'
void AASCharacter::FireOnce()
{
    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_QA_FIRE_DISPATCH weapon=%d controller=%d downed=%d eliminated=%d"),
        Weapon ? 1 : 0,
        Controller ? 1 : 0,
        bDowned ? 1 : 0,
        bEliminated ? 1 : 0);

    if (!Weapon || !Controller || bDowned || bEliminated)
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_FIRE_DISPATCH_REJECT"));
        return;
    }

    FVector L;
    FRotator R;
    Controller->GetPlayerViewPoint(L, R);

    UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_FIRE_REQUEST_SENT"));
    Weapon->RequestFire(L, R.Vector());
}
'@

$Character = Replace-FunctionSpan `
    $Character `
    "void AASCharacter::FireOnce()" `
    "void AASCharacter::Reload()" `
    $NewFireOnce `
    "FIREONCE"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ADD FIRE AUTHORITY ACCEPT / REJECT TELEMETRY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$NewFireAuthority = @'
void UASWeaponComponent::FireAuthority(const FVector& O, const FVector& D)
{
    if (!WeaponDefinition)
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_FIRE_AUTH_REJECT_NO_DEFINITION"));
        return;
    }

    if (bReloading)
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_FIRE_AUTH_REJECT_RELOADING"));
        return;
    }

    if (!GetWorld())
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_FIRE_AUTH_REJECT_NO_WORLD"));
        return;
    }

    if (!GetOwner())
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_FIRE_AUTH_REJECT_NO_OWNER"));
        return;
    }

    if (Ammo.Magazine <= 0)
    {
        UE_LOG(
            LogTemp,
            Warning,
            TEXT("ASWW_QA_FIRE_AUTH_REJECT_EMPTY mag=%d reserve=%d"),
            Ammo.Magazine,
            Ammo.Reserve);
        return;
    }

    const double Now = GetWorld()->GetTimeSeconds();
    const double MinInterval =
        60.0 / FMath::Max(1.f, WeaponDefinition->RoundsPerMinute);

    if (Now - LastServerShotTime < MinInterval)
    {
        UE_LOG(
            LogTemp,
            Warning,
            TEXT("ASWW_QA_FIRE_AUTH_REJECT_COOLDOWN dt=%.4f min=%.4f"),
            Now - LastServerShotTime,
            MinInterval);
        return;
    }

    LastServerShotTime = Now;

    const int32 MagazineBefore = Ammo.Magazine;
    Ammo.Magazine--;
    OnRep_Ammo();

    UE_LOG(
        LogTemp,
        Warning,
        TEXT("ASWW_QA_FIRE_AUTH_ACCEPTED magBefore=%d magAfter=%d reserve=%d"),
        MagazineBefore,
        Ammo.Magazine,
        Ammo.Reserve);

    const FVector Dir = FMath::VRandCone(
        D.GetSafeNormal(),
        FMath::DegreesToRadians(WeaponDefinition->SpreadDegrees));

    if (WeaponDefinition->FireMode == EASFireMode::Projectile &&
        WeaponDefinition->ProjectileClass)
    {
        FActorSpawnParameters P;
        P.Owner = GetOwner();
        P.Instigator = Cast<APawn>(GetOwner());

        AASProjectile* Projectile = GetWorld()->SpawnActor<AASProjectile>(
            WeaponDefinition->ProjectileClass,
            O,
            Dir.Rotation(),
            P);

        if (Projectile)
        {
            Projectile->InitDamage(WeaponDefinition->Damage);
        }

        MulticastShotFX(O, O + Dir * 500.f);

        UE_LOG(
            LogTemp,
            Warning,
            TEXT("ASWW_QA_FIRE_AUTH_PATH=PROJECTILE spawned=%d"),
            Projectile ? 1 : 0);
        return;
    }

    const FVector End = O + Dir * WeaponDefinition->Range;
    FHitResult Hit;
    FCollisionQueryParams Q(
        SCENE_QUERY_STAT(ASWeaponTrace),
        true,
        GetOwner());

    FVector FxEnd = End;

    if (GetWorld()->LineTraceSingleByChannel(
        Hit,
        O,
        End,
        ECC_Visibility,
        Q))
    {
        FxEnd = Hit.ImpactPoint;

        AController* C = nullptr;
        if (const APawn* P = Cast<APawn>(GetOwner()))
        {
            C = P->GetController();
        }

        UGameplayStatics::ApplyPointDamage(
            Hit.GetActor(),
            WeaponDefinition->Damage,
            Dir,
            Hit,
            C,
            GetOwner(),
            nullptr);

        UE_LOG(
            LogTemp,
            Warning,
            TEXT("ASWW_QA_FIRE_AUTH_HIT actor=%s"),
            *GetNameSafe(Hit.GetActor()));
    }
    else
    {
        UE_LOG(LogTemp, Warning, TEXT("ASWW_QA_FIRE_AUTH_HIT actor=NONE"));
    }

    ApplyNearMissSuppression(O, FxEnd);
    MulticastShotFX(O, FxEnd);
}
'@

$Weapon = Replace-FunctionSpan `
    $Weapon `
    "void UASWeaponComponent::FireAuthority(" `
    "void UASWeaponComponent::ApplyNearMissSuppression" `
    $NewFireAuthority `
    "FIREAUTHORITY"

Write-Utf8Bom $InputIni $Input
Write-Utf8Bom $CharacterCpp $Character
Write-Utf8Bom $WeaponCpp $Weapon

$InputDisk = Get-Content -Raw -LiteralPath $InputIni
$CharacterDisk = Get-Content -Raw -LiteralPath $CharacterCpp
$WeaponDisk = Get-Content -Raw -LiteralPath $WeaponCpp

$ZDisabled = -not ($InputDisk -match 'ActionName="Prone".*Key=Z')
$FireDispatchMarker = $CharacterDisk -match "ASWW_QA_FIRE_DISPATCH"
$FireRequestMarker = $CharacterDisk -match "ASWW_QA_FIRE_REQUEST_SENT"
$FireAcceptedMarker = $WeaponDisk -match "ASWW_QA_FIRE_AUTH_ACCEPTED"
$FireNoDefMarker = $WeaponDisk -match "ASWW_QA_FIRE_AUTH_REJECT_NO_DEFINITION"
$ReloadAcceptedMarker = $WeaponDisk -match "ASWW_QA_RELOAD_ACCEPTED"
$ReloadFinishedMarker = $WeaponDisk -match "ASWW_QA_RELOAD_FINISHED"

Write-Host "Z_TEMP_DISABLED=$ZDisabled"
Write-Host "FIRE_DISPATCH_MARKER_INSTALLED=$FireDispatchMarker"
Write-Host "FIRE_REQUEST_MARKER_INSTALLED=$FireRequestMarker"
Write-Host "FIRE_AUTH_ACCEPT_MARKER_INSTALLED=$FireAcceptedMarker"
Write-Host "FIRE_AUTH_NO_DEF_MARKER_INSTALLED=$FireNoDefMarker"
Write-Host "RELOAD_ACCEPT_MARKER_STILL_PRESENT=$ReloadAcceptedMarker"
Write-Host "RELOAD_FINISH_MARKER_STILL_PRESENT=$ReloadFinishedMarker"

if (-not ($ZDisabled -and $FireDispatchMarker -and $FireRequestMarker -and $FireAcceptedMarker -and $FireNoDefMarker -and $ReloadAcceptedMarker -and $ReloadFinishedMarker)) {
    Stop-Gate "POST_PATCH_VERIFY_FAILED" 22
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 23
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
    Get-Content -LiteralPath $EditorLog -Tail 340
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
    Get-Content -LiteralPath $GameLog -Tail 340
    $Code = 31
    if ($GameExit -gt 0) { $Code = $GameExit }
    Stop-Gate "GAME_BUILD_FAILED_EXIT_$GameExit" $Code
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COOK + STAGE + PACKAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRE_PHASE03G_$Stamp"
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
    Get-Content -LiteralPath $PackageLog -Tail 400
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
Write-Host "PHASE_03G_FIRE_RELOAD_PROOF=PASS" -ForegroundColor Green
Write-Host "Z_INPUT=TEMP_DISABLED_UNTIL_TRUE_PRONE" -ForegroundColor Yellow
Write-Host "FIRE_AUTHORITY_TELEMETRY=INSTALLED_QA_ONLY" -ForegroundColor Yellow
Write-Host "RIFLE_DEFINITION=KEPT_REAL" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_PHASE_03G_FIRE_RELOAD_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
