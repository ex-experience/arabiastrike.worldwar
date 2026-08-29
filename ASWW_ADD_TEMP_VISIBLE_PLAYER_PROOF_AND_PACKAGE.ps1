[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "TEMP_VISIBLE_PLAYER_PROOF=STOPPED" -ForegroundColor Red
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

$Character = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"
$PackageScript = Join-Path $ProjectRoot "ASWW_REPAIR_STAGINGDIR_AND_PACKAGE.ps1"

if (-not (Test-Path -LiteralPath $Character -PathType Leaf)) {
    Stop-Gate "MISSING_ASCHARACTER_CPP" 11
}
if (-not (Test-Path -LiteralPath $PackageScript -PathType Leaf)) {
    Stop-Gate "MISSING_ASWW_REPAIR_STAGINGDIR_AND_PACKAGE_PS1" 12
}

$Original = Get-Content -Raw -LiteralPath $Character

if ($Original -match 'TEXT\("ASWW_PlayerVisualProof"\)') {
    Write-Host "TEMP_VISIBLE_PLAYER_PROOF=ALREADY_APPLIED" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=REPACKAGE_OR_RUN_VISIBLE_PLAYER_QA" -ForegroundColor Green
    exit 0
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ProjectRoot "Saved\Verification\TempVisiblePlayerProof_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Character -Destination (Join-Path $BackupDir "ASCharacter.cpp") -Force
Write-Host "ASCHARACTER_BACKUP=$BackupDir" -ForegroundColor Cyan

$Text = $Original

$Includes = @(
    '#include "Components/StaticMeshComponent.h"',
    '#include "Engine/StaticMesh.h"',
    '#include "UObject/ConstructorHelpers.h"'
)

$IncludeAnchor = '#include "Camera/CameraComponent.h"'
if (-not $Text.Contains($IncludeAnchor)) {
    Stop-Gate "SAFE_INCLUDE_ANCHOR_NOT_FOUND" 20
}

foreach ($Inc in $Includes) {
    if (-not $Text.Contains($Inc)) {
        $Text = $Text.Replace($IncludeAnchor, $IncludeAnchor + [Environment]::NewLine + $Inc)
    }
}

$AttachRx = [regex]::new(
    'FollowCamera->SetupAttachment\s*\(\s*CameraBoom\s*,\s*USpringArmComponent::SocketName\s*\)\s*;',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

if (-not $AttachRx.IsMatch($Text)) {
    Stop-Gate "FOLLOW_CAMERA_ATTACHMENT_PATTERN_NOT_FOUND" 21
}

$ProofBlock = @'

    // TEMPORARY QA VISUAL ONLY. Do not commit as final player art.
    UStaticMeshComponent* VisualProof =
        CreateDefaultSubobject<UStaticMeshComponent>(TEXT("ASWW_PlayerVisualProof"));
    VisualProof->SetupAttachment(RootComponent);
    VisualProof->SetRelativeLocation(FVector(0.f, 0.f, -5.f));
    VisualProof->SetRelativeScale3D(FVector(0.45f, 0.35f, 1.60f));
    VisualProof->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    VisualProof->SetGenerateOverlapEvents(false);

    static ConstructorHelpers::FObjectFinder<UStaticMesh> VisualProofMesh(
        TEXT("/Engine/BasicShapes/Cube.Cube"));
    if (VisualProofMesh.Succeeded())
    {
        VisualProof->SetStaticMesh(VisualProofMesh.Object);
    }

    UE_LOG(LogTemp, Warning,
        TEXT("ASWW_VISUAL_PROOF component=%s mesh=%s"),
        *GetNameSafe(VisualProof),
        *GetNameSafe(VisualProof->GetStaticMesh()));
'@

$Text = $AttachRx.Replace(
    $Text,
    [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        return $m.Value + $ProofBlock
    },
    1
)

[IO.File]::WriteAllText($Character, $Text, [Text.UTF8Encoding]::new($true))

$Verify = Get-Content -Raw -LiteralPath $Character
$Checks = @{
    "STATIC_MESH_COMPONENT_INCLUDE" = '#include "Components/StaticMeshComponent.h"'
    "CONSTRUCTOR_HELPERS_INCLUDE" = '#include "UObject/ConstructorHelpers.h"'
    "PLAYER_VISUAL_PROOF_COMPONENT" = 'TEXT("ASWW_PlayerVisualProof")'
    "ENGINE_CUBE_ASSET" = '/Engine/BasicShapes/Cube.Cube'
    "VISUAL_PROOF_LOG" = 'ASWW_VISUAL_PROOF'
}

foreach ($K in $Checks.Keys) {
    $Seen = $Verify.Contains($Checks[$K])
    Write-Host "$K=$Seen"
    if (-not $Seen) {
        Stop-Gate "VERIFY_FAILED_$K" 22
    }
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 23
}

Write-Host ""
Write-Host "TEMP_VISIBLE_PLAYER_PROOF=PASS" -ForegroundColor Green
Write-Host "VISUAL_PROOF_TYPE=ENGINE_CUBE_STATIC_MESH" -ForegroundColor Green
Write-Host "PATCH_SCOPE=ASCharacter.cpp_ONLY" -ForegroundColor Green
Write-Host "NEXT_GATE=REBUILD_PACKAGE_WITH_VISUAL_PROOF" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_VISUAL_PROOF_OR_TELEMETRY" -ForegroundColor Yellow

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REBUILD + PACKAGE WITH TEMP VISUAL PROOF" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PackageScript
$Exit = $LASTEXITCODE

Write-Host ""
Write-Host "PACKAGE_PIPELINE_EXIT=$Exit"

if ($Exit -ne 0) {
    Stop-Gate "PACKAGE_PIPELINE_FAILED_EXIT_$Exit" $(if ($Exit -gt 0) { $Exit } else { 30 })
}

Write-Host ""
Write-Host "VISIBLE_PLAYER_PROOF_PACKAGE=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_VISIBLE_PLAYER_PROOF_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_VISUAL_PROOF_OR_TELEMETRY" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
