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
    "-ExecCmds=Automation RunTest Editor.Python.ArabiaStrikeWorldWar.test_asww_jeddah_pie;Quit",
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