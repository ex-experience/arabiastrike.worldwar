[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Set-Location $ProjectRoot

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    throw "WRONG_BRANCH_STOP"
}

$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$ConfigFile = Join-Path $ProjectRoot "Config\DefaultEngine.ini"
$TestScript = Join-Path $ProjectRoot "Content\Python\test_asww_jeddah_pie.py"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$LogRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\PIE"

foreach ($Required in @($ProjectFile,$ConfigFile,$TestScript,$EditorCmd)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        throw "MISSING=$Required"
    }
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ListLog = Join-Path $LogRoot "automation_list_$Stamp.log"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PROJECT PLUGIN STATE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$UProjectText = Get-Content -Raw -LiteralPath $ProjectFile
$PluginMention = $UProjectText -match '"Name"\s*:\s*"PythonAutomationTest"'
$PluginEnabled = $UProjectText -match '"Name"\s*:\s*"PythonAutomationTest"[\s\S]{0,200}?"Enabled"\s*:\s*true'

Write-Host "PYTHON_AUTOMATION_PLUGIN_MENTIONED=$PluginMention"
Write-Host "PYTHON_AUTOMATION_PLUGIN_ENABLED_TRUE=$PluginEnabled"

Select-String -LiteralPath $ProjectFile -Pattern "PythonAutomationTest|PythonScriptPlugin|Plugins" -Context 2,4 |
    Select-Object -First 60

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ASWWPIE GROUP CONFIG" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$GroupMatches = Select-String -LiteralPath $ConfigFile -Pattern "ASWWPIE|\+Groups=|Groups=" -Context 2,3
if ($GroupMatches) {
    $GroupMatches | Select-Object -First 80
} else {
    Write-Host "ASWWPIE_GROUP_CONFIG=NOT_FOUND" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PYTHON TEST FILE REGISTRATION SURFACE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "TEST_SCRIPT=$TestScript"
Write-Host "TEST_FILENAME=$(Split-Path $TestScript -Leaf)"

Select-String -LiteralPath $TestScript `
    -Pattern "ASWWPIE|ASWW_PIE_SMOKE|AutomationScheduler|unreal\.log|log\(|def |class |assert|raise " `
    -Context 3,8 |
    Select-Object -First 160

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REAL AUTOMATION LIST DISCOVERY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$ProjectForUE = $ProjectFile.Replace('\','/')
$Args = @(
    $ProjectForUE,
    "-Unattended",
    "-NoSplash",
    "-NoSound",
    "-NullRHI",
    "-NoSourceControl",
    "-ExecCmds=Automation List;Quit",
    "-stdout",
    "-FullStdOutLogOutput"
)

Write-Host "AUTOMATION_LIST_LOG=$ListLog" -ForegroundColor Cyan
& $EditorCmd @Args 2>&1 | Tee-Object -FilePath $ListLog | Out-Null
$Exit = $LASTEXITCODE
Write-Host "AUTOMATION_LIST_EDITOR_EXIT=$Exit"

Write-Host ""
Write-Host "=== DISCOVERED ASWW / PYTHON TEST NAMES ===" -ForegroundColor Yellow

$Matches = Select-String -LiteralPath $ListLog `
    -Pattern "Editor\.Python|Python\..*ASWW|asww_jeddah_pie|ASWWPIE|test_asww_jeddah_pie|No automation tests matched" `
    -Context 2,5

if ($Matches) {
    $Matches | Select-Object -First 180
} else {
    Write-Host "DISCOVERED_ASWW_TEST_MATCHES=NONE" -ForegroundColor Red
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "PYTHON_AUTOMATION_PLUGIN_ENABLED_TRUE=$PluginEnabled"
if ($GroupMatches) {
    Write-Host "ASWWPIE_GROUP_CONFIG=FOUND"
} else {
    Write-Host "ASWWPIE_GROUP_CONFIG=NOT_FOUND"
}
Write-Host "AUTOMATION_LIST_EDITOR_EXIT=$Exit"
Write-Host "AUTOMATION_LIST_LOG=$ListLog"

if ($Matches) {
    Write-Host "DISCOVERED_ASWW_TEST_MATCHES=FOUND" -ForegroundColor Green
} else {
    Write-Host "DISCOVERED_ASWW_TEST_MATCHES=NONE" -ForegroundColor Red
}

Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_RERUN_VALIDATOR_OR_PROMOTION" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
