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
    Write-Host "OUTSIDE_ONEDRIVE_PACKAGE=STOPPED" -ForegroundColor Red
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

$BuildScript = Join-Path $ProjectRoot "BuildScripts\build_win64.ps1"
$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"

foreach ($Required in @($BuildScript,$ProjectFile,(Join-Path $UERoot "Engine\Build\BatchFiles\RunUAT.bat"))) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_$Required" 11
    }
}

$Running = @(Get-Process UnrealEditor,UnrealEditor-Cmd,UnrealPak,ShaderCompileWorker -ErrorAction SilentlyContinue)
if ($Running.Count -gt 0) {
    $Running | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_PROCESSES_FIRST" 12
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PATCH BUILD SCRIPT TO STAGE OUTSIDE ONEDRIVE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$StageForUAT = $StageRoot.Replace('\','/')
$Original = Get-Content -Raw -LiteralPath $BuildScript

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ProjectRoot "Saved\Verification\FixBackups\Win64StageOutsideOneDrive_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $BuildScript -Destination (Join-Path $BackupDir "build_win64.ps1") -Force
Write-Host "BUILD_SCRIPT_BACKUP=$BackupDir"

$Patched = $Original
$Already = $false

if ($Patched -match '(?i)-stagingdirectory=') {
    # Replace an existing staging directory token when it is inside a quoted PowerShell argument.
    $NewArg = "-stagingdirectory=$StageForUAT"
    $Patched2 = [regex]::Replace(
        $Patched,
        '(?i)-stagingdirectory=(?:"[^"]*"|''[^'']*''|[^\s"'',\)]+)',
        $NewArg
    )
    if ($Patched2 -eq $Patched) {
        Stop-Gate "EXISTING_STAGINGDIRECTORY_FOUND_BUT_SAFE_REPLACEMENT_FAILED" 20
    }
    $Patched = $Patched2
    $Already = $true
}
else {
    # Preferred form: an argument-array line containing only "-stage",
    $rx = '(?m)^(?<indent>\s*)(?<quote>["''])-stage\k<quote>\s*,?\s*$'
    $m = [regex]::Match($Patched, $rx)
    if ($m.Success) {
        $indent = $m.Groups["indent"].Value
        $quote = $m.Groups["quote"].Value
        $stageLine = $m.Value.TrimEnd()
        $needsComma = -not $stageLine.TrimEnd().EndsWith(",")
        if ($needsComma) { $stageLine = $stageLine + "," }
        $insert = $stageLine + [Environment]::NewLine +
                  $indent + $quote + "-stagingdirectory=$StageForUAT" + $quote + ","
        $Patched = [regex]::Replace($Patched, $rx, [System.Text.RegularExpressions.MatchEvaluator]{ param($x) $insert }, 1)
    }
    else {
        Write-Host "SAFE_PATCH_PATTERN_NOT_FOUND" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "=== BUILD SCRIPT STAGE CONTEXT ===" -ForegroundColor Yellow
        Select-String -LiteralPath $BuildScript -Pattern "BuildCookRun|RunUAT|stage|package|stagingdirectory" -Context 2,4 |
            Select-Object -First 80
        Stop-Gate "BUILD_SCRIPT_REQUIRES_MANUAL_STAGE_ARGUMENT_PATCH" 21
    }
}

if ($Patched -notmatch [regex]::Escape("-stagingdirectory=$StageForUAT")) {
    Stop-Gate "STAGINGDIRECTORY_ARGUMENT_NOT_PRESENT_AFTER_PATCH" 22
}

[IO.File]::WriteAllText($BuildScript, $Patched, [Text.UTF8Encoding]::new($true))

if ($Already) {
    Write-Host "STAGINGDIRECTORY_PATCH=REPLACED_EXISTING" -ForegroundColor Green
} else {
    Write-Host "STAGINGDIRECTORY_PATCH=APPLIED" -ForegroundColor Green
}
Write-Host "STAGINGDIRECTORY=$StageRoot" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PREPARE LOCAL STAGING ROOT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (Test-Path -LiteralPath $StageRoot) {
    $Old = "$StageRoot`_PREV_$Stamp"
    try {
        Move-Item -LiteralPath $StageRoot -Destination $Old
        Write-Host "OLD_LOCAL_STAGE_MOVED=$Old"
    }
    catch {
        Stop-Gate "LOCAL_STAGE_ROOT_LOCKED_$($_.Exception.Message)" 23
    }
}

New-Item -ItemType Directory -Force -Path $StageRoot | Out-Null
Write-Host "LOCAL_STAGE_READY=True" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " GIT WHITESPACE GATE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 24
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REAL WIN64 PACKAGE — LOCAL STAGING" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$EvidenceDir = Join-Path $ProjectRoot "Saved\RuntimeEvidence\Package"
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$Log = Join-Path $EvidenceDir "build_win64_local_stage_$Stamp.log"

Write-Host "PACKAGE_LOG=$Log"
Write-Host "UERoot=$UERoot"
Write-Host "StageRoot=$StageRoot"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BuildScript -UERoot $UERoot 2>&1 |
    Tee-Object -FilePath $Log
$Exit = $LASTEXITCODE

Write-Host ""
Write-Host "PACKAGE_SCRIPT_EXIT=$Exit"

if ($Exit -ne 0) {
    Write-Host ""
    Write-Host "=== PACKAGE FAILURE TAIL ===" -ForegroundColor Yellow
    Get-Content -LiteralPath $Log -Tail 160
    Stop-Gate "BUILD_WIN64_FAILED_EXIT_$Exit" $(if ($Exit -gt 0) { $Exit } else { 30 })
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERIFY PACKAGED OUTPUT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Exes = @(Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending)

if ($Exes.Count -eq 0) {
    Stop-Gate "PACKAGE_EXIT_0_BUT_EXE_NOT_FOUND_UNDER_LOCAL_STAGE" 31
}

$Exe = $Exes[0]
$Paks = @(Get-ChildItem -LiteralPath $StageRoot -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @(".pak",".utoc",".ucas") })

Write-Host "PACKAGED_EXE=$($Exe.FullName)" -ForegroundColor Green
Write-Host "CONTAINER_FILE_COUNT=$($Paks.Count)"

if ($Paks.Count -eq 0) {
    Stop-Gate "PACKAGED_EXE_FOUND_BUT_NO_PAK_UTOC_UCAS_FOUND" 32
}

Write-Host ""
Write-Host "WIN64_PACKAGE=PASS" -ForegroundColor Green
Write-Host "PACKAGED_EXE_VERIFIED=YES" -ForegroundColor Green
Write-Host "LOCAL_STAGING_OUTSIDE_ONEDRIVE=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=PACKAGED_RUNTIME_STARTUP_SMOKE" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
