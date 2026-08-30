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
    Write-Host "PLAYER_REGRESSION_AB_TEST=STOPPED" -ForegroundColor Red
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

$ProjectFile  = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$BuildScript  = Join-Path $ProjectRoot "BuildScripts\build_win64.ps1"
$CharacterCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"

foreach ($Required in @($ProjectFile,$BuildScript,$CharacterCpp)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

$Text = Get-Content -Raw -LiteralPath $CharacterCpp

$TPPath = "/Game/Variant_Shooter/Anims/ABP_TP_Rifle"
$UnarmedPath = "/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed"

$TPCount = ([regex]::Matches($Text, [regex]::Escape($TPPath))).Count
$UnarmedCount = ([regex]::Matches($Text, [regex]::Escape($UnarmedPath))).Count
$HandGripAttachCount = ([regex]::Matches($Text, 'SetupAttachment\(GetMesh\(\),\s*TEXT\("HandGrip_R"\)\)')).Count
$RifleMarkerCount = ([regex]::Matches($Text, "ASWW_REAL_RIFLE_VISUAL_BEGIN")).Count
$MannyMarkerCount = ([regex]::Matches($Text, "ASWW_REAL_PLAYER_MANNY")).Count

Write-Host "TP_RIFLE_ABP_PATH_COUNT=$TPCount"
Write-Host "UNARMED_ABP_PATH_COUNT=$UnarmedCount"
Write-Host "HANDGRIP_R_ATTACH_COUNT=$HandGripAttachCount"
Write-Host "REAL_RIFLE_VISUAL_MARKER_COUNT=$RifleMarkerCount"
Write-Host "REAL_MANNY_MARKER_COUNT=$MannyMarkerCount"

if ($TPCount -ne 1) {
    Stop-Gate "EXPECTED_EXACTLY_ONE_TP_RIFLE_ABP_PATH_FOUND_$TPCount" 12
}
if ($UnarmedCount -ne 0) {
    Stop-Gate "UNARMED_ABP_PATH_ALREADY_PRESENT_$UnarmedCount" 13
}
if ($HandGripAttachCount -lt 1) {
    Stop-Gate "HANDGRIP_R_ATTACHMENT_NOT_PRESENT" 14
}
if ($RifleMarkerCount -ne 1 -or $MannyMarkerCount -ne 1) {
    Stop-Gate "EXPECTED_PLAYER_RIFLE_MARKERS_NOT_FOUND" 15
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PRECISE A/B CHANGE ONLY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "A_TEST_CURRENT=ABP_TP_Rifle + HandGrip_R"
Write-Host "B_TEST_NEXT=ABP_Unarmed + HandGrip_R"
Write-Host "PURPOSE=ISOLATE_MOVEMENT_CAMERA_REGRESSION_TO_ANIM_BLUEPRINT"

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\PlayerRegressionAB_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
$BackupFile = Join-Path $BackupRoot "ASCharacter.cpp.before_unarmed_ab_test"
Copy-Item -LiteralPath $CharacterCpp -Destination $BackupFile -Force
Write-Host "SOURCE_BACKUP=$BackupFile"

$NewText = $Text.Replace($TPPath, $UnarmedPath)

# Keep the rifle on the verified HandGrip_R socket. Only add a source comment marker.
$Marker = @"

    // ASWW_PLAYER_REGRESSION_AB_TEST_BEGIN
    // Temporary A/B isolation:
    // ABP_TP_Rifle -> ABP_Unarmed
    // Rifle remains attached to HandGrip_R.
    // If movement/camera recover, direct ABP_TP_Rifle assignment is the regression source.
    // ASWW_PLAYER_REGRESSION_AB_TEST_END

"@

if ($NewText -notmatch "ASWW_PLAYER_REGRESSION_AB_TEST_BEGIN") {
    $MannyLogPattern = '(?m)^\s*UE_LOG\(LogTemp,\s*Warning,\s*$\r?\n^\s*TEXT\("ASWW_REAL_PLAYER_MANNY mesh=%s animClass=%s"\),'
    $Anchor = [regex]::Match($NewText, $MannyLogPattern)
    if (-not $Anchor.Success) {
        Stop-Gate "MANNY_LOG_ANCHOR_NOT_FOUND_SOURCE_NOT_WRITTEN" 16
    }
    $NewText = $NewText.Insert($Anchor.Index, $Marker)
}

[IO.File]::WriteAllText($CharacterCpp, $NewText, [Text.UTF8Encoding]::new($true))

$Disk = Get-Content -Raw -LiteralPath $CharacterCpp
$PostTP = ([regex]::Matches($Disk, [regex]::Escape($TPPath))).Count
$PostUnarmed = ([regex]::Matches($Disk, [regex]::Escape($UnarmedPath))).Count
$PostGrip = ([regex]::Matches($Disk, 'SetupAttachment\(GetMesh\(\),\s*TEXT\("HandGrip_R"\)\)')).Count
$ABMarker = ([regex]::Matches($Disk, "ASWW_PLAYER_REGRESSION_AB_TEST_BEGIN")).Count

Write-Host "POST_TP_RIFLE_ABP_PATH_COUNT=$PostTP"
Write-Host "POST_UNARMED_ABP_PATH_COUNT=$PostUnarmed"
Write-Host "POST_HANDGRIP_R_ATTACH_COUNT=$PostGrip"
Write-Host "AB_TEST_MARKER_COUNT=$ABMarker"

if ($PostTP -ne 0 -or $PostUnarmed -ne 1 -or $PostGrip -lt 1 -or $ABMarker -ne 1) {
    Stop-Gate "POST_PATCH_AB_TEST_VALIDATION_FAILED" 17
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 18
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CLEAN BUILD + COOK + PACKAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 19
}

$PackageStart = Get-Date

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRE_PLAYER_AB_$Stamp"
    try {
        Move-Item -LiteralPath $StageRoot -Destination $OldStage
        Write-Host "OLD_STAGE_MOVED=$OldStage"
    }
    catch {
        Stop-Gate "STAGE_ROOT_LOCKED_$($_.Exception.Message)" 20
    }
}

$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\PlayerRegressionABPackage"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$PackageLog = Join-Path $EvidenceRoot "player_regression_ab_package_$Stamp.log"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BuildScript -UERoot $UERoot 2>&1 |
    Tee-Object -FilePath $PackageLog
$PackageExit = $LASTEXITCODE

Write-Host "PACKAGE_SCRIPT_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Write-Host "=== PACKAGE FAILURE TAIL ===" -ForegroundColor Yellow
    Get-Content -LiteralPath $PackageLog -Tail 180
    Stop-Gate "BUILD_WIN64_FAILED_EXIT_$PackageExit" $(if ($PackageExit -gt 0) { $PackageExit } else { 21 })
}

$Exes = @(
    Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
)
if ($Exes.Count -eq 0) {
    Stop-Gate "PACKAGE_EXIT_ZERO_BUT_EXE_NOT_FOUND" 22
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
    Stop-Gate "PACKAGED_OUTPUT_NOT_FRESH_OR_NO_CONTAINERS" 23
}

Write-Host ""
Write-Host "PLAYER_REGRESSION_AB_TEST_PACKAGE=PASS" -ForegroundColor Green
Write-Host "ACTIVE_ANIM_BLUEPRINT=ABP_Unarmed" -ForegroundColor Green
Write-Host "RIFLE_SOCKET_STILL=HandGrip_R" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_PLAYER_REGRESSION_AB_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
