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
    Write-Host "STAGINGDIR_REPAIR_PACKAGE=STOPPED" -ForegroundColor Red
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
if (-not (Test-Path -LiteralPath $BuildScript -PathType Leaf)) {
    Stop-Gate "MISSING_BUILD_WIN64_PS1" 11
}

$Character = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"
if (-not (Test-Path -LiteralPath $Character -PathType Leaf)) {
    Stop-Gate "MISSING_ASCHARACTER_CPP" 12
}

$CharText = Get-Content -Raw -LiteralPath $Character
if ($CharText -notmatch "ASWW_TELEMETRY CHARACTER_BEGIN") {
    Stop-Gate "TEMP_PLAYER_CONTROL_TELEMETRY_NOT_PRESENT" 13
}
Write-Host "TEMP_PLAYER_CONTROL_TELEMETRY=PRESENT" -ForegroundColor Green

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ProjectRoot "Saved\Verification\FixBackups\RepairStageDir_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $BuildScript -Destination (Join-Path $BackupDir "build_win64.ps1") -Force
Write-Host "BUILD_SCRIPT_BACKUP=$BackupDir"

$Original = Get-Content -Raw -LiteralPath $BuildScript
$StageForUAT = $StageRoot.Replace('\','/')

Write-Host ""
Write-Host "=== EXISTING STAGINGDIRECTORY CONTEXT ===" -ForegroundColor Yellow
Select-String -LiteralPath $BuildScript -Pattern "stagingdirectory|BuildCookRun|RunUAT|stage" -Context 1,2 |
    Select-Object -First 100

$Patched = $Original

# First, normalize any existing -stagingdirectory=<value> token.
$Patched = [regex]::Replace(
    $Patched,
    '(?i)-stagingdirectory=(?:"[^"]*"|''[^'']*''|[^\s,"''\)\]]+)',
    "-stagingdirectory=$StageForUAT"
)

# If an existing token remains but was not normalized (e.g. interpolation edge case),
# replace only the value portion up to the enclosing quote/comma/whitespace.
if ($Patched -match '(?i)-stagingdirectory=' -and
    $Patched -notmatch [regex]::Escape("-stagingdirectory=$StageForUAT")) {
    $Patched = [regex]::Replace(
        $Patched,
        '(?i)(-stagingdirectory=)[^"''\r\n,\)\]]+',
        "`$1$StageForUAT"
    )
}

# If no stagingdirectory existed at all, insert it after a standalone "-stage" argument.
if ($Patched -notmatch '(?i)-stagingdirectory=') {
    $rx = '(?m)^(?<indent>\s*)(?<q>["''])-stage\k<q>\s*,?\s*$'
    $m = [regex]::Match($Patched, $rx)
    if (-not $m.Success) {
        Write-Host "SAFE_STAGE_INSERT_PATTERN_NOT_FOUND" -ForegroundColor Red
        Stop-Gate "CANNOT_INSERT_STAGINGDIRECTORY_SAFELY" 20
    }

    $line = $m.Value.TrimEnd()
    if (-not $line.EndsWith(",")) { $line += "," }
    $indent = $m.Groups["indent"].Value
    $q = $m.Groups["q"].Value
    $insert = $line + [Environment]::NewLine +
              $indent + $q + "-stagingdirectory=$StageForUAT" + $q + ","

    $Patched = [regex]::Replace(
        $Patched,
        $rx,
        [System.Text.RegularExpressions.MatchEvaluator]{ param($x) $insert },
        1
    )
}

if ($Patched -notmatch [regex]::Escape("-stagingdirectory=$StageForUAT")) {
    Stop-Gate "STAGINGDIRECTORY_NORMALIZATION_FAILED" 21
}

[IO.File]::WriteAllText($BuildScript, $Patched, [Text.UTF8Encoding]::new($true))

Write-Host ""
Write-Host "STAGINGDIRECTORY_REPAIR=PASS" -ForegroundColor Green
Write-Host "STAGINGDIRECTORY=$StageRoot" -ForegroundColor Green

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 22
}

# Ensure no game/build process is holding output.
$Active = @(Get-Process ArabiaStrikeWorldWar,UnrealEditor,UnrealEditor-Cmd,UnrealPak -ErrorAction SilentlyContinue)
if ($Active.Count -gt 0) {
    $Active | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ACTIVE_UNREAL_OR_GAME_PROCESSES_FIRST" 23
}

# Move an old local stage out of the way instead of deleting it.
if (Test-Path -LiteralPath $StageRoot) {
    $Old = "$StageRoot`_PREV_$Stamp"
    try {
        Move-Item -LiteralPath $StageRoot -Destination $Old
        Write-Host "OLD_STAGE_MOVED=$Old"
    }
    catch {
        Stop-Gate "LOCAL_STAGE_ROOT_LOCKED_$($_.Exception.Message)" 24
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REBUILD + PACKAGE WIN64 WITH TELEMETRY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$EvidenceDir = Join-Path $ProjectRoot "Saved\RuntimeEvidence\Package"
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$Log = Join-Path $EvidenceDir "telemetry_package_$Stamp.log"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BuildScript -UERoot $UERoot 2>&1 |
    Tee-Object -FilePath $Log
$Exit = $LASTEXITCODE

Write-Host ""
Write-Host "PACKAGE_SCRIPT_EXIT=$Exit"

if ($Exit -ne 0) {
    Write-Host "=== PACKAGE FAILURE TAIL ===" -ForegroundColor Yellow
    Get-Content -LiteralPath $Log -Tail 160
    Stop-Gate "BUILD_WIN64_FAILED_EXIT_$Exit" $(if ($Exit -gt 0) { $Exit } else { 30 })
}

$Exes = @(Get-ChildItem -LiteralPath $StageRoot -Filter "ArabiaStrikeWorldWar.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending)

if ($Exes.Count -eq 0) {
    Stop-Gate "PACKAGE_EXIT_0_BUT_PACKAGED_EXE_NOT_FOUND" 31
}

$Containers = @(Get-ChildItem -LiteralPath $StageRoot -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @(".pak",".utoc",".ucas") })

if ($Containers.Count -eq 0) {
    Stop-Gate "PACKAGED_EXE_FOUND_BUT_NO_CONTAINER_FILES" 32
}

Write-Host "PACKAGED_EXE=$($Exes[0].FullName)" -ForegroundColor Green
Write-Host "CONTAINER_FILE_COUNT=$($Containers.Count)"
Write-Host "WIN64_PACKAGE_WITH_TELEMETRY=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=RUN_PLAYER_CONTROL_TELEMETRY" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_TELEMETRY" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
