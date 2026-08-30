[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "MOVEMENT_TELEMETRY_COMPILE_FIX=STOPPED" -ForegroundColor Red
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

$Text = Get-Content -Raw -LiteralPath $Character

if ($Text -notmatch "ASWW_MOVE_STATE BEGIN") {
    Stop-Gate "TEMP_MOVEMENT_TELEMETRY_NOT_PRESENT" 13
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ProjectRoot "Saved\Verification\TempMovementTelemetryCompileFix_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Character -Destination (Join-Path $BackupDir "ASCharacter.cpp") -Force
Write-Host "ASCHARACTER_BACKUP=$BackupDir" -ForegroundColor Cyan

$Include = '#include "Components/CapsuleComponent.h"'

if ($Text -match [regex]::Escape($Include)) {
    Write-Host "CAPSULE_COMPONENT_INCLUDE=ALREADY_PRESENT" -ForegroundColor Yellow
}
else {
    $Anchor = '#include "GameFramework/CharacterMovementComponent.h"'
    if ($Text.Contains($Anchor)) {
        $Text = $Text.Replace($Anchor, $Anchor + [Environment]::NewLine + $Include)
    }
    else {
        # Safe fallback: place after ASCharacter include.
        $Anchor2 = '#include "Player/ASCharacter.h"'
        if (-not $Text.Contains($Anchor2)) {
            Stop-Gate "SAFE_INCLUDE_ANCHOR_NOT_FOUND" 20
        }
        $Text = $Text.Replace($Anchor2, $Anchor2 + [Environment]::NewLine + $Include)
    }

    [IO.File]::WriteAllText($Character, $Text, [Text.UTF8Encoding]::new($true))
    Write-Host "CAPSULE_COMPONENT_INCLUDE=ADDED" -ForegroundColor Green
}

$Verify = Get-Content -Raw -LiteralPath $Character
if ($Verify -notmatch [regex]::Escape($Include)) {
    Stop-Gate "CAPSULE_COMPONENT_INCLUDE_VERIFY_FAILED" 21
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 22
}

Write-Host ""
Write-Host "MOVEMENT_TELEMETRY_COMPILE_FIX=PASS" -ForegroundColor Green
Write-Host "FIX=ADDED_COMPONENTS_CAPSULECOMPONENT_INCLUDE" -ForegroundColor Green
Write-Host "NEXT_GATE=REBUILD_PACKAGE_WITH_MOVEMENT_TELEMETRY" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REBUILD + PACKAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PackageScript
$Exit = $LASTEXITCODE

Write-Host ""
Write-Host "PACKAGE_PIPELINE_EXIT=$Exit"

if ($Exit -ne 0) {
    Stop-Gate "PACKAGE_PIPELINE_FAILED_EXIT_$Exit" $(if ($Exit -gt 0) { $Exit } else { 30 })
}

Write-Host ""
Write-Host "MOVEMENT_TELEMETRY_PACKAGE=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_ASWW_RUN_MOVEMENT_TELEMETRY_PS1" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_TELEMETRY" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
