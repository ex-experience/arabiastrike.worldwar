[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [int]$TimeoutSeconds = 600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PIE_EXITCODE_FIX=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_RERUN_VALIDATOR_OR_PROMOTION" -ForegroundColor Yellow
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

Set-Location $ProjectRoot

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

$PieScript = Join-Path $ProjectRoot "BuildScripts\run_jeddah_pie_smoke.ps1"
if (-not (Test-Path -LiteralPath $PieScript -PathType Leaf)) {
    Stop-Gate "PIE_SCRIPT_NOT_FOUND" 11
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Backup = Join-Path $ProjectRoot "Saved\Verification\FixBackups\PIEExitCodeGuard_$Stamp"
New-Item -ItemType Directory -Force -Path $Backup | Out-Null
Copy-Item -LiteralPath $PieScript -Destination (Join-Path $Backup "run_jeddah_pie_smoke.ps1") -Force
Write-Host "PIE_WRAPPER_BACKUP=$Backup" -ForegroundColor Green

$Text = [IO.File]::ReadAllText($PieScript)

# Replace the fragile post-WaitForExit block with a guarded exit-code read.
$Old = @'
$Process.Refresh()
Write-Output "EDITOR_EXIT_CODE=$($Process.ExitCode)"

# Append stderr into the evidence log after process exit.
if ([IO.File]::Exists($ErrPath) -and (Get-Item -LiteralPath $ErrPath).Length -gt 0) {
    Add-Content -LiteralPath $LogPath -Value "`r`n=== STDERR ==="
    Get-Content -LiteralPath $ErrPath | Add-Content -LiteralPath $LogPath
}

if ($Process.ExitCode -ne 0) {
    Write-Output "PROCESS_CLEANUP=PROCESS_EXITED"
    Write-Output "PIE_RESULT=FAIL_EDITOR_EXIT_$($Process.ExitCode)"
    exit $Process.ExitCode
}
'@

$New = @'
# Complete async stdout/stderr drain, then read the real process exit code.
$Process.WaitForExit()
$Process.Refresh()

$EditorExitCode = $null
try {
    $EditorExitCode = [int]$Process.ExitCode
}
catch {
    $EditorExitCode = $null
}

if ($null -eq $EditorExitCode) {
    Write-Output "EDITOR_EXIT_CODE=NULL"
    Write-Output "PROCESS_CLEANUP=PROCESS_EXITED"
    Write-Output "PIE_RESULT=FAIL_EDITOR_EXITCODE_UNAVAILABLE"
    exit 6
}

Write-Output "EDITOR_EXIT_CODE=$EditorExitCode"

# Append stderr into the evidence log after process exit.
if ([IO.File]::Exists($ErrPath) -and (Get-Item -LiteralPath $ErrPath).Length -gt 0) {
    Add-Content -LiteralPath $LogPath -Value "`r`n=== STDERR ==="
    Get-Content -LiteralPath $ErrPath | Add-Content -LiteralPath $LogPath
}

if ($EditorExitCode -ne 0) {
    Write-Output "PROCESS_CLEANUP=PROCESS_EXITED"
    Write-Output "PIE_RESULT=FAIL_EDITOR_EXIT_$EditorExitCode"
    exit $EditorExitCode
}
'@

if (-not $Text.Contains($Old)) {
    Stop-Gate "EXPECTED_PIE_EXITCODE_BLOCK_NOT_FOUND" 12
}

$Text = $Text.Replace($Old, $New)
[IO.File]::WriteAllText($PieScript, $Text, [Text.UTF8Encoding]::new($false))
Write-Host "PIE_EXITCODE_GUARD_PATCH=APPLIED" -ForegroundColor Green

Write-Host ""
Write-Host "=== DIFF CHECK ===" -ForegroundColor Cyan
& git -c core.safecrlf=false --no-pager diff --check
if ($LASTEXITCODE -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED_AFTER_PIE_EXITCODE_PATCH" 20
}
Write-Host "DIFF_CHECK=PASS" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RERUN PIE STARTUP SMOKE — STRICT PASS MARKER REQUIRED" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$OuterLog = Join-Path $ProjectRoot "Saved\RuntimeEvidence\PIE\pie_wrapper_rerun_$Stamp.txt"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PieScript -UERoot $UERoot -TimeoutSeconds $TimeoutSeconds 2>&1 |
    Tee-Object -FilePath $OuterLog

$InnerExit = $LASTEXITCODE
$OuterText = if (Test-Path -LiteralPath $OuterLog) { Get-Content -Raw -LiteralPath $OuterLog } else { "" }

$PassMarker = $OuterText -match "PIE_RESULT=PASS_STARTUP_SMOKE_ONLY"
$SmokeMarker = $OuterText -match "ASWW_PIE_SMOKE=PASS"
$ExitLine = ($OuterText -split "`r?`n" | Where-Object { $_ -match '^EDITOR_EXIT_CODE=' } | Select-Object -Last 1)

Write-Host ""
Write-Host "PIE_INNER_EXIT=$InnerExit"
if ($ExitLine) { Write-Host $ExitLine }
Write-Host "WRAPPER_PASS_MARKER=$PassMarker"
Write-Host "ASWW_SMOKE_MARKER=$SmokeMarker"
Write-Host "PIE_WRAPPER_LOG=$OuterLog"

if ($InnerExit -eq 0 -and $PassMarker) {
    Write-Host ""
    Write-Host "PIE_STARTUP_SMOKE=PASS_STARTUP_ONLY" -ForegroundColor Green
    Write-Host "NEXT_GATE=WIN64_PACKAGE" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "=== STRICT PIE FAILURE EVIDENCE ===" -ForegroundColor Yellow
Get-Content -LiteralPath $OuterLog -Tail 120

Stop-Gate "PIE_NOT_PROVEN_AFTER_EXITCODE_GUARD" $(if ($InnerExit -ne 0) { $InnerExit } else { 7 })
