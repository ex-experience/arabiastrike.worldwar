[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "TEMP_MOVEMENT_TELEMETRY=STOPPED" -ForegroundColor Red
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
if (-not (Test-Path -LiteralPath $Character -PathType Leaf)) {
    Stop-Gate "MISSING_ASCHARACTER_CPP" 11
}

$Original = Get-Content -Raw -LiteralPath $Character

if ($Original -notmatch "ASWW_TELEMETRY CHARACTER_BEGIN") {
    Stop-Gate "BASE_PLAYER_CONTROL_TELEMETRY_NOT_PRESENT" 12
}

if ($Original -match "ASWW_MOVE_STATE INPUT") {
    Write-Host "TEMP_MOVEMENT_TELEMETRY=ALREADY_APPLIED" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=REBUILD_PACKAGE_THEN_RUN_MOVEMENT_TELEMETRY" -ForegroundColor Green
    exit 0
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ProjectRoot "Saved\Verification\TempMovementTelemetry_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Character -Destination (Join-Path $BackupDir "ASCharacter.cpp") -Force
Write-Host "MOVEMENT_TELEMETRY_BACKUP=$BackupDir" -ForegroundColor Cyan

$Text = $Original

function Patch-MoveFunction {
    param(
        [string]$InputText,
        [string]$FunctionName
    )

    $Pattern = 'void\s+AASCharacter::' + [regex]::Escape($FunctionName) +
               '\s*\(\s*float\s+(?<arg>\w+)\s*\)\s*\{'
    $Rx = [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $M = $Rx.Match($InputText)
    if (-not $M.Success) {
        Stop-Gate "MOVE_FUNCTION_NOT_FOUND_$FunctionName" 20
    }

    $Arg = $M.Groups["arg"].Value
    $Tag = "ASWW_MoveState_$FunctionName"

    $Insert = @"

    if (FMath::Abs($Arg) > KINDA_SMALL_NUMBER && !Tags.Contains(FName(TEXT("$Tag"))))
    {
        Tags.AddUnique(FName(TEXT("$Tag")));
        const UCharacterMovementComponent* ASWWMove = GetCharacterMovement();
        UE_LOG(LogTemp, Warning,
            TEXT("ASWW_MOVE_STATE INPUT func=$FunctionName value=%.3f loc=%s vel=%s mode=%d downed=%d eliminated=%d collision=%d controller=%s"),
            $Arg,
            *GetActorLocation().ToCompactString(),
            *GetVelocity().ToCompactString(),
            ASWWMove ? static_cast<int32>(ASWWMove->MovementMode) : -1,
            bDowned ? 1 : 0,
            bEliminated ? 1 : 0,
            static_cast<int32>(GetActorEnableCollision()),
            *GetNameSafe(Controller));

        const FVector ASWWStartLoc = GetActorLocation();
        FTimerDelegate ASWWMoveProbe;
        ASWWMoveProbe.BindWeakLambda(this, [this, ASWWStartLoc]()
        {
            const UCharacterMovementComponent* ASWWMoveAfter = GetCharacterMovement();
            const FVector ASWWNow = GetActorLocation();
            UE_LOG(LogTemp, Warning,
                TEXT("ASWW_MOVE_STATE AFTER start=%s now=%s delta=%.2f vel=%s mode=%d downed=%d eliminated=%d"),
                *ASWWStartLoc.ToCompactString(),
                *ASWWNow.ToCompactString(),
                FVector::Dist(ASWWStartLoc, ASWWNow),
                *GetVelocity().ToCompactString(),
                ASWWMoveAfter ? static_cast<int32>(ASWWMoveAfter->MovementMode) : -1,
                bDowned ? 1 : 0,
                bEliminated ? 1 : 0);
        });
        GetWorldTimerManager().SetTimerForNextTick(ASWWMoveProbe);
    }
"@

    return $Rx.Replace($InputText, { param($x) $x.Value + $Insert }, 1)
}

$Text = Patch-MoveFunction $Text "MoveForward"
$Text = Patch-MoveFunction $Text "MoveRight"

# Add a one-shot startup movement/collision state after BeginPlay begins.
$BeginRx = [regex]::new('void\s+AASCharacter::BeginPlay\s*\(\s*\)\s*\{',
    [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $BeginRx.IsMatch($Text)) {
    Stop-Gate "BEGINPLAY_NOT_FOUND" 21
}

$BeginInsert = @'

    {
        const UCharacterMovementComponent* ASWWMove = GetCharacterMovement();
        UE_LOG(LogTemp, Warning,
            TEXT("ASWW_MOVE_STATE BEGIN loc=%s vel=%s mode=%d downed=%d eliminated=%d collision=%d capsule=%s"),
            *GetActorLocation().ToCompactString(),
            *GetVelocity().ToCompactString(),
            ASWWMove ? static_cast<int32>(ASWWMove->MovementMode) : -1,
            bDowned ? 1 : 0,
            bEliminated ? 1 : 0,
            static_cast<int32>(GetActorEnableCollision()),
            *GetNameSafe(GetCapsuleComponent()));
    }
'@

$Text = $BeginRx.Replace($Text, { param($x) $x.Value + $BeginInsert }, 1)

[IO.File]::WriteAllText($Character, $Text, [Text.UTF8Encoding]::new($true))

$Now = Get-Content -Raw -LiteralPath $Character
foreach ($Marker in @("ASWW_MOVE_STATE BEGIN","ASWW_MOVE_STATE INPUT","ASWW_MOVE_STATE AFTER")) {
    $Seen = $Now.Contains($Marker)
    Write-Host "$($Marker.Replace(' ','_'))=$Seen"
    if (-not $Seen) {
        Stop-Gate "MISSING_MARKER_$Marker" 22
    }
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 23
}

Write-Host ""
Write-Host "TEMP_MOVEMENT_TELEMETRY=PASS" -ForegroundColor Green
Write-Host "PATCH_SCOPE=ASCharacter.cpp_ONLY" -ForegroundColor Green
Write-Host "NEXT_GATE=REBUILD_PACKAGE_THEN_RUN_MOVEMENT_TELEMETRY" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_TELEMETRY" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
