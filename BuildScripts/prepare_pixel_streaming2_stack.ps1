[CmdletBinding()]
param(
    [string]$UERoot = $env:UE_ROOT,
    [string]$InfrastructureRoot,
    [string]$ExpectedBranch = "codex/asww-development",
    [ValidateRange(1, 65535)][int]$StreamerPort = 8888,
    [ValidateRange(1, 65535)][int]$PlayerPort = 8080,
    [ValidateRange(10, 600)][int]$StartupTimeoutSeconds = 180,
    [switch]$DownloadOfficialUE58,
    [switch]$Start,
    [switch]$VisibleWindow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$OfficialRepository = "https://github.com/EpicGames/PixelStreamingInfrastructure.git"
$OfficialBranch = "UE5.8"
if ([string]::IsNullOrWhiteSpace($InfrastructureRoot)) {
    $InfrastructureRoot = Join-Path $ProjectRoot "LocalInfrastructure\PixelStreamingInfrastructure-UE5.8"
}
elseif (-not [IO.Path]::IsPathRooted($InfrastructureRoot)) {
    $InfrastructureRoot = Join-Path $ProjectRoot $InfrastructureRoot
}
$InfrastructureRoot = [IO.Path]::GetFullPath($InfrastructureRoot)

function Test-TcpPort {
    param([string]$HostName, [int]$Port, [int]$TimeoutMilliseconds = 1000)
    $Client = [Net.Sockets.TcpClient]::new()
    try {
        $ConnectTask = $Client.ConnectAsync($HostName, $Port)
        return $ConnectTask.Wait($TimeoutMilliseconds) -and $Client.Connected
    }
    catch {
        return $false
    }
    finally {
        $Client.Dispose()
    }
}

$CurrentBranch = (& git -C $ProjectRoot branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $CurrentBranch -ne $ExpectedBranch) {
    throw "Pixel Streaming preparation requires '$ExpectedBranch'; current branch is '$CurrentBranch'."
}
Write-Output "BRANCH=$CurrentBranch"
Write-Output "OFFICIAL_INFRASTRUCTURE_REPOSITORY=$OfficialRepository"
Write-Output "OFFICIAL_INFRASTRUCTURE_BRANCH=$OfficialBranch"
Write-Output "INFRASTRUCTURE_ROOT=$InfrastructureRoot"

if (-not [IO.File]::Exists($ProjectFile)) {
    throw "Project descriptor was not found: '$ProjectFile'."
}
$ProjectDescriptor = Get-Content -Raw -LiteralPath $ProjectFile | ConvertFrom-Json
$PixelStreamingPlugin = @($ProjectDescriptor.Plugins) |
    Where-Object { $_.Name -eq "PixelStreaming2" -and $_.Enabled -eq $true } |
    Select-Object -First 1
if (-not $PixelStreamingPlugin) {
    throw "PixelStreaming2 is not enabled in ArabiaStrikeWorldWar.uproject."
}
Write-Output "PIXEL_STREAMING2_PROJECT_PLUGIN=ENABLED"

if ([string]::IsNullOrWhiteSpace($UERoot)) {
    Write-Output "UE_ROOT=NOT_PROVIDED"
    Write-Output "PIXEL_STREAMING2_ENGINE_PLUGIN=NOT_CHECKED"
}
else {
    $BuildVersionPath = Join-Path $UERoot "Engine\Build\Build.version"
    $EnginePlugin = Join-Path $UERoot "Engine\Plugins\Media\PixelStreaming2\PixelStreaming2.uplugin"
    if (-not [IO.File]::Exists($BuildVersionPath) -or -not [IO.File]::Exists($EnginePlugin)) {
        throw "UE_ROOT is incomplete or does not contain PixelStreaming2: '$UERoot'."
    }
    $BuildVersion = Get-Content -Raw -LiteralPath $BuildVersionPath | ConvertFrom-Json
    $EngineVersion = "$($BuildVersion.MajorVersion).$($BuildVersion.MinorVersion).$($BuildVersion.PatchVersion)"
    if ($BuildVersion.MajorVersion -ne 5 -or $BuildVersion.MinorVersion -ne 8) {
        throw "Pixel Streaming 2 preparation requires UE 5.8.x; found '$EngineVersion'."
    }
    Write-Output "UE_ROOT=$UERoot"
    Write-Output "UE_VERSION=$EngineVersion"
    Write-Output "PIXEL_STREAMING2_ENGINE_PLUGIN=$EnginePlugin"

    $BundledFetcher = Join-Path $UERoot "Engine\Plugins\Media\PixelStreaming2\Resources\WebServers\get_ps_servers.bat"
    if ([IO.File]::Exists($BundledFetcher)) {
        $FetcherHasUE58Mapping = Select-String -LiteralPath $BundledFetcher -SimpleMatch 'if "%UEVersion%"=="5.8"' -Quiet
        Write-Output "BUNDLED_INFRASTRUCTURE_FETCHER=$BundledFetcher"
        Write-Output "BUNDLED_FETCHER_UE58_MAPPING=$(if ($FetcherHasUE58Mapping) { 'PRESENT' } else { 'NOT_PRESENT_USE_EXPLICIT_OFFICIAL_BRANCH' })"
    }
    else {
        Write-Output "BUNDLED_INFRASTRUCTURE_FETCHER=NOT_FOUND"
    }
}

$NodeCommand = Get-Command node -ErrorAction SilentlyContinue
$NpmCommand = Get-Command npm -ErrorAction SilentlyContinue
Write-Output "NODE=$(if ($NodeCommand) { $NodeCommand.Source } else { 'NOT_FOUND' })"
Write-Output "NPM=$(if ($NpmCommand) { $NpmCommand.Source } else { 'NOT_FOUND' })"
if (-not $NodeCommand -or -not $NpmCommand) {
    throw "Node.js and npm are required by the official Pixel Streaming infrastructure."
}
Write-Output "NODE_VERSION=$(& $NodeCommand.Source --version)"
Write-Output "NPM_VERSION=$(& $NpmCommand.Source --version)"

if ($DownloadOfficialUE58) {
    if ([IO.Directory]::Exists($InfrastructureRoot)) {
        $ExistingEntries = @(Get-ChildItem -LiteralPath $InfrastructureRoot -Force -ErrorAction SilentlyContinue)
        if ($ExistingEntries.Count -gt 0) {
            throw "Refusing to overwrite non-empty infrastructure directory '$InfrastructureRoot'."
        }
    }
    else {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $InfrastructureRoot) | Out-Null
    }
    Write-Output "DOWNLOAD_COMMAND=git clone --branch $OfficialBranch --depth 1 $OfficialRepository `"$InfrastructureRoot`""
    & git clone --branch $OfficialBranch --depth 1 $OfficialRepository $InfrastructureRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Official Pixel Streaming infrastructure clone failed with exit code $LASTEXITCODE."
    }
}

$StartScript = Join-Path $InfrastructureRoot "SignallingWebServer\platform_scripts\cmd\start.bat"
$RepositoryMetadata = Join-Path $InfrastructureRoot ".git"
if (-not [IO.File]::Exists($StartScript)) {
    Write-Output "SIGNALLING_START_SCRIPT=NOT_FOUND"
    Write-Output "FRONTEND_URL=NOT_AVAILABLE"
    Write-Output "SIGNALLING_URL=NOT_AVAILABLE"
    Write-Output "STACK_RESULT=BLOCKED_INFRASTRUCTURE_NOT_DOWNLOADED"
    Write-Output "NEXT_ACTION=Rerun with -DownloadOfficialUE58 after network bandwidth is available."
    exit 2
}

$InfrastructureBranch = "UNVERIFIED"
if ([IO.Directory]::Exists($RepositoryMetadata)) {
    $InfrastructureBranch = (& git -C $InfrastructureRoot branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Could not verify the Pixel Streaming infrastructure Git branch."
    }
}
elseif ([IO.File]::Exists((Join-Path $InfrastructureRoot "DOWNLOAD_VERSION"))) {
    $InfrastructureBranch = (Get-Content -Raw -LiteralPath (Join-Path $InfrastructureRoot "DOWNLOAD_VERSION")).Trim()
}
if ($InfrastructureBranch -notmatch '^UE5\.8(?:$|[-.])') {
    throw "Pixel Streaming infrastructure is not verifiably UE5.8-compatible (marker '$InfrastructureBranch')."
}

$FrontendPage = Join-Path $InfrastructureRoot "SignallingWebServer\www\player.html"
$FrontendUrl = "http://127.0.0.1:$PlayerPort/"
$SignallingUrl = "ws://127.0.0.1:$StreamerPort"
Write-Output "INFRASTRUCTURE_VERSION_MARKER=$InfrastructureBranch"
Write-Output "SIGNALLING_START_SCRIPT=$StartScript"
Write-Output "FRONTEND_PAGE=$(if ([IO.File]::Exists($FrontendPage)) { $FrontendPage } else { 'GENERATED_DURING_FIRST_START' })"
Write-Output "FRONTEND_URL=$FrontendUrl"
Write-Output "SIGNALLING_URL=$SignallingUrl"

if (-not $Start) {
    Write-Output "STACK_RESULT=READY_TO_START_NOT_STARTED"
    exit 0
}

$StartArguments = @(
    "/d",
    "/c",
    "`"$StartScript`" --streamer_port $StreamerPort --player_port $PlayerPort"
)
$StartParameters = @{
    FilePath = $env:ComSpec
    ArgumentList = $StartArguments
    WorkingDirectory = $InfrastructureRoot
    PassThru = $true
}
if (-not $VisibleWindow) {
    $StartParameters.WindowStyle = "Hidden"
}
Write-Output "STACK_COMMAND=$($env:ComSpec) /d /c `"$StartScript`" --streamer_port $StreamerPort --player_port $PlayerPort"
$StackProcess = Start-Process @StartParameters
Write-Output "STACK_PROCESS_ID=$($StackProcess.Id)"

$Deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
$PlayerReachable = $false
$StreamerReachable = $false
do {
    if ($StackProcess.HasExited) {
        $StackProcess.Refresh()
        Write-Output "STACK_PROCESS_EXIT_CODE=$($StackProcess.ExitCode)"
        Write-Output "STACK_RESULT=FAIL_PROCESS_EXITED_BEFORE_ENDPOINTS"
        exit 1
    }
    $PlayerReachable = Test-TcpPort "127.0.0.1" $PlayerPort
    $StreamerReachable = Test-TcpPort "127.0.0.1" $StreamerPort
    if ($PlayerReachable -and $StreamerReachable) {
        break
    }
    Start-Sleep -Seconds 2
}
while ([DateTime]::UtcNow -lt $Deadline)

Write-Output "FRONTEND_REACHABILITY=$(if ($PlayerReachable) { 'TCP_REACHABLE_NOT_WEBRTC_VERIFIED' } else { 'NOT_REACHABLE' })"
Write-Output "SIGNALLING_REACHABILITY=$(if ($StreamerReachable) { 'TCP_REACHABLE_NOT_WEBRTC_VERIFIED' } else { 'NOT_REACHABLE' })"
if (-not $PlayerReachable -or -not $StreamerReachable) {
    Write-Output "STACK_RESULT=FAIL_ENDPOINT_STARTUP_TIMEOUT"
    exit 1
}
Write-Output "WEBRTC_SESSION=NOT_VERIFIED"
Write-Output "STACK_RESULT=PASS_PROCESS_STARTED_ENDPOINTS_REACHABLE_WEBRTC_NOT_VERIFIED"
exit 0
