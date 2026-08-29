[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$Phase2Script = "ASWW_OFFLINE_PHASE2_POST_BUILD.ps1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Now([string]$Reason, [int]$Code=1) {
    Write-Host ""
    Write-Host "RESUME=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Normalize-Trailing-NewlineOnly([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-Now "FILE_NOT_FOUND_$Path" 10
    }

    $Bytes = [IO.File]::ReadAllBytes($Path)
    if ($Bytes.Length -eq 0) {
        return
    }

    # Detect the file's existing newline convention without rewriting any other bytes.
    $UseCRLF = $false
    for ($i = 0; $i -lt ($Bytes.Length - 1); $i++) {
        if ($Bytes[$i] -eq 13 -and $Bytes[$i + 1] -eq 10) {
            $UseCRLF = $true
            break
        }
    }

    # Remove only trailing CR/LF bytes.
    $End = $Bytes.Length
    while ($End -gt 0 -and ($Bytes[$End - 1] -eq 10 -or $Bytes[$End - 1] -eq 13)) {
        $End--
    }

    $Newline = if ($UseCRLF) { [byte[]](13,10) } else { [byte[]](10) }
    $Output = New-Object byte[] ($End + $Newline.Length)

    if ($End -gt 0) {
        [Array]::Copy($Bytes, 0, $Output, 0, $End)
    }
    [Array]::Copy($Newline, 0, $Output, $End, $Newline.Length)

    [IO.File]::WriteAllBytes($Path, $Output)
}

Set-Location $ProjectRoot

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Now "WRONG_BRANCH_$Branch" 20
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Backup = Join-Path $ProjectRoot "Saved\Verification\FixBackups\EOF_WHITESPACE_$Stamp"
New-Item -ItemType Directory -Force -Path $Backup | Out-Null

$Targets = @(
    "Source\ArabiaStrikeWorldWar\Public\Combat\ASWeaponInventoryComponent.h",
    "Source\ArabiaStrikeWorldWar\Public\Vehicles\ASVehiclePawn.h"
)

Write-Host ""
Write-Host "=== BACKUP + FIX ONLY CONFIRMED EOF BLANK LINES ===" -ForegroundColor Cyan

foreach ($Rel in $Targets) {
    $Full = Join-Path $ProjectRoot $Rel
    $Dest = Join-Path $Backup $Rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
    Copy-Item -LiteralPath $Full -Destination $Dest -Force
    Normalize-Trailing-NewlineOnly $Full
    Write-Host "EOF_FIXED=$Rel" -ForegroundColor Green
}
Write-Host "BACKUP=$Backup" -ForegroundColor Green

Write-Host ""
Write-Host "=== ROBUST GIT DIFF CHECK ===" -ForegroundColor Cyan

$Out = Join-Path $ProjectRoot "Saved\Verification\Local\diffcheck_after_eof_fix_stdout.txt"
$Err = Join-Path $ProjectRoot "Saved\Verification\Local\diffcheck_after_eof_fix_stderr.txt"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Out) | Out-Null
Remove-Item $Out,$Err -Force -ErrorAction SilentlyContinue

$Args = @("-c","core.safecrlf=false","--no-pager","diff","--check")
$Proc = Start-Process -FilePath "git.exe" -ArgumentList $Args -RedirectStandardOutput $Out -RedirectStandardError $Err -Wait -PassThru -NoNewWindow

if ((Test-Path $Out) -and ((Get-Item $Out).Length -gt 0)) {
    Write-Host "WHITESPACE_ERRORS:" -ForegroundColor Red
    Get-Content $Out
}
else {
    Write-Host "WHITESPACE_ERRORS=NONE" -ForegroundColor Green
}

if ((Test-Path $Err) -and ((Get-Item $Err).Length -gt 0)) {
    Write-Host "GIT_STDERR:" -ForegroundColor Yellow
    Get-Content $Err | Select-Object -First 40
}

Write-Host "DIFF_CHECK_EXIT=$($Proc.ExitCode)" -ForegroundColor Cyan

if ($Proc.ExitCode -ne 0) {
    Stop-Now "GIT_DIFF_CHECK_STILL_FAILS" $Proc.ExitCode
}

Write-Host ""
Write-Host "DIFF_CHECK=PASS" -ForegroundColor Green

$Phase2Path = if ([IO.Path]::IsPathRooted($Phase2Script)) {
    $Phase2Script
} else {
    Join-Path $ProjectRoot $Phase2Script
}

if (-not (Test-Path -LiteralPath $Phase2Path -PathType Leaf)) {
    Stop-Now "PHASE2_SCRIPT_NOT_FOUND_$Phase2Path" 30
}

# Create an offline-safe patched copy of Phase 2.
# The only functional change is that git diff/check/stat calls use per-command
# core.safecrlf=false so CRLF advisory messages cannot trip PowerShell.
$Phase2Text = [IO.File]::ReadAllText($Phase2Path)

$Phase2Text = $Phase2Text.Replace(
    '& git diff --check',
    '& git -c core.safecrlf=false diff --check'
)
$Phase2Text = $Phase2Text.Replace(
    '& git --no-pager diff --stat',
    '& git -c core.safecrlf=false --no-pager diff --stat'
)
$Phase2Text = $Phase2Text.Replace(
    '& git -C $ProjectRoot diff --binary',
    '& git -c core.safecrlf=false -C $ProjectRoot diff --binary'
)
$Phase2Text = $Phase2Text.Replace(
    '& git -C $ProjectRoot diff --cached --binary',
    '& git -c core.safecrlf=false -C $ProjectRoot diff --cached --binary'
)
$Phase2Text = $Phase2Text.Replace(
    '& git -C $ProjectRoot diff --stat',
    '& git -c core.safecrlf=false -C $ProjectRoot diff --stat'
)
$Phase2Text = $Phase2Text.Replace(
    '& git -C $ProjectRoot diff --name-only',
    '& git -c core.safecrlf=false -C $ProjectRoot diff --name-only'
)
$Phase2Text = $Phase2Text.Replace(
    '& git -C $ProjectRoot diff --cached --name-only',
    '& git -c core.safecrlf=false -C $ProjectRoot diff --cached --name-only'
)

$PatchedPhase2 = Join-Path $ProjectRoot "ASWW_OFFLINE_PHASE2_POST_BUILD_SAFECRLF.ps1"
[IO.File]::WriteAllText($PatchedPhase2, $Phase2Text, [Text.UTF8Encoding]::new($true))

Write-Host ""
Write-Host "PATCHED_PHASE2=$PatchedPhase2" -ForegroundColor Green
Write-Host "INTERNET_REQUIRED=NO" -ForegroundColor Green
Write-Host ""
Write-Host "=== STARTING PHASE 2 FROM SAVED EDITOR+GAME PASS ===" -ForegroundColor Cyan

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PatchedPhase2
$Phase2Exit = $LASTEXITCODE

Write-Host ""
Write-Host "PHASE2_EXIT_CODE=$Phase2Exit"

if ($Phase2Exit -ne 0) {
    Write-Host "PHASE2=STOPPED_AT_NEXT_REAL_GATE" -ForegroundColor Yellow
    Write-Host "REVIEW_THE_BLOCKER_ABOVE" -ForegroundColor Yellow
    exit $Phase2Exit
}

Write-Host "PHASE2=PASS_AUTOMATED_GATES" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_OR_PUSH_UNTIL_FINAL_DIFF_REVIEW" -ForegroundColor Yellow
