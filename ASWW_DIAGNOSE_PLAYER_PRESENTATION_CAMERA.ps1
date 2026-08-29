[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PLAYER_PRESENTATION_CAMERA_DIAGNOSTIC=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
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

$CharacterCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"
$CharacterH   = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Player\ASCharacter.h"
$Controller  = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASPlayerController.cpp"
$GameMode    = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Game\ASGameMode.cpp"

foreach ($F in @($CharacterCpp,$CharacterH,$Controller,$GameMode)) {
    if (-not (Test-Path -LiteralPath $F -PathType Leaf)) {
        Stop-Gate "MISSING_$F" 11
    }
}

$CharText = Get-Content -Raw -LiteralPath $CharacterCpp
$ControllerText = Get-Content -Raw -LiteralPath $Controller
$GameModeText = Get-Content -Raw -LiteralPath $GameMode

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PLAYER VISUAL / MESH SOURCE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Select-String -LiteralPath $CharacterCpp `
    -Pattern "GetMesh|SetSkeletalMesh|SkeletalMesh|SkeletalMeshComponent|AnimInstance|AnimClass|SetAnimInstanceClass|ConstructorHelpers|Mesh|Material|CapsuleComponent" `
    -Context 2,4 |
    Select-Object -First 180

$ExplicitMeshAssignment =
    ($CharText -match "SetSkeletalMesh\s*\(") -or
    ($CharText -match "SkeletalMesh'") -or
    ($CharText -match "SkeletalMesh""") -or
    ($CharText -match "FObjectFinder\s*<\s*USkeletalMesh")

$ExplicitAnimAssignment =
    ($CharText -match "SetAnimInstanceClass\s*\(") -or
    ($CharText -match "AnimClass\s*=") -or
    ($CharText -match "UAnimBlueprintGeneratedClass")

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CAMERA SOURCE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Select-String -LiteralPath $CharacterCpp `
    -Pattern "CameraBoom|FollowCamera|TargetArmLength|bUsePawnControlRotation|bUseControllerRotationYaw|SetRelativeLocation|SetRelativeRotation|SetActive|Activate|Deactivate|CalcCamera|GetPawnViewLocation|GetViewRotation" `
    -Context 2,5 |
    Select-Object -First 180

Select-String -LiteralPath $Controller `
    -Pattern "SetViewTarget|SetViewTargetWithBlend|AutoManageActiveCameraTarget|PlayerCameraManager|bAutoManageActiveCameraTarget|SetControlRotation|SetInputMode|bShowMouseCursor" `
    -Context 2,5 |
    Select-Object -First 140

$HasCameraBoom = $CharText -match "CreateDefaultSubobject\s*<\s*USpringArmComponent"
$HasFollowCamera = $CharText -match "CreateDefaultSubobject\s*<\s*UCameraComponent"
$CameraUsesControlRotation = $CharText -match "CameraBoom->bUsePawnControlRotation\s*=\s*true"
$PawnUsesControllerYaw = $CharText -match "bUseControllerRotationYaw\s*=\s*true"
$ControllerOverridesViewTarget = $ControllerText -match "SetViewTarget|AutoManageActiveCameraTarget|PlayerCameraManager"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " NATIVE DEFAULT PAWN CHECK" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Select-String -LiteralPath $GameMode `
    -Pattern "DefaultPawnClass|PlayerControllerClass" `
    -Context 1,2 |
    Select-Object -First 20

$NativeDefaultPawn = $GameModeText -match "DefaultPawnClass\s*=\s*AASCharacter::StaticClass\s*\(\s*\)"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CONTENT CANDIDATES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$ContentRoot = Join-Path $ProjectRoot "Content"
$Candidates = @()
if (Test-Path -LiteralPath $ContentRoot -PathType Container) {
    $Candidates = @(Get-ChildItem -LiteralPath $ContentRoot -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension -in @(".uasset",".umap") -and
            $_.Name -match "(?i)character|player|soldier|mannequin|hero|mesh|skeletal|anim|camera"
        } |
        Sort-Object FullName |
        Select-Object -First 120)

    foreach ($C in $Candidates) {
        $Rel = $C.FullName.Substring($ProjectRoot.Length).TrimStart('\')
        Write-Host "CONTENT_CANDIDATE=$Rel"
    }
}

if ($Candidates.Count -eq 0) {
    Write-Host "CONTENT_CANDIDATES=NONE_FOUND_BY_FILENAME"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " LATEST MOVEMENT EVIDENCE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$MovementRoot = "D:\ASWW_RUNTIME_EVIDENCE\MovementTelemetry"
$LatestMove = $null
if (Test-Path -LiteralPath $MovementRoot -PathType Container) {
    $LatestMove = Get-ChildItem -LiteralPath $MovementRoot -Filter "movement_*.stdout.log" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

$MovementActorChanges = $false
if ($LatestMove) {
    Write-Host "MOVEMENT_LOG=$($LatestMove.FullName)"
    $MoveText = Get-Content -Raw -LiteralPath $LatestMove.FullName
    $MovementActorChanges = $MoveText -match "ASWW_MOVE_STATE AFTER .*?delta=([1-9][0-9]*|0\.[0-9]*[1-9])"
    Select-String -LiteralPath $LatestMove.FullName -Pattern "ASWW_MOVE_STATE BEGIN|ASWW_MOVE_STATE INPUT|ASWW_MOVE_STATE AFTER|ASWW_TELEMETRY AXIS_TURN|ASWW_TELEMETRY AXIS_LOOKUP" |
        Select-Object -First 40
}
else {
    Write-Host "MOVEMENT_LOG=NOT_FOUND"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "NATIVE_DEFAULT_PAWN=$NativeDefaultPawn"
Write-Host "EXPLICIT_SKELETAL_MESH_ASSIGNMENT_SEEN=$ExplicitMeshAssignment"
Write-Host "EXPLICIT_ANIM_ASSIGNMENT_SEEN=$ExplicitAnimAssignment"
Write-Host "CAMERA_BOOM_PRESENT=$HasCameraBoom"
Write-Host "FOLLOW_CAMERA_PRESENT=$HasFollowCamera"
Write-Host "CAMERA_USES_CONTROL_ROTATION=$CameraUsesControlRotation"
Write-Host "PAWN_USES_CONTROLLER_YAW=$PawnUsesControllerYaw"
Write-Host "PLAYERCONTROLLER_VIEWTARGET_OVERRIDE_SEEN=$ControllerOverridesViewTarget"
Write-Host "MOVEMENT_ACTOR_POSITION_CHANGES=$MovementActorChanges"
Write-Host "CONTENT_VISUAL_CANDIDATE_COUNT=$($Candidates.Count)"

if ($MovementActorChanges -and
    $NativeDefaultPawn -and
    (-not $ExplicitMeshAssignment) -and
    $HasCameraBoom -and
    $HasFollowCamera) {

    Write-Host "PLAYER_PRESENTATION_CLASSIFICATION=MOVEMENT_WORKS_NATIVE_PLAYER_PAWN_HAS_NO_EXPLICIT_VISUAL_MESH" -ForegroundColor Yellow
    Write-Host "LIKELY_USER_VISIBLE_EFFECT=INVISIBLE_PLAYER_AND_WEAK_VISUAL_PARALLAX_ON_SPARSE_TEST_MAP" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=ADD_TEMPORARY_VISIBLE_PLAYER_PROOF_OR_ASSIGN_REAL_PLAYER_MESH" -ForegroundColor Green
}
elseif ($MovementActorChanges -and $HasCameraBoom -and $HasFollowCamera) {
    Write-Host "PLAYER_PRESENTATION_CLASSIFICATION=MOVEMENT_WORKS_CAMERA_SOURCE_PRESENT" -ForegroundColor Green
    Write-Host "NEXT_GATE=RUNTIME_CAMERA_TRANSFORM_AND_VIEWTARGET_TELEMETRY" -ForegroundColor Green
}
elseif ($MovementActorChanges) {
    Write-Host "PLAYER_PRESENTATION_CLASSIFICATION=MOVEMENT_WORKS_CAMERA_SOURCE_INCOMPLETE" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=FIX_CAMERA_PRESENTATION_PATH" -ForegroundColor Green
}
else {
    Write-Host "PLAYER_PRESENTATION_CLASSIFICATION=INCONCLUSIVE" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=RECHECK_MOVEMENT_EVIDENCE" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "PLAYER_PRESENTATION_CAMERA_DIAGNOSTIC=PASS" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
