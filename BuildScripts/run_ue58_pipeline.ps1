[CmdletBinding()]
param(
    [string]$UERoot,
    [string]$PythonExecutable,
    [string]$ExpectedBranch = "codex/asww-development",
    [switch]$WaitForEngine,
    [ValidateRange(5, 300)][int]$PollIntervalSeconds = 30,
    [ValidateRange(1, 720)][int]$MaxWaitMinutes = 240,
    [switch]$SkipPIE,
    [switch]$SkipPackaging,
    [switch]$RunMultiplayerProcessWindow,
    [ValidateSet(2, 4, 8)][int]$MultiplayerPlayerCount = 2,
    [ValidateRange(10, 3600)][int]$MultiplayerDurationSeconds = 120,
    [switch]$LaunchPixelStreaming,
    [switch]$StartPixelStreamingStack,
    [string]$PixelStreamingInfrastructureRoot,
    [string]$SignallingServerUrl = "ws://127.0.0.1",
    [ValidateRange(1, 65535)][int]$SignallingServerPort = 8888,
    [ValidateRange(1, 65535)][int]$PixelStreamingFrontendPort = 8080
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ResumeScript = Join-Path $PSScriptRoot "resume_after_ue58.ps1"
$GenerateMapScript = Join-Path $PSScriptRoot "generate_jeddah_map.ps1"
$ValidateMapScript = Join-Path $PSScriptRoot "validate_jeddah_map.ps1"
$PromoteMapScript = Join-Path $PSScriptRoot "promote_jeddah_default_map.ps1"
$PIEScript = Join-Path $PSScriptRoot "run_jeddah_pie_smoke.ps1"
$BuildClientScript = Join-Path $PSScriptRoot "build_win64.ps1"
$BuildServerScript = Join-Path $PSScriptRoot "build_server_win64.ps1"
$MultiplayerScript = Join-Path $PSScriptRoot "run_local_multiplayer.ps1"
$PixelStreamingScript = Join-Path $PSScriptRoot "run_pixel_streaming2.ps1"
$PixelStreamingStackScript = Join-Path $PSScriptRoot "prepare_pixel_streaming2_stack.ps1"
$VerificationSummary = Join-Path $ProjectRoot "Saved\Verification\Local\verification_summary.txt"
$MapLogRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\JeddahMap"
$PipelineLogRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\Pipeline"
$Deadline = [DateTime]::UtcNow.AddMinutes($MaxWaitMinutes)

function Get-SummaryValue {
    param([string]$Path, [string]$Key)
    if (-not [IO.File]::Exists($Path)) {
        return $null
    }
    $Prefix = "$Key="
    $Line = Get-Content -LiteralPath $Path |
        Where-Object { $_.StartsWith($Prefix, [StringComparison]::Ordinal) } |
        Select-Object -Last 1
    if ($Line) {
        return $Line.Substring($Prefix.Length)
    }
    return $null
}

function Invoke-PowerShellScript {
    param([string]$ScriptPath, [string[]]$Arguments, [string]$LogPath)
    Write-Host "PIPELINE_COMMAND=powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`" $($Arguments -join ' ')"
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1 |
        Tee-Object -FilePath $LogPath |
        Out-Host
    $ScriptExitCode = $LASTEXITCODE
    return $ScriptExitCode
}

$CurrentBranch = (& git -C $ProjectRoot branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $CurrentBranch -ne $ExpectedBranch) {
    throw "UE pipeline requires '$ExpectedBranch'; current branch is '$CurrentBranch'."
}

New-Item -ItemType Directory -Force -Path $PipelineLogRoot | Out-Null
$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
Write-Output "PIPELINE_RUN_ID=$RunId"
Write-Output "BRANCH=$CurrentBranch"
Write-Output "WAIT_FOR_ENGINE=$WaitForEngine"

$ResumeExit = 2
do {
    $ResumeArguments = @("-ExpectedBranch", $ExpectedBranch)
    if (-not [string]::IsNullOrWhiteSpace($UERoot)) {
        $ResumeArguments += @("-UERoot", $UERoot)
    }
    if (-not [string]::IsNullOrWhiteSpace($PythonExecutable)) {
        $ResumeArguments += @("-PythonExecutable", $PythonExecutable)
    }
    $ResumeLog = Join-Path $PipelineLogRoot "resume_$RunId.log"
    $ResumeExit = Invoke-PowerShellScript $ResumeScript $ResumeArguments $ResumeLog
    Write-Output "RESUME_EXIT_CODE=$ResumeExit"

    if ($ResumeExit -ne 2) {
        break
    }
    if (-not $WaitForEngine) {
        Write-Output "PIPELINE_RESULT=BLOCKED_UE58_NOT_FOUND"
        exit 2
    }
    if ([DateTime]::UtcNow -ge $Deadline) {
        Write-Output "PIPELINE_RESULT=BLOCKED_UE58_INSTALL_TIMEOUT"
        exit 2
    }
    Write-Output "UE_POLL_RESULT=NOT_READY;NEXT_POLL_SECONDS=$PollIntervalSeconds"
    Start-Sleep -Seconds $PollIntervalSeconds
}
while ($true)

if ($ResumeExit -notin @(0, 3)) {
    $HostResult = Get-SummaryValue $VerificationSummary "HOST_PREREQUISITE_RESULT"
    if ($HostResult -eq "BLOCKED") {
        Write-Output "PIPELINE_RESULT=BLOCKED_HOST_TOOLCHAIN"
        exit 4
    }
    Write-Output "PIPELINE_RESULT=FAIL_REAL_UNREAL_BUILD_STAGE"
    exit $ResumeExit
}

$DetectedUERoot = Get-SummaryValue $VerificationSummary "UE_ROOT"
if ([string]::IsNullOrWhiteSpace($DetectedUERoot) -or $DetectedUERoot -eq "NOT_FOUND") {
    throw "The Unreal verifier did not report a valid UE_ROOT."
}
Write-Output "UE_ROOT=$DetectedUERoot"

$GenerateLog = Join-Path $PipelineLogRoot "map_generate_$RunId.log"
$GenerateExit = Invoke-PowerShellScript $GenerateMapScript @("-UERoot", $DetectedUERoot, "-ExpectedBranch", $ExpectedBranch) $GenerateLog
if ($GenerateExit -ne 0) {
    Write-Output "PIPELINE_RESULT=FAIL_JEDDAH_GENERATION"
    exit $GenerateExit
}

$ValidateLog = Join-Path $PipelineLogRoot "map_validate_$RunId.log"
$ValidateExit = Invoke-PowerShellScript $ValidateMapScript @("-UERoot", $DetectedUERoot, "-ExpectedBranch", $ExpectedBranch) $ValidateLog
if ($ValidateExit -ne 0) {
    Write-Output "PIPELINE_RESULT=FAIL_JEDDAH_EDITOR_VALIDATION"
    exit $ValidateExit
}

$EditorValidationLog = Get-ChildItem -LiteralPath $MapLogRoot -File -Filter "validate_*.log" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $EditorValidationLog) {
    throw "Jeddah validation passed without a retained Editor log."
}
$PromoteLog = Join-Path $PipelineLogRoot "map_promote_$RunId.log"
$PromoteExit = Invoke-PowerShellScript $PromoteMapScript @("-ValidationLog", $EditorValidationLog.FullName, "-ExpectedBranch", $ExpectedBranch) $PromoteLog
if ($PromoteExit -ne 0) {
    Write-Output "PIPELINE_RESULT=FAIL_JEDDAH_DEFAULT_PROMOTION"
    exit $PromoteExit
}

