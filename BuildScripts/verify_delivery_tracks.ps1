[CmdletBinding()]
param(
    [string]$UERoot,
    [string]$PythonExecutable,
    [string]$ExpectedBranch = "codex/asww-development"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$LogRoot = Join-Path $ProjectRoot "Saved\Verification\DeliveryTracks"
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

if ([string]::IsNullOrWhiteSpace($PythonExecutable)) {
    $PythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($PythonCommand) {
        $PythonExecutable = $PythonCommand.Source
    }
    elseif ($env:USERPROFILE) {
        $BundledPython = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
        if ([IO.File]::Exists($BundledPython)) {
            $PythonExecutable = $BundledPython
        }
    }
}
if ([string]::IsNullOrWhiteSpace($PythonExecutable) -or -not [IO.File]::Exists($PythonExecutable)) {
    throw "Python 3 was not found. Pass -PythonExecutable explicitly."
}

Push-Location $ProjectRoot
try {
    $Branch = (& git branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or $Branch -ne $ExpectedBranch) {
        throw "Delivery verification must run on '$ExpectedBranch'; current branch is '$Branch'."
    }

    Write-Output "BRANCH=$Branch"
    Write-Output "PYTHON=$PythonExecutable"

    $WebLog = Join-Path $LogRoot "track_a_web.log"
    & $PythonExecutable (Join-Path $ProjectRoot "ci\preflight_web_delivery.py") 2>&1 | Tee-Object -FilePath $WebLog
    $WebExit = $LASTEXITCODE

    $NativeLog = Join-Path $LogRoot "track_b_native_structure.log"
    & $PythonExecutable (Join-Path $ProjectRoot "ci\preflight_native_delivery.py") 2>&1 | Tee-Object -FilePath $NativeLog
    $NativeStructureExit = $LASTEXITCODE

    $UnrealArguments = @(
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy", "Bypass",
        "-File", (Join-Path $ProjectRoot "BuildScripts\verify_unreal_local.ps1"),
        "-PythonExecutable", $PythonExecutable,
        "-ExpectedBranch", $ExpectedBranch
    )
    if (-not [string]::IsNullOrWhiteSpace($UERoot)) {
        $UnrealArguments += @("-UERoot", $UERoot)
    }
    $UnrealLog = Join-Path $LogRoot "track_b_unreal.log"
    & powershell.exe @UnrealArguments 2>&1 | Tee-Object -FilePath $UnrealLog
    $UnrealExit = $LASTEXITCODE

    $Win64Artifacts = @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "BuildOutput\Client") -Recurse -File -Filter "ArabiaStrikeWorldWar.exe" -ErrorAction SilentlyContinue)
    $AndroidApkArtifacts = @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "BuildOutput\Android") -Recurse -File -Filter "*.apk" -ErrorAction SilentlyContinue)
    $AndroidAabArtifacts = @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "BuildOutput\Android") -Recurse -File -Filter "*.aab" -ErrorAction SilentlyContinue)
    $IOSArtifacts = @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "BuildOutput\IOS") -Recurse -File -Filter "*.ipa" -ErrorAction SilentlyContinue)

    $TrackAResult = if ($WebExit -eq 0) { "PASS_STATIC_READINESS" } else { "FAIL" }
    $NativeStructureResult = if ($NativeStructureExit -eq 0) { "PASS" } else { "FAIL" }
    $UnrealResult = if ($UnrealExit -eq 0) { "PASS_REAL_UE_BUILDS" } else { "BLOCKED_OR_FAILED_SEE_LOG" }
    $Win64Result = if ($Win64Artifacts.Count -gt 0) { "FOUND" } else { "NOT_FOUND" }
    $AndroidResult = if (($AndroidApkArtifacts.Count + $AndroidAabArtifacts.Count) -gt 0) { "FOUND" } else { "NOT_FOUND" }
    $IOSResult = if ($IOSArtifacts.Count -gt 0) { "FOUND" } else { "NOT_FOUND" }
    $TrackBResult = if ($NativeStructureExit -eq 0 -and $UnrealExit -eq 0 -and $Win64Artifacts.Count -gt 0) { "PASS_WIN64_MILESTONE" } else { "BLOCKED" }
    $OverallResult = if ($WebExit -eq 0 -and $TrackBResult -like "PASS*") { "PASS" } else { "FAIL" }

    $Summary = @(
        "TRACK_A_WEB_RESULT=$TrackAResult",
        "TRACK_A_LOG=$WebLog",
        "TRACK_B_NATIVE_STRUCTURE_RESULT=$NativeStructureResult",
        "TRACK_B_UNREAL_RESULT=$UnrealResult",
        "TRACK_B_WIN64_PACKAGE=$Win64Result",
        "TRACK_B_ANDROID_PACKAGE=$AndroidResult",
        "TRACK_B_IOS_PACKAGE=$IOSResult",
        "TRACK_B_NATIVE_RESULT=$TrackBResult",
        "TRACK_B_STRUCTURE_LOG=$NativeLog",
        "TRACK_B_UNREAL_LOG=$UnrealLog",
        "OVERALL_RESULT=$OverallResult"
    )
    $SummaryPath = Join-Path $LogRoot "delivery_summary.txt"
    [IO.File]::WriteAllLines($SummaryPath, $Summary, [Text.UTF8Encoding]::new($false))
    $Summary | ForEach-Object { Write-Output $_ }
    Write-Output "DELIVERY_SUMMARY=$SummaryPath"

    if ($OverallResult -ne "PASS") {
        exit 1
    }
}
finally {
    Pop-Location
}
