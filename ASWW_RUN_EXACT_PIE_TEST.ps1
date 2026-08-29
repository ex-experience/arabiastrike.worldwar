[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "EXACT_PIE_TEST=STOPPED" -ForegroundColor Red
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

$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$MapFile = Join-Path $ProjectRoot "Content\Maps\Jeddah_RedSea_Assault.umap"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$BuildVersion = Join-Path $UERoot "Engine\Build\Build.version"
$PieRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\PIE"

foreach ($Required in @($ProjectFile,$MapFile,$EditorCmd,$BuildVersion)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_$Required" 11
    }
}

$RunningEditors = @(Get-Process UnrealEditor,UnrealEditor-Cmd -ErrorAction SilentlyContinue)
if ($RunningEditors.Count -gt 0) {
    $RunningEditors | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ALL_UNREAL_EDITOR_PROCESSES_FIRST" 12
}

$V = Get-Content -Raw -LiteralPath $BuildVersion | ConvertFrom-Json
$UEVersion = "$($V.MajorVersion).$($V.MinorVersion).$($V.PatchVersion)"
Write-Host "UE_VERSION=$UEVersion"
if ($V.MajorVersion -ne 5 -or $V.MinorVersion -ne 8) {
    Stop-Gate "UE_5_8_REQUIRED_FOUND_$UEVersion" 13
}

$TestName = "Editor.Python.ArabiaStrikeWorldWar.test_asww_jeddah_pie"

New-Item -ItemType Directory -Force -Path $PieRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogPath = Join-Path $PieRoot "pie_exact_$Stamp.log"
$ReportPath = Join-Path $PieRoot "ExactReport_$Stamp"

$ProjectForUE = $ProjectFile.Replace('\','/')
$ReportForUE = $ReportPath.Replace('\','/')

$Arguments = @(
    $ProjectForUE,
    "-Unattended",
    "-NoSplash",
    "-NoSound",
    "-NullRHI",
    "-NoSourceControl",
    "-ExecCmds=Automation RunTest $TestName;Quit",
    "-TestExit=Automation Test Queue Empty",
    "-ReportExportPath=$ReportForUE",
    "-stdout",
    "-FullStdOutLogOutput"
)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " DIRECT EXACT PIE AUTOMATION TEST" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEST_NAME=$TestName"
Write-Host "PIE_LOG=$LogPath"
Write-Host "PIE_REPORT=$ReportPath"
Write-Host "COMMAND=`"$EditorCmd`" $($Arguments -join ' ')"

& $EditorCmd @Arguments 2>&1 | Tee-Object -FilePath $LogPath
$EditorExit = $LASTEXITCODE

$LogText = if (Test-Path -LiteralPath $LogPath) {
    Get-Content -Raw -LiteralPath $LogPath
} else {
    ""
}

$SmokePass = $LogText -match "ASWW_PIE_SMOKE=PASS"
$TestNameSeen = $LogText -match [regex]::Escape($TestName)
$PythonError = $LogText -match "LogPython:\s*Error|Traceback|RuntimeError:|AttributeError:|TypeError:"
$AutomationFailure = $LogText -match "Test Completed.*Fail|Test Failed|Automation.*Fail|Error:.*Automation"

Write-Host ""
Write-Host "EDITOR_EXIT_CODE=$EditorExit"
Write-Host "EXACT_TEST_NAME_SEEN=$TestNameSeen"
Write-Host "ASWW_PIE_SMOKE_PASS=$SmokePass"
Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "AUTOMATION_FAILURE_SEEN=$AutomationFailure"
Write-Host "REPORT_DIR_EXISTS=$(Test-Path -LiteralPath $ReportPath)"

if ($EditorExit -eq 0 -and $SmokePass) {
    Write-Host ""
    Write-Host "EXACT_PIE_TEST=PASS" -ForegroundColor Green
    Write-Host "PIE_STARTUP_SMOKE=PASS_STARTUP_ONLY" -ForegroundColor Green
    Write-Host "NEXT_GATE=PATCH_PIE_WRAPPER_TO_EXACT_TEST_THEN_WIN64_PACKAGE" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "=== EXACT PIE TEST ROOT CAUSE ===" -ForegroundColor Yellow
Select-String -LiteralPath $LogPath `
    -Pattern "Editor\.Python\.ArabiaStrikeWorldWar\.test_asww_jeddah_pie|ASWW_PIE|LogPython:\s*Error|Traceback|RuntimeError:|AttributeError:|TypeError:|Automation|Test Started|Test Completed|Test Failed|Error:|failed|missing|PlayerStart|ASGameMode|Possess|spawn|WorldPartition|World Partition" `
    -Context 5,16 |
    Select-Object -First 180

Stop-Gate "EXACT_PIE_TEST_NOT_PROVEN" $(if ($EditorExit -ne 0) { $EditorExit } else { 5 })
