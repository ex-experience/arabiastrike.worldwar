[CmdletBinding()]
param(
    [string]$PackageRoot,
    [string]$SignallingServerUrl = "ws://127.0.0.1",
    [ValidateRange(1, 65535)]
    [int]$SignallingServerPort = 8888,
    [string]$UERoot = $env:UE_ROOT,
    [ValidateRange(640, 7680)]
    [int]$ResolutionX = 1920,
    [ValidateRange(360, 4320)]
    [int]$ResolutionY = 1080,
    [switch]$VisibleWindow,
    [switch]$WaitForExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$PackageCandidates = [System.Collections.Generic.List[string]]::new()
$FailureReasons = [System.Collections.Generic.List[string]]::new()

function Add-UniqueDirectory {
    param(
        [System.Collections.Generic.List[string]]$Directories,
        [string]$Candidate
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return
    }

    $ExpandedCandidate = [Environment]::ExpandEnvironmentVariables($Candidate.Trim().Trim('"'))
    if (-not [IO.Path]::IsPathRooted($ExpandedCandidate)) {
        $ExpandedCandidate = Join-Path $ProjectRoot $ExpandedCandidate
    }

    if (-not $Directories.Contains($ExpandedCandidate)) {
        $Directories.Add($ExpandedCandidate)
    }
}

Write-Output "PROJECT_ROOT=$ProjectRoot"
Write-Output "PROJECT_FILE=$ProjectFile"

if (-not [IO.File]::Exists($ProjectFile)) {
    Write-Output "PIXEL_STREAMING2_ENABLED=UNKNOWN"
    Write-Output "PACKAGE_EXECUTABLE=NOT_FOUND"
    Write-Output "LAUNCH_RESULT=FAIL_PROJECT_FILE_MISSING"
    exit 1
}

$ProjectDescriptor = Get-Content -Raw -LiteralPath $ProjectFile | ConvertFrom-Json
$PixelStreamingPlugin = @($ProjectDescriptor.Plugins) | Where-Object { $_.Name -eq "PixelStreaming2" } | Select-Object -First 1
$PixelStreamingEnabled = $PixelStreamingPlugin -and $PixelStreamingPlugin.Enabled -eq $true
Write-Output "PIXEL_STREAMING2_ENABLED=$PixelStreamingEnabled"

if (-not $PixelStreamingEnabled) {
    $FailureReasons.Add("PixelStreaming2 is not enabled in ArabiaStrikeWorldWar.uproject. Enable it only after confirming the UE 5.8 plugin is installed.")
}

if ([string]::IsNullOrWhiteSpace($UERoot)) {
    Write-Output "ENGINE_PIXEL_STREAMING2_PLUGIN=NOT_CHECKED_NO_UE_ROOT"
}
else {
    $EnginePluginCandidates = @(
        (Join-Path $UERoot "Engine\Plugins\Media\PixelStreaming2\PixelStreaming2.uplugin"),
        (Join-Path $UERoot "Engine\Plugins\Media\PixelStreaming\PixelStreaming2.uplugin")
    )
    $EnginePlugin = $EnginePluginCandidates | Where-Object { [IO.File]::Exists($_) } | Select-Object -First 1
    if ($EnginePlugin) {
        Write-Output "ENGINE_PIXEL_STREAMING2_PLUGIN=$EnginePlugin"
    }
    else {
        Write-Output "ENGINE_PIXEL_STREAMING2_PLUGIN=NOT_FOUND"
        $FailureReasons.Add("PixelStreaming2.uplugin was not found under UE_ROOT '$UERoot'.")
    }
}

Add-UniqueDirectory $PackageCandidates $PackageRoot
Add-UniqueDirectory $PackageCandidates (Join-Path $ProjectRoot "BuildOutput\Client")
Add-UniqueDirectory $PackageCandidates (Join-Path $ProjectRoot "Packaged\Client")
Add-UniqueDirectory $PackageCandidates (Join-Path $ProjectRoot "Packaged\Windows")
Add-UniqueDirectory $PackageCandidates (Join-Path $ProjectRoot "Releases\Windows")

$PackagedExecutable = $null
foreach ($CandidateRoot in $PackageCandidates) {
    Write-Output "PACKAGE_SEARCH_ROOT=$CandidateRoot;EXISTS=$([IO.Directory]::Exists($CandidateRoot))"
    if (-not [IO.Directory]::Exists($CandidateRoot)) {
        continue
    }

    $PackagedExecutable = Get-ChildItem -LiteralPath $CandidateRoot -Recurse -File -Filter "ArabiaStrikeWorldWar.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\Engine\\Binaries\\' } |
        Sort-Object FullName |
        Select-Object -First 1
    if ($PackagedExecutable) {
        break
    }
}

if ($PackagedExecutable) {
    Write-Output "PACKAGE_EXECUTABLE=$($PackagedExecutable.FullName)"
}
else {
    Write-Output "PACKAGE_EXECUTABLE=NOT_FOUND"
    $FailureReasons.Add("No packaged ArabiaStrikeWorldWar.exe was found. Package the Win64 client before launching Pixel Streaming 2.")
}

$SignallingEndpoint = $null
try {
    $ParsedSignallingUrl = [Uri]$SignallingServerUrl
    if ($ParsedSignallingUrl.Scheme -notin @("ws", "wss")) {
        throw "The signalling URL must use ws:// or wss://."
    }

    $EndpointBuilder = [UriBuilder]::new($ParsedSignallingUrl)
    $EndpointBuilder.Port = $SignallingServerPort
    $SignallingEndpoint = $EndpointBuilder.Uri.AbsoluteUri.TrimEnd('/')
    Write-Output "SIGNALLING_ENDPOINT=$SignallingEndpoint"
}
catch {
    Write-Output "SIGNALLING_ENDPOINT=INVALID"
    $FailureReasons.Add("Invalid signalling endpoint: $($_.Exception.Message)")
}

if ($FailureReasons.Count -gt 0) {
    foreach ($FailureReason in $FailureReasons) {
        Write-Output "ERROR=$FailureReason"
    }
    Write-Output "LAUNCH_RESULT=FAIL_PREREQUISITES"
    exit 1
}

$LaunchArguments = @(
    "-PixelStreamingURL=$SignallingEndpoint",
    "-RenderOffscreen",
    "-AudioMixer",
    "-Unattended",
    "-StdOut",
    "-FullStdOutLogOutput",
    "-ForceRes",
    "-ResX=$ResolutionX",
    "-ResY=$ResolutionY"
)

Write-Output "LAUNCH_COMMAND=`"$($PackagedExecutable.FullName)`" $($LaunchArguments -join ' ')"
Write-Output "VISIBLE_WINDOW=$VisibleWindow"
Write-Output "WAIT_FOR_EXIT=$WaitForExit"

$ProcessParameters = @{
    FilePath = $PackagedExecutable.FullName
    ArgumentList = $LaunchArguments
    WorkingDirectory = $PackagedExecutable.DirectoryName
    PassThru = $true
}
if (-not $VisibleWindow) {
    $ProcessParameters.WindowStyle = "Hidden"
}

$GameProcess = Start-Process @ProcessParameters
Write-Output "PROCESS_ID=$($GameProcess.Id)"

if ($GameProcess.WaitForExit(2500)) {
    $GameProcess.Refresh()
    if ($GameProcess.ExitCode -ne 0) {
        Write-Output "PROCESS_EXIT_CODE=$($GameProcess.ExitCode)"
        Write-Output "LAUNCH_RESULT=FAIL_PROCESS_EXITED_EARLY"
        exit $GameProcess.ExitCode
    }
}

if ($WaitForExit -and -not $GameProcess.HasExited) {
    Write-Output "PROCESS_STATE=RUNNING_WAITING_FOR_EXIT"
    $GameProcess.WaitForExit()
    $GameProcess.Refresh()
    Write-Output "PROCESS_EXIT_CODE=$($GameProcess.ExitCode)"
    if ($GameProcess.ExitCode -ne 0) {
        Write-Output "LAUNCH_RESULT=FAIL_PROCESS_EXIT"
        exit $GameProcess.ExitCode
    }
}

Write-Output "LAUNCH_RESULT=PASS_PROCESS_STARTED"
exit 0
