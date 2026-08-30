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
    Write-Host "PIE_FIX_RERUN=STOPPED" -ForegroundColor Red
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
$Project = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$Map = Join-Path $ProjectRoot "Content\Maps\Jeddah_RedSea_Assault.umap"
$TestScript = Join-Path $ProjectRoot "Content\Python\test_asww_jeddah_pie.py"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$BuildVersion = Join-Path $UERoot "Engine\Build\Build.version"

foreach ($Required in @($PieScript,$Project,$Map,$TestScript,$EditorCmd,$BuildVersion)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_$Required" 11
    }
}

$RunningEditors = @(Get-Process UnrealEditor,UnrealEditor-Cmd -ErrorAction SilentlyContinue)
if ($RunningEditors.Count -gt 0) {
    $RunningEditors | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ALL_UNREAL_EDITOR_PROCESSES_FIRST" 12
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Backup = Join-Path $ProjectRoot "Saved\Verification\FixBackups\PIELogging_$Stamp"
New-Item -ItemType Directory -Force -Path $Backup | Out-Null
Copy-Item -LiteralPath $PieScript -Destination (Join-Path $Backup "run_jeddah_pie_smoke.ps1") -Force
Write-Host "PIE_WRAPPER_BACKUP=$Backup" -ForegroundColor Green

$Wrapper = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$UERoot,
    [string]$ExpectedBranch = "codex/asww-development",
    [int]$TimeoutSeconds = 600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$MapFile = Join-Path $ProjectRoot "Content\Maps\Jeddah_RedSea_Assault.umap"
$TestScript = Join-Path $ProjectRoot "Content\Python\test_asww_jeddah_pie.py"
$BuildVersionPath = Join-Path $UERoot "Engine\Build\Build.version"
$UnrealEditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$LogRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\PIE"

function Find-FirstFile {
    param([string[]]$Candidates)
    foreach ($Candidate in $Candidates) {
        if ([IO.File]::Exists($Candidate)) { return $Candidate }
    }
    return $null
}

function Test-UnrealPackageFile {
    param([string]$Path)
    if (-not [IO.File]::Exists($Path) -or (Get-Item -LiteralPath $Path).Length -lt 32) {
        return $false
    }
    $Stream = [IO.File]::OpenRead($Path)
    try {
        $Reader = [IO.BinaryReader]::new($Stream)
        try { return $Reader.ReadUInt32() -eq [Convert]::ToUInt32("9E2A83C1",16) }
        finally { $Reader.Dispose() }
    }
    finally { $Stream.Dispose() }
}

$CurrentBranch = (& git -C $ProjectRoot branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $CurrentBranch -ne $ExpectedBranch) {
    throw "PIE smoke testing requires '$ExpectedBranch'; current branch is '$CurrentBranch'."
}
if (-not [IO.File]::Exists($ProjectFile) -or -not [IO.File]::Exists($TestScript)) {
    throw "Project descriptor or Jeddah PIE test is missing."
}
if (-not [IO.File]::Exists($BuildVersionPath) -or -not [IO.File]::Exists($UnrealEditorCmd)) {
    throw "A complete UE 5.8 installation with UnrealEditor-Cmd.exe is required under '$UERoot'."
}
if (-not (Test-UnrealPackageFile $MapFile)) {
    Write-Output "PIE_RESULT=BLOCKED_NO_REAL_JEDDAH_UMAP"
    exit 2
}

$BuildVersion = Get-Content -Raw -LiteralPath $BuildVersionPath | ConvertFrom-Json
$DetectedVersion = "$($BuildVersion.MajorVersion).$($BuildVersion.MinorVersion).$($BuildVersion.PatchVersion)"
if ($BuildVersion.MajorVersion -ne 5 -or $BuildVersion.MinorVersion -ne 8) {
    throw "UE 5.8 is required; detected '$DetectedVersion'."
}

$PythonAutomationPlugin = Find-FirstFile @(
    (Join-Path $UERoot "Engine\Plugins\Tests\PythonAutomationTest\PythonAutomationTest.uplugin"),
    (Join-Path $UERoot "Engine\Plugins\Experimental\PythonAutomationTest\PythonAutomationTest.uplugin")
)
if (-not $PythonAutomationPlugin) {
    Write-Output "PYTHON_AUTOMATION_TEST_PLUGIN=NOT_FOUND"
    Write-Output "PIE_RESULT=BLOCKED_TEST_PLUGIN_MISSING"
    exit 3
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$LogPath = Join-Path $LogRoot "pie_$RunId.log"
$ErrPath = Join-Path $LogRoot "pie_$RunId.stderr.log"
$ReportPath = Join-Path $LogRoot "Report_$RunId"

# Use forward-slash paths for Unreal command-line arguments.
$ProjectForUE = $ProjectFile.Replace('\','/')
$ReportForUE = $ReportPath.Replace('\','/')

$Arguments = @(
    $ProjectForUE,
    "-Unattended",
    "-NoSplash",
    "-NoSound",
    "-NullRHI",
    "-NoSourceControl",
    "-ExecCmds=Automation RunTest Group:ASWWPIE;Quit",
    "-TestExit=Automation Test Queue Empty",
    "-ReportExportPath=$ReportForUE",
    "-stdout",
    "-FullStdOutLogOutput"
)

Write-Output "BRANCH=$CurrentBranch"
Write-Output "UE_VERSION=$DetectedVersion"
Write-Output "UE_ROOT=$UERoot"
Write-Output "PYTHON_AUTOMATION_TEST_PLUGIN=$PythonAutomationPlugin"
Write-Output "PIE_SCOPE=STARTUP_POSSESSION_ACTOR_PRESENCE_ONLY"
Write-Output "COMMAND=`"$UnrealEditorCmd`" $($Arguments -join ' ')"
Write-Output "PIE_LOG=$LogPath"
Write-Output "PIE_STDERR=$ErrPath"
Write-Output "PIE_REPORT=$ReportPath"

$Process = Start-Process `
    -FilePath $UnrealEditorCmd `
    -ArgumentList $Arguments `
    -WorkingDirectory $ProjectRoot `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $LogPath `
    -RedirectStandardError $ErrPath

if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    $Process.WaitForExit(5000) | Out-Null
    Write-Output "PROCESS_CLEANUP=TERMINATED_AFTER_TIMEOUT"
    Write-Output "PIE_RESULT=FAIL_TIMEOUT"
    exit 4
}

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

$LogText = if ([IO.File]::Exists($LogPath)) { Get-Content -Raw -LiteralPath $LogPath } else { "" }

$PassMarker = $LogText -match "ASWW_PIE_SMOKE=PASS"
$AutomationSeen = $LogText -match "Automation"
$ASWWSeen = $LogText -match "ASWW_"

Write-Output "MARKER_ASWW_PIE_SMOKE_PASS=$PassMarker"
Write-Output "AUTOMATION_OUTPUT_SEEN=$AutomationSeen"
Write-Output "ASWW_OUTPUT_SEEN=$ASWWSeen"

if (-not $PassMarker) {
    Write-Output "PROCESS_CLEANUP=PROCESS_EXITED"
    Write-Output "PIE_RESULT=FAIL_MISSING_TEST_SUCCESS_MARKER"
    Write-Output ""
    Write-Output "=== PIE ROOT CAUSE ==="
    Select-String -LiteralPath $LogPath `
        -Pattern "ASWW_|Automation|LogPython:\s*Error|Traceback|RuntimeError:|AttributeError:|TypeError:|Error:|Warning:|failed|missing|PlayerStart|ASGameMode|Possess|spawn|WorldPartition|World Partition" `
        -Context 4,14 |
        Select-Object -First 120
    exit 5
}

Write-Output "PROCESS_CLEANUP=PROCESS_EXITED"
Write-Output "PIE_RESULT=PASS_STARTUP_SMOKE_ONLY"
Write-Output "GAMEPLAY_FEATURE_MATRIX=NOT_TESTED_BY_THIS_SMOKE"
exit 0
'@

[IO.File]::WriteAllText($PieScript, $Wrapper, [Text.UTF8Encoding]::new($false))
Write-Host "PIE_LOGGING_PATCH=APPLIED" -ForegroundColor Green

Write-Host ""
Write-Host "=== DIFF CHECK ===" -ForegroundColor Cyan
& git -c core.safecrlf=false --no-pager diff --check
if ($LASTEXITCODE -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED_AFTER_PIE_WRAPPER_PATCH" 20
}
Write-Host "DIFF_CHECK=PASS" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RERUN PIE STARTUP SMOKE ONLY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PieScript -UERoot $UERoot -TimeoutSeconds $TimeoutSeconds
$Exit = $LASTEXITCODE

Write-Host ""
Write-Host "PIE_RERUN_EXIT=$Exit"

if ($Exit -eq 0) {
    Write-Host "PIE_STARTUP_SMOKE=PASS_STARTUP_ONLY" -ForegroundColor Green
    Write-Host "NEXT_GATE=WIN64_PACKAGE" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
    exit 0
}

Write-Host "PIE_STARTUP_SMOKE=FAIL_EXIT_$Exit" -ForegroundColor Red
Write-Host "CURRENT_BLOCKER=READ_NEW_PIE_ROOT_CAUSE_OUTPUT" -ForegroundColor Red
Write-Host "DO_NOT_RERUN_VALIDATOR_OR_PROMOTION" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
exit $Exit
