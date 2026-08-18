[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$UERoot,
    [string]$ExpectedBranch = "codex/asww-development",
    [ValidateRange(60, 1800)][int]$TimeoutSeconds = 600
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
        if ([IO.File]::Exists($Candidate)) {
            return $Candidate
        }
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
        try {
            return $Reader.ReadUInt32() -eq [Convert]::ToUInt32("9E2A83C1", 16)
        }
        finally {
            $Reader.Dispose()
        }
    }
    finally {
        $Stream.Dispose()
    }
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
$ReportPath = Join-Path $LogRoot "Report_$RunId"
$Arguments = @(
    $ProjectFile,
    "-Unattended",
    "-NoSplash",
    "-NoSound",
    "-NullRHI",
    "-NoSourceControl",
    "-ExecCmds=Automation RunTest Group:ASWWPIE;Quit",
    "-TestExit=Automation Test Queue Empty",
    "-ReportExportPath=$ReportPath",
    "-Log=$LogPath"
)

Write-Output "BRANCH=$CurrentBranch"
Write-Output "UE_VERSION=$DetectedVersion"
Write-Output "UE_ROOT=$UERoot"
Write-Output "PYTHON_AUTOMATION_TEST_PLUGIN=$PythonAutomationPlugin"
Write-Output "PIE_SCOPE=STARTUP_POSSESSION_ACTOR_PRESENCE_ONLY"
Write-Output "COMMAND=`"$UnrealEditorCmd`" $($Arguments -join ' ')"
Write-Output "PIE_LOG=$LogPath"
Write-Output "PIE_REPORT=$ReportPath"

$Process = Start-Process -FilePath $UnrealEditorCmd -ArgumentList $Arguments -WorkingDirectory $ProjectRoot -PassThru -WindowStyle Hidden
if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    $Process.WaitForExit(5000) | Out-Null
    Write-Output "PROCESS_CLEANUP=TERMINATED_AFTER_TIMEOUT"
    Write-Output "PIE_RESULT=FAIL_TIMEOUT"
    exit 4
}
$Process.Refresh()
Write-Output "EDITOR_EXIT_CODE=$($Process.ExitCode)"
if ($Process.ExitCode -ne 0) {
    Write-Output "PROCESS_CLEANUP=PROCESS_EXITED"
    Write-Output "PIE_RESULT=FAIL_EDITOR_EXIT_$($Process.ExitCode)"
    exit $Process.ExitCode
}

$LogText = if ([IO.File]::Exists($LogPath)) { Get-Content -Raw -LiteralPath $LogPath } else { "" }
if ($LogText -notmatch "ASWW_PIE_SMOKE=PASS") {
    Write-Output "PROCESS_CLEANUP=PROCESS_EXITED"
    Write-Output "PIE_RESULT=FAIL_MISSING_TEST_SUCCESS_MARKER"
    exit 5
}

Write-Output "PROCESS_CLEANUP=PROCESS_EXITED"
Write-Output "PIE_RESULT=PASS_STARTUP_SMOKE_ONLY"
Write-Output "GAMEPLAY_FEATURE_MATRIX=NOT_TESTED_BY_THIS_SMOKE"
exit 0
