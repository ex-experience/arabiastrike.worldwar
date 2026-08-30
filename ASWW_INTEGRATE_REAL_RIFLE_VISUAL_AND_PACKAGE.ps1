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
    Write-Host "REAL_RIFLE_INTEGRATION=STOPPED" -ForegroundColor Red
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

$SourceResourceRoot = Join-Path $UERoot "Templates\TemplateResources\Standard\Weapons\Content"
$SourceRifleRoot = Join-Path $SourceResourceRoot "Rifle"
$SourceRifleAsset = Join-Path $SourceRifleRoot "Meshes\SK_Rifle.uasset"

foreach ($Required in @($ProjectFile,$EditorCmd,$BuildScript,$CharacterCpp,$SourceRifleRoot,$SourceRifleAsset)) {
    if (-not (Test-Path -LiteralPath $Required)) {
        Stop-Gate "MISSING_REQUIRED_PATH_$Required" 11
    }
}

# Refuse to stack the visual integration twice.
$OriginalCharacter = Get-Content -Raw -LiteralPath $CharacterCpp
if ($OriginalCharacter -match "ASWW_REAL_RIFLE_VISUAL_BEGIN") {
    Stop-Gate "REAL_RIFLE_VISUAL_ALREADY_PRESENT" 12
}

if ($OriginalCharacter -notmatch "ASWW_REAL_PLAYER_MANNY") {
    Stop-Gate "REAL_MANNY_INTEGRATION_MARKER_NOT_FOUND" 13
}

if ($OriginalCharacter -notmatch "SKM_Manny_Simple") {
    Stop-Gate "MANNY_MESH_WIRING_NOT_FOUND" 14
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " INFER ORIGINAL PACKAGE ROOT FROM SK_Rifle" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Bytes = [IO.File]::ReadAllBytes($SourceRifleAsset)
$Ascii = [Text.Encoding]::ASCII.GetString($Bytes)
$Matches = [regex]::Matches($Ascii, '/Game/[A-Za-z0-9_./-]+') |
    ForEach-Object { $_.Value.TrimEnd([char]0,'.') } |
    Sort-Object -Unique

$RifleInternal = @(
    $Matches |
    Where-Object { $_ -match '/Meshes/SK_Rifle(?:\.SK_Rifle)?$' -or $_ -match '/Meshes/SK_Rifle' }
) | Select-Object -First 1

if ($RifleInternal) {
    Write-Host "SK_RIFLE_INTERNAL_PATH_HINT=$RifleInternal"
}
else {
    Write-Host "SK_RIFLE_INTERNAL_PATH_HINT=NOT_FOUND"
}

# Default shared-resource mapping is Content\Rifle -> /Game/Rifle.
# If the binary advertises /Game/<prefix>/Rifle/Meshes/SK_Rifle, preserve that prefix.
$PackagePrefix = ""
if ($RifleInternal) {
    $Normalized = $RifleInternal -replace '\\','/'
    $m = [regex]::Match($Normalized, '^/Game/(.*?)(?:Rifle/Meshes/SK_Rifle)')
    if ($m.Success) {
        $PackagePrefix = $m.Groups[1].Value.Trim('/')
    }
}

if ([string]::IsNullOrWhiteSpace($PackagePrefix)) {
    $DestRifleRoot = Join-Path $ProjectRoot "Content\Rifle"
    $AssetObjectPath = "/Game/Rifle/Meshes/SK_Rifle.SK_Rifle"
}
else {
    $PrefixWin = $PackagePrefix.Replace('/','\')
    $DestRifleRoot = Join-Path $ProjectRoot ("Content\" + $PrefixWin + "\Rifle")
    $AssetObjectPath = "/Game/$PackagePrefix/Rifle/Meshes/SK_Rifle.SK_Rifle" -replace '//','/'
}

Write-Host "RIFLE_PACKAGE_PREFIX=$PackagePrefix"
Write-Host "DEST_RIFLE_ROOT=$DestRifleRoot"
Write-Host "RIFLE_ASSET_OBJECT_PATH=$AssetObjectPath"

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\RealRifleIntegration_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
Copy-Item -LiteralPath $CharacterCpp -Destination (Join-Path $BackupRoot "ASCharacter.cpp.before_rifle") -Force

$DestExisted = Test-Path -LiteralPath $DestRifleRoot
if ($DestExisted) {
    $DestBackup = Join-Path $BackupRoot "RifleAssets.before_integration"
    Copy-Item -LiteralPath $DestRifleRoot -Destination $DestBackup -Recurse -Force
    Write-Host "EXISTING_RIFLE_ASSET_BACKUP=$DestBackup"
}
else {
    Write-Host "EXISTING_RIFLE_ASSET_BACKUP=NOT_NEEDED"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COPY REAL UE TEMPLATE RIFLE ASSET FAMILY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $DestRifleRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $SourceRifleRoot "*") -Destination $DestRifleRoot -Recurse -Force

$CopiedCount = @(
    Get-ChildItem -LiteralPath $DestRifleRoot -Recurse -File -Filter "*.uasset" -ErrorAction Stop
).Count

Write-Host "COPIED_RIFLE_UASSET_COUNT=$CopiedCount"
if ($CopiedCount -lt 1) {
    Stop-Gate "RIFLE_COPY_PRODUCED_NO_UASSETS" 20
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY SK_Rifle LOADS IN ASWW" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$VerifyRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\RealRifleVerify"
New-Item -ItemType Directory -Force -Path $VerifyRoot | Out-Null
$Py = Join-Path $VerifyRoot "verify_real_rifle_$Stamp.py"
$VerifyOut = Join-Path $VerifyRoot "verify_real_rifle_$Stamp.stdout.log"
$VerifyErr = Join-Path $VerifyRoot "verify_real_rifle_$Stamp.stderr.log"

$PyText = @"
import unreal

path = r"$AssetObjectPath"
registry = unreal.AssetRegistryHelpers.get_asset_registry()
registry.scan_paths_synchronous(["/Game"], True)

asset = unreal.load_asset(path)
print(f"ASWW_REAL_RIFLE_ASSET_PATH={path}")
print(f"ASWW_REAL_RIFLE_LOAD={asset is not None}")
print(f"ASWW_REAL_RIFLE_CLASS={asset.get_class().get_name() if asset else 'NONE'}")

if asset:
    try:
        mats = asset.get_editor_property("materials")
        print(f"ASWW_REAL_RIFLE_MATERIAL_SLOT_COUNT={len(mats)}")
        for i, slot in enumerate(mats):
            print(f"ASWW_REAL_RIFLE_MATERIAL_SLOT_{i}={slot}")
    except Exception as exc:
        print(f"ASWW_REAL_RIFLE_MATERIAL_ENUM=UNAVAILABLE:{exc}")
"@

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

& $EditorCmd @Args 1> $VerifyOut 2> $VerifyErr
$VerifyExit = $LASTEXITCODE

$VerifyText = ""
if (Test-Path -LiteralPath $VerifyOut) {
    $VerifyText += Get-Content -Raw -LiteralPath $VerifyOut
    Select-String -LiteralPath $VerifyOut -Pattern "ASWW_REAL_RIFLE_" |
        ForEach-Object { Write-Host $_.Line }
}
if (Test-Path -LiteralPath $VerifyErr) {
    $VerifyText += "`n" + (Get-Content -Raw -LiteralPath $VerifyErr)
}

Write-Host "RIFLE_VERIFY_EDITOR_EXIT=$VerifyExit"

if ($VerifyExit -ne 0 -or
    $VerifyText -notmatch "ASWW_REAL_RIFLE_LOAD=True" -or
    $VerifyText -notmatch "ASWW_REAL_RIFLE_CLASS=SkeletalMesh") {
    Stop-Gate "SK_RIFLE_FAILED_TO_LOAD_AS_SKELETAL_MESH" 21
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PATCH ONLY PLAYER RIFLE VISUAL" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Text = $OriginalCharacter

# Add no new header dependency: Manny integration already uses
# USkeletalMeshComponent, USkeletalMesh and ConstructorHelpers.
$Insert = @"

    // ASWW_REAL_RIFLE_VISUAL_BEGIN
    USkeletalMeshComponent* RifleVisual =
        CreateDefaultSubobject<USkeletalMeshComponent>(TEXT("ASWW_RifleVisual"));
    RifleVisual->SetupAttachment(GetMesh(), TEXT("hand_r"));
    RifleVisual->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    RifleVisual->SetGenerateOverlapEvents(false);

    static ConstructorHelpers::FObjectFinder<USkeletalMesh> RifleMeshAsset(
        TEXT("$AssetObjectPath"));
    if (RifleMeshAsset.Succeeded())
    {
        RifleVisual->SetSkeletalMeshAsset(RifleMeshAsset.Object);
        RifleVisual->SetRelativeTransform(FTransform::Identity);
    }

    UE_LOG(LogTemp, Warning,
        TEXT("ASWW_COMBAT_PROOF RIFLE_VISUAL mesh=%s parent=%s socket=hand_r"),
        *GetNameSafe(RifleVisual->GetSkeletalMeshAsset()),
        *GetNameSafe(RifleVisual->GetAttachParent()));
    // ASWW_REAL_RIFLE_VISUAL_END

"@

$AnchorPattern = '(?m)^\s*UE_LOG\(LogTemp,\s*Warning,\s*$\r?\n^\s*TEXT\("ASWW_REAL_PLAYER_MANNY mesh=%s animClass=%s"\),'
$Anchor = [regex]::Match($Text, $AnchorPattern)

if (-not $Anchor.Success) {
    Stop-Gate "REAL_MANNY_LOG_ANCHOR_NOT_FOUND_SOURCE_NOT_MODIFIED" 22
}

$Text = $Text.Insert($Anchor.Index, $Insert)

# Guard against duplicate insertion.
if (([regex]::Matches($Text, "ASWW_REAL_RIFLE_VISUAL_BEGIN")).Count -ne 1) {
    Stop-Gate "RIFLE_VISUAL_INSERTION_COUNT_INVALID" 23
}

[IO.File]::WriteAllText($CharacterCpp, $Text, [Text.UTF8Encoding]::new($true))

$Disk = Get-Content -Raw -LiteralPath $CharacterCpp
$BeginCount = ([regex]::Matches($Disk, "ASWW_REAL_RIFLE_VISUAL_BEGIN")).Count
$ProofCount = ([regex]::Matches($Disk, "ASWW_COMBAT_PROOF RIFLE_VISUAL")).Count
$MannyCount = ([regex]::Matches($Disk, "ASWW_REAL_PLAYER_MANNY")).Count

Write-Host "RIFLE_VISUAL_BLOCK_COUNT=$BeginCount"
Write-Host "RIFLE_VISUAL_PROOF_MARKER_COUNT=$ProofCount"
Write-Host "REAL_MANNY_MARKER_COUNT=$MannyCount"

if ($BeginCount -ne 1 -or $ProofCount -ne 1 -or $MannyCount -ne 1) {
    Stop-Gate "POST_PATCH_SOURCE_VALIDATION_FAILED" 24
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 25
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLEAN BUILD + COOK + PACKAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 26
}

$PackageStart = Get-Date

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRERIFLE_$Stamp"
    try {
        Move-Item -LiteralPath $StageRoot -Destination $OldStage
        Write-Host "OLD_STAGE_MOVED=$OldStage"
    }
    catch {
        Stop-Gate "STAGE_ROOT_LOCKED_$($_.Exception.Message)" 27
    }
}

$PackageEvidence = Join-Path $ProjectRoot "Saved\RuntimeEvidence\RealRiflePackage"
New-Item -ItemType Directory -Force -Path $PackageEvidence | Out-Null
$PackageLog = Join-Path $PackageEvidence "real_rifle_package_$Stamp.log"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BuildScript -UERoot $UERoot 2>&1 |
    Tee-Object -FilePath $PackageLog
$PackageExit = $LASTEXITCODE

Write-Host "PACKAGE_SCRIPT_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Write-Host ""
    Write-Host "=== PACKAGE FAILURE TAIL ===" -ForegroundColor Yellow
    Get-Content -LiteralPath $PackageLog -Tail 180
    Stop-Gate "BUILD_WIN64_FAILED_EXIT_$PackageExit" $(if ($PackageExit -gt 0) { $PackageExit } else { 40 })
}

$Exes = @(
    Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
)

if ($Exes.Count -eq 0) {
    Stop-Gate "PACKAGE_EXIT_ZERO_BUT_EXE_NOT_FOUND" 41
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
    Stop-Gate "PACKAGED_OUTPUT_NOT_FRESH_OR_NO_CONTAINERS" 42
}

Write-Host ""
Write-Host "REAL_RIFLE_INTEGRATION=PASS" -ForegroundColor Green
Write-Host "RIFLE_ASSET_LOAD=PASS" -ForegroundColor Green
Write-Host "RIFLE_VISUAL_ATTACHED_TO=hand_r" -ForegroundColor Green
Write-Host "CLEAN_PACKAGE_WITH_RIFLE=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_REAL_RIFLE_COMBAT_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
