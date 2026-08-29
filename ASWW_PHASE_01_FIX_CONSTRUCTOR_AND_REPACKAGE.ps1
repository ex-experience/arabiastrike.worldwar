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
    Write-Host "PHASE_01_CONSTRUCTOR_FIX=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
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

$BuildScript = Join-Path $ProjectRoot "BuildScripts\build_win64.ps1"
$BaseH = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Player\ASCharacter.h"
$BaseCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"
$V2H = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Public\Player\ASPlayerCharacterV2.h"
$V2Cpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASPlayerCharacterV2.cpp"

foreach ($Required in @($BuildScript,$BaseH,$BaseCpp,$V2H,$V2Cpp)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

$BaseHeader = Get-Content -Raw -LiteralPath $BaseH
$BaseSource = Get-Content -Raw -LiteralPath $BaseCpp
$V2Header = Get-Content -Raw -LiteralPath $V2H
$V2Source = Get-Content -Raw -LiteralPath $V2Cpp

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " CONSTRUCTOR AUDIT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$BaseHeaderNoArg = ([regex]::Matches($BaseHeader, 'AASCharacter\s*\(\s*\)\s*;')).Count
$BaseHeaderObjInit = ([regex]::Matches($BaseHeader, 'AASCharacter\s*\(\s*const\s+FObjectInitializer\s*&')).Count
$BaseCppNoArg = ([regex]::Matches($BaseSource, 'AASCharacter::AASCharacter\s*\(\s*\)')).Count
$BaseCppObjInit = ([regex]::Matches($BaseSource, 'AASCharacter::AASCharacter\s*\(\s*const\s+FObjectInitializer\s*&')).Count

$V2HeaderNoArg = ([regex]::Matches($V2Header, 'AASPlayerCharacterV2\s*\(\s*\)\s*;')).Count
$V2HeaderObjInit = ([regex]::Matches($V2Header, 'AASPlayerCharacterV2\s*\(\s*const\s+FObjectInitializer\s*&')).Count
$V2CppNoArg = ([regex]::Matches($V2Source, 'AASPlayerCharacterV2::AASPlayerCharacterV2\s*\(\s*\)')).Count
$V2CppObjInit = ([regex]::Matches($V2Source, 'AASPlayerCharacterV2::AASPlayerCharacterV2\s*\(\s*const\s+FObjectInitializer\s*&')).Count

Write-Host "BASE_HEADER_NOARG_CTOR_COUNT=$BaseHeaderNoArg"
Write-Host "BASE_HEADER_OBJECTINITIALIZER_CTOR_COUNT=$BaseHeaderObjInit"
Write-Host "BASE_CPP_NOARG_CTOR_COUNT=$BaseCppNoArg"
Write-Host "BASE_CPP_OBJECTINITIALIZER_CTOR_COUNT=$BaseCppObjInit"
Write-Host "V2_HEADER_NOARG_CTOR_COUNT=$V2HeaderNoArg"
Write-Host "V2_HEADER_OBJECTINITIALIZER_CTOR_COUNT=$V2HeaderObjInit"
Write-Host "V2_CPP_NOARG_CTOR_COUNT=$V2CppNoArg"
Write-Host "V2_CPP_OBJECTINITIALIZER_CTOR_COUNT=$V2CppObjInit"

# Standardize both classes on Unreal's FObjectInitializer constructor pattern.
# This makes AASCharacter explicitly inheritable and removes C2512 ambiguity.
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\Phase01ConstructorFix_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

Copy-Item -LiteralPath $BaseH -Destination (Join-Path $BackupRoot "ASCharacter.h.before_ctor_fix") -Force
Copy-Item -LiteralPath $BaseCpp -Destination (Join-Path $BackupRoot "ASCharacter.cpp.before_ctor_fix") -Force
Copy-Item -LiteralPath $V2H -Destination (Join-Path $BackupRoot "ASPlayerCharacterV2.h.before_ctor_fix") -Force
Copy-Item -LiteralPath $V2Cpp -Destination (Join-Path $BackupRoot "ASPlayerCharacterV2.cpp.before_ctor_fix") -Force

Write-Host "BACKUP_ROOT=$BackupRoot"

if ($BaseHeaderObjInit -eq 0) {
    if ($BaseHeaderNoArg -ne 1) {
        Stop-Gate "BASE_HEADER_CONSTRUCTOR_PATTERN_UNEXPECTED" 20
    }

    $BaseHeader = [regex]::Replace(
        $BaseHeader,
        'AASCharacter\s*\(\s*\)\s*;',
        'AASCharacter(const FObjectInitializer& ObjectInitializer = FObjectInitializer::Get());',
        1
    )
}

if ($BaseCppObjInit -eq 0) {
    if ($BaseCppNoArg -ne 1) {
        Stop-Gate "BASE_CPP_CONSTRUCTOR_PATTERN_UNEXPECTED" 21
    }

    $BaseSource = [regex]::Replace(
        $BaseSource,
        'AASCharacter::AASCharacter\s*\(\s*\)\s*(?=\{)',
        "AASCharacter::AASCharacter(const FObjectInitializer& ObjectInitializer)`r`n    : Super(ObjectInitializer)`r`n",
        1
    )
}
elseif ($BaseSource -notmatch 'AASCharacter::AASCharacter\s*\(\s*const\s+FObjectInitializer\s*&[^)]*\)\s*:\s*Super\s*\(\s*ObjectInitializer\s*\)') {
    Stop-Gate "BASE_OBJECTINITIALIZER_CTOR_EXISTS_BUT_SUPER_CHAIN_NOT_VERIFIED" 22
}

if ($V2HeaderObjInit -eq 0) {
    if ($V2HeaderNoArg -ne 1) {
        Stop-Gate "V2_HEADER_CONSTRUCTOR_PATTERN_UNEXPECTED" 23
    }

    $V2Header = [regex]::Replace(
        $V2Header,
        'AASPlayerCharacterV2\s*\(\s*\)\s*;',
        'AASPlayerCharacterV2(const FObjectInitializer& ObjectInitializer = FObjectInitializer::Get());',
        1
    )
}

if ($V2CppObjInit -eq 0) {
    if ($V2CppNoArg -ne 1) {
        Stop-Gate "V2_CPP_CONSTRUCTOR_PATTERN_UNEXPECTED" 24
    }

    $V2Source = [regex]::Replace(
        $V2Source,
        'AASPlayerCharacterV2::AASPlayerCharacterV2\s*\(\s*\)\s*(?=\{)',
        "AASPlayerCharacterV2::AASPlayerCharacterV2(const FObjectInitializer& ObjectInitializer)`r`n    : Super(ObjectInitializer)`r`n",
        1
    )
}
elseif ($V2Source -notmatch 'AASPlayerCharacterV2::AASPlayerCharacterV2\s*\(\s*const\s+FObjectInitializer\s*&[^)]*\)\s*:\s*Super\s*\(\s*ObjectInitializer\s*\)') {
    Stop-Gate "V2_OBJECTINITIALIZER_CTOR_EXISTS_BUT_SUPER_CHAIN_NOT_VERIFIED" 25
}

Write-Utf8Bom $BaseH $BaseHeader
Write-Utf8Bom $BaseCpp $BaseSource
Write-Utf8Bom $V2H $V2Header
Write-Utf8Bom $V2Cpp $V2Source

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " POST-PATCH CONSTRUCTOR VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$BaseHeaderDisk = Get-Content -Raw -LiteralPath $BaseH
$BaseSourceDisk = Get-Content -Raw -LiteralPath $BaseCpp
$V2HeaderDisk = Get-Content -Raw -LiteralPath $V2H
$V2SourceDisk = Get-Content -Raw -LiteralPath $V2Cpp

$BaseHeaderPass = $BaseHeaderDisk -match 'AASCharacter\s*\(\s*const\s+FObjectInitializer\s*&'
$BaseSourcePass = $BaseSourceDisk -match 'AASCharacter::AASCharacter\s*\(\s*const\s+FObjectInitializer\s*&[^)]*\)\s*:\s*Super\s*\(\s*ObjectInitializer\s*\)'
$V2HeaderPass = $V2HeaderDisk -match 'AASPlayerCharacterV2\s*\(\s*const\s+FObjectInitializer\s*&'
$V2SourcePass = $V2SourceDisk -match 'AASPlayerCharacterV2::AASPlayerCharacterV2\s*\(\s*const\s+FObjectInitializer\s*&[^)]*\)\s*:\s*Super\s*\(\s*ObjectInitializer\s*\)'

Write-Host "BASE_HEADER_OBJECTINITIALIZER=PASS_$BaseHeaderPass"
Write-Host "BASE_CPP_SUPER_OBJECTINITIALIZER=PASS_$BaseSourcePass"
Write-Host "V2_HEADER_OBJECTINITIALIZER=PASS_$V2HeaderPass"
Write-Host "V2_CPP_SUPER_OBJECTINITIALIZER=PASS_$V2SourcePass"

if (-not ($BaseHeaderPass -and $BaseSourcePass -and $V2HeaderPass -and $V2SourcePass)) {
    Stop-Gate "POST_PATCH_CONSTRUCTOR_VERIFICATION_FAILED" 26
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 27
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REBUILD + COOK + PACKAGE PHASE 01" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 28
}

$PackageStart = Get-Date

if (Test-Path -LiteralPath $StageRoot) {
    $OldStage = "$StageRoot`_PRE_PHASE01_CTOR_FIX_$Stamp"
    try {
        Move-Item -LiteralPath $StageRoot -Destination $OldStage
        Write-Host "OLD_STAGE_MOVED=$OldStage"
    }
    catch {
        Stop-Gate "STAGE_ROOT_LOCKED_$($_.Exception.Message)" 29
    }
}

$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\Phase01ConstructorFix"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$PackageLog = Join-Path $EvidenceRoot "phase01_ctor_fix_package_$Stamp.log"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BuildScript -UERoot $UERoot 2>&1 |
    Tee-Object -FilePath $PackageLog
$PackageExit = $LASTEXITCODE

Write-Host "PACKAGE_SCRIPT_EXIT=$PackageExit"

if ($PackageExit -ne 0) {
    Write-Host ""
    Write-Host "=== PACKAGE FAILURE TAIL ===" -ForegroundColor Yellow
    Get-Content -LiteralPath $PackageLog -Tail 220
    Stop-Gate "BUILD_WIN64_FAILED_EXIT_$PackageExit" $(if ($PackageExit -gt 0) { $PackageExit } else { 30 })
}

$Exes = @(
    Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
)

if ($Exes.Count -eq 0) {
    Stop-Gate "PACKAGE_EXIT_ZERO_BUT_EXE_NOT_FOUND" 31
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
    Stop-Gate "PACKAGED_OUTPUT_NOT_FRESH_OR_NO_CONTAINERS" 32
}

Write-Host ""
Write-Host "PHASE_01_CONSTRUCTOR_FIX=PASS" -ForegroundColor Green
Write-Host "C2512_BASE_CONSTRUCTOR_BLOCKER=FIXED" -ForegroundColor Green
Write-Host "BUILD_COOK_PACKAGE=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_PHASE_01_PLAYER_FOUNDATION_QA" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