if (-not $SkipPIE) {
    $PIELog = Join-Path $PipelineLogRoot "pie_$RunId.log"
    $PIEExit = Invoke-PowerShellScript $PIEScript @("-UERoot", $DetectedUERoot, "-ExpectedBranch", $ExpectedBranch) $PIELog
    if ($PIEExit -ne 0) {
        Write-Output "PIPELINE_RESULT=FAIL_PIE_STARTUP_SMOKE"
        exit $PIEExit
    }
}
else {
    Write-Output "PIE_RESULT=NOT_RUN_BY_REQUEST"
}

if ($SkipPackaging) {
    Write-Output "WIN64_CLIENT_PACKAGE=NOT_RUN_BY_REQUEST"
    Write-Output "WIN64_SERVER_PACKAGE=NOT_RUN_BY_REQUEST"
    Write-Output "PIPELINE_RESULT=PASS_BUILDS_MAP_AND_OPTIONAL_PIE_ONLY"
    exit 0
}

$ClientPackageLog = Join-Path $PipelineLogRoot "package_client_$RunId.log"
$ClientPackageExit = Invoke-PowerShellScript $BuildClientScript @("-UERoot", $DetectedUERoot, "-Configuration", "Development") $ClientPackageLog
if ($ClientPackageExit -ne 0) {
    Write-Output "PIPELINE_RESULT=FAIL_WIN64_CLIENT_PACKAGE"
    exit $ClientPackageExit
}
$ServerPackageLog = Join-Path $PipelineLogRoot "package_server_$RunId.log"
$ServerPackageExit = Invoke-PowerShellScript $BuildServerScript @("-UERoot", $DetectedUERoot, "-Configuration", "Development") $ServerPackageLog
if ($ServerPackageExit -ne 0) {
    Write-Output "PIPELINE_RESULT=FAIL_WIN64_SERVER_PACKAGE"
    exit $ServerPackageExit
}

