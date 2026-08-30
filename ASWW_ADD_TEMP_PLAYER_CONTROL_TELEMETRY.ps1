[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "TEMP_PLAYER_CONTROL_TELEMETRY=STOPPED" -ForegroundColor Red
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

if ($Original -match "ASWW_TELEMETRY CHARACTER_BEGIN") {
    Write-Host "TEMP_PLAYER_CONTROL_TELEMETRY=ALREADY_APPLIED" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=REBUILD_AND_PACKAGE_WIN64" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
    exit 0
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ProjectRoot "Saved\Verification\TempPlayerControlTelemetry_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Character -Destination (Join-Path $BackupDir "ASCharacter.cpp") -Force

Write-Host "TELEMETRY_BACKUP=$BackupDir" -ForegroundColor Cyan

$Text = $Original

function Insert-AfterOpen {
    param(
        [string]$InputText,
        [string]$Pattern,
        [string]$Insertion,
        [string]$GateName
    )
    $Rx = [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $M = $Rx.Match($InputText)
    if (-not $M.Success) {
        Stop-Gate "PATCH_PATTERN_NOT_FOUND_$GateName" 20
    }
    return $Rx.Replace($InputText, { param($x) $x.Value + $Insertion }, 1)
}

$BeginInsert = @'

    UE_LOG(LogTemp, Warning, TEXT("ASWW_TELEMETRY CHARACTER_BEGIN pawn=%s controller=%s local=%d player=%d location=%s"),
        *GetName(), *GetNameSafe(GetController()), IsLocallyControlled() ? 1 : 0, IsPlayerControlled() ? 1 : 0,
        *GetActorLocation().ToCompactString());
'@

$Text = Insert-AfterOpen `
    -InputText $Text `
    -Pattern 'void\s+AASCharacter::BeginPlay\s*\(\s*\)\s*\{' `
    -Insertion $BeginInsert `
    -GateName "BEGINPLAY"

$TickInsert = @'

    if (Controller && !Tags.Contains(FName(TEXT("ASWW_Telemetry_ControllerSeen"))))
    {
        Tags.AddUnique(FName(TEXT("ASWW_Telemetry_ControllerSeen")));
        UE_LOG(LogTemp, Warning, TEXT("ASWW_TELEMETRY CONTROLLER_SEEN pawn=%s controller=%s controllerClass=%s local=%d player=%d"),
            *GetName(), *GetNameSafe(Controller), *GetNameSafe(Controller->GetClass()),
            IsLocallyControlled() ? 1 : 0, IsPlayerControlled() ? 1 : 0);
    }
'@

$Text = Insert-AfterOpen `
    -InputText $Text `
    -Pattern 'void\s+AASCharacter::Tick\s*\(\s*float\s+\w+\s*\)\s*\{' `
    -Insertion $TickInsert `
    -GateName "TICK"

$SetupInsert = @'

    UE_LOG(LogTemp, Warning, TEXT("ASWW_TELEMETRY INPUT_SETUP pawn=%s controller=%s input=%s local=%d player=%d"),
        *GetName(), *GetNameSafe(GetController()), *GetNameSafe(I),
        IsLocallyControlled() ? 1 : 0, IsPlayerControlled() ? 1 : 0);
'@

# Support either the compact local parameter "I" or a descriptive parameter name.
$SetupRx = [regex]::new('void\s+AASCharacter::SetupPlayerInputComponent\s*\(\s*UInputComponent\s*\*\s*(?<arg>\w+)\s*\)\s*\{',
    [System.Text.RegularExpressions.RegexOptions]::Singleline)
$SetupMatch = $SetupRx.Match($Text)
if (-not $SetupMatch.Success) {
    Stop-Gate "PATCH_PATTERN_NOT_FOUND_SETUPINPUT" 21
}
$InputArg = $SetupMatch.Groups["arg"].Value
$SetupInsertActual = $SetupInsert.Replace('GetNameSafe(I)', "GetNameSafe($InputArg)")
$Text = $SetupRx.Replace($Text, { param($x) $x.Value + $SetupInsertActual }, 1)

function Insert-AxisTelemetry {
    param(
        [string]$InputText,
        [string]$FunctionName,
        [string]$Marker
    )

    $Pattern = 'void\s+AASCharacter::' + [regex]::Escape($FunctionName) +
               '\s*\(\s*float\s+(?<arg>\w+)\s*\)\s*\{'
    $Rx = [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $M = $Rx.Match($InputText)
    if (-not $M.Success) {
        Stop-Gate "PATCH_PATTERN_NOT_FOUND_$($FunctionName.ToUpperInvariant())" 22
    }

    $Arg = $M.Groups["arg"].Value
    $Tag = "ASWW_Telemetry_$Marker"
    $Insert = @"

    if (FMath::Abs($Arg) > KINDA_SMALL_NUMBER && !Tags.Contains(FName(TEXT("$Tag"))))
    {
        Tags.AddUnique(FName(TEXT("$Tag")));
        UE_LOG(LogTemp, Warning, TEXT("ASWW_TELEMETRY $Marker value=%.3f pawn=%s controller=%s"),
            $Arg, *GetName(), *GetNameSafe(GetController()));
    }
"@

    return $Rx.Replace($InputText, { param($x) $x.Value + $Insert }, 1)
}

$Text = Insert-AxisTelemetry $Text "MoveForward" "AXIS_MOVEFORWARD"
$Text = Insert-AxisTelemetry $Text "MoveRight"   "AXIS_MOVERIGHT"
$Text = Insert-AxisTelemetry $Text "Turn"        "AXIS_TURN"
$Text = Insert-AxisTelemetry $Text "LookUp"      "AXIS_LOOKUP"

if ($Text -eq $Original) {
    Stop-Gate "PATCH_MADE_NO_CHANGES" 23
}

[IO.File]::WriteAllText($Character, $Text, [Text.UTF8Encoding]::new($true))

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY TELEMETRY PATCH" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Markers = @(
    "ASWW_TELEMETRY CHARACTER_BEGIN",
    "ASWW_TELEMETRY CONTROLLER_SEEN",
    "ASWW_TELEMETRY INPUT_SETUP",
    "ASWW_TELEMETRY AXIS_MOVEFORWARD",
    "ASWW_TELEMETRY AXIS_MOVERIGHT",
    "ASWW_TELEMETRY AXIS_TURN",
    "ASWW_TELEMETRY AXIS_LOOKUP"
)

$Now = Get-Content -Raw -LiteralPath $Character
foreach ($Marker in $Markers) {
    $Seen = $Now.Contains($Marker)
    Write-Host "$($Marker.Replace(' ','_'))=$Seen"
    if (-not $Seen) {
        Stop-Gate "MISSING_TELEMETRY_MARKER_$Marker" 24
    }
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 25
}

Write-Host ""
Write-Host "TEMP_PLAYER_CONTROL_TELEMETRY=PASS" -ForegroundColor Green
Write-Host "PATCH_SCOPE=ASCharacter.cpp_ONLY" -ForegroundColor Green
Write-Host "NEXT_GATE=REBUILD_AND_PACKAGE_WIN64" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_TELEMETRY" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