foreach ($PlayerCount in @(2, 4, 8)) {
    $MultiplayerValidationLog = Join-Path $PipelineLogRoot "multiplayer_${PlayerCount}p_validate_$RunId.log"
    $MultiplayerValidationExit = Invoke-PowerShellScript $MultiplayerScript @("-PlayerCount", "$PlayerCount", "-ValidateOnly") $MultiplayerValidationLog
    if ($MultiplayerValidationExit -ne 0) {
        Write-Output "PIPELINE_RESULT=FAIL_MULTIPLAYER_${PlayerCount}P_PREREQUISITES"
        exit $MultiplayerValidationExit
    }
    Write-Output "MULTIPLAYER_${PlayerCount}P=PREREQUISITES_PASS_GAMEPLAY_NOT_TESTED"
}

if ($RunMultiplayerProcessWindow) {
    $MultiplayerRunLog = Join-Path $PipelineLogRoot "multiplayer_${MultiplayerPlayerCount}p_run_$RunId.log"
    $MultiplayerRunExit = Invoke-PowerShellScript $MultiplayerScript @(
        "-PlayerCount", "$MultiplayerPlayerCount",
        "-RunDurationSeconds", "$MultiplayerDurationSeconds"
    ) $MultiplayerRunLog
    if ($MultiplayerRunExit -ne 0) {
        Write-Output "PIPELINE_RESULT=FAIL_MULTIPLAYER_PROCESS_WINDOW"
        exit $MultiplayerRunExit
    }
    Write-Output "MULTIPLAYER_RUNTIME=PROCESS_WINDOW_COMPLETED_GAMEPLAY_NOT_VERIFIED"
}
else {
    Write-Output "MULTIPLAYER_RUNTIME=NOT_RUN"
}

if ($LaunchPixelStreaming) {
    if ($StartPixelStreamingStack) {
        $PixelStackLog = Join-Path $PipelineLogRoot "pixel_streaming_stack_$RunId.log"
        $PixelStackArguments = @(
            "-UERoot", $DetectedUERoot,
            "-ExpectedBranch", $ExpectedBranch,
            "-StreamerPort", "$SignallingServerPort",
            "-PlayerPort", "$PixelStreamingFrontendPort",
            "-Start"
        )
        if (-not [string]::IsNullOrWhiteSpace($PixelStreamingInfrastructureRoot)) {
            $PixelStackArguments += @("-InfrastructureRoot", $PixelStreamingInfrastructureRoot)
        }
        $PixelStackExit = Invoke-PowerShellScript $PixelStreamingStackScript $PixelStackArguments $PixelStackLog
        if ($PixelStackExit -ne 0) {
            Write-Output "PIPELINE_RESULT=FAIL_OR_BLOCKED_PIXEL_STREAMING_STACK"
            exit $PixelStackExit
        }
        Write-Output "PIXEL_STREAMING_FRONTEND=http://127.0.0.1:$PixelStreamingFrontendPort/"
    }
    $PixelLog = Join-Path $PipelineLogRoot "pixel_streaming_$RunId.log"
    $PixelExit = Invoke-PowerShellScript $PixelStreamingScript @(
        "-PackageRoot", (Join-Path $ProjectRoot "BuildOutput\Client"),
        "-UERoot", $DetectedUERoot,
        "-SignallingServerUrl", $SignallingServerUrl,
        "-SignallingServerPort", "$SignallingServerPort",
        "-VisibleWindow"
    ) $PixelLog
    if ($PixelExit -ne 0) {
        Write-Output "PIPELINE_RESULT=FAIL_OR_BLOCKED_PIXEL_STREAMING_PREREQUISITES"
        exit $PixelExit
    }
    Write-Output "PIXEL_STREAMING=PROCESS_STARTED_WEBRTC_NOT_VERIFIED"
}
else {
    Write-Output "PIXEL_STREAMING=NOT_RUN_REQUIRES_REAL_SIGNALLING_BACKEND"
}

Write-Output "PIPELINE_LOG_ROOT=$PipelineLogRoot"
Write-Output "PIPELINE_RESULT=PASS_AUTOMATED_STAGES_RUNTIME_FEATURE_MATRIX_REMAINS_SEPARATE"
exit 0
