[CmdletBinding()]
param(
    [string]$UERoot,
    [string]$PythonExecutable,
    [string]$ExpectedBranch = "codex/asww-development"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$VerificationLogRoot = Join-Path $ProjectRoot "Saved\Verification\Local"
New-Item -ItemType Directory -Force -Path $VerificationLogRoot | Out-Null

$VerificationFailed = $false
$PreflightSucceeded = $true
$BranchSucceeded = $true

function Add-UniquePath {
    param(
        [System.Collections.Generic.List[string]]$Paths,
        [string]$Candidate
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return
    }

    $ExpandedCandidate = [Environment]::ExpandEnvironmentVariables($Candidate.Trim().Trim('"'))
    if (-not $Paths.Contains($ExpandedCandidate)) {
        $Paths.Add($ExpandedCandidate)
    }
}

function Find-FirstExistingFile {
    param([string[]]$Candidates)

    foreach ($Candidate in $Candidates) {
        if ([IO.File]::Exists($Candidate)) {
            return $Candidate
        }
    }
    return $null
}

function Add-PythonCandidate {
    param(
        [System.Collections.Generic.List[object]]$Candidates,
        [string]$Executable,
        [string[]]$PrefixArguments = @()
    )

    if ([string]::IsNullOrWhiteSpace($Executable)) {
        return
    }

    $Key = "$Executable|$($PrefixArguments -join ' ')"
    if (-not ($Candidates | Where-Object { $_.Key -eq $Key })) {
        $Candidates.Add([PSCustomObject]@{
            Key = $Key
            Executable = $Executable
            PrefixArguments = $PrefixArguments
        })
    }
}

Push-Location $ProjectRoot
try {
    $CurrentBranch = (& git branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to determine the current Git branch."
    }
    Write-Output "BRANCH=$CurrentBranch"
    Write-Output "EXPECTED_BRANCH=$ExpectedBranch"
    if ($CurrentBranch -ne $ExpectedBranch) {
        Write-Output "BRANCH_RESULT=FAIL"
        $BranchSucceeded = $false
        $VerificationFailed = $true
    }
    else {
        Write-Output "BRANCH_RESULT=PASS"
    }

    $EngineCandidates = [System.Collections.Generic.List[string]]::new()
    Add-UniquePath $EngineCandidates $UERoot
    Add-UniquePath $EngineCandidates $env:UE_ROOT

    foreach ($Drive in Get-PSDrive -PSProvider FileSystem) {
        if ($Drive.Root -notmatch '^[A-Za-z]:\\$') {
            continue
        }

        foreach ($Suffix in @(
            "Program Files\Epic Games\UE_5.8.1",
            "Program Files\Epic Games\UE_5.8",
            "Epic Games\UE_5.8.1",
            "Epic Games\UE_5.8",
            "UnrealEngine\UE_5.8.1",
            "UnrealEngine\UE_5.8",
            "UE_5.8.1",
            "UE_5.8"
        )) {
            Add-UniquePath $EngineCandidates ([IO.Path]::Combine($Drive.Root, $Suffix))
        }
    }

    foreach ($RegistryPath in @(
        "HKLM:\SOFTWARE\EpicGames\Unreal Engine\5.8",
        "HKLM:\SOFTWARE\WOW6432Node\EpicGames\Unreal Engine\5.8"
    )) {
        $RegistryInstall = Get-ItemProperty -Path $RegistryPath -ErrorAction SilentlyContinue
        if ($RegistryInstall -and $RegistryInstall.InstalledDirectory) {
            Add-UniquePath $EngineCandidates ([string]$RegistryInstall.InstalledDirectory)
        }
    }

    $UserBuilds = Get-ItemProperty -Path "HKCU:\Software\Epic Games\Unreal Engine\Builds" -ErrorAction SilentlyContinue
    if ($UserBuilds) {
        foreach ($Property in $UserBuilds.PSObject.Properties) {
            if ($Property.Name -notlike "PS*" -and $Property.Value -is [string]) {
                Add-UniquePath $EngineCandidates ([string]$Property.Value)
            }
        }
    }

    foreach ($LauncherFile in @(
        "C:\ProgramData\Epic\UnrealEngineLauncher\LauncherInstalled.dat",
        "C:\ProgramData\Epic\EpicGamesLauncher\Data\LauncherInstalled.dat",
        "D:\ProgramData\Epic\UnrealEngineLauncher\LauncherInstalled.dat"
    )) {
        if (-not [IO.File]::Exists($LauncherFile)) {
            continue
        }

        try {
            $LauncherData = Get-Content -Raw -LiteralPath $LauncherFile | ConvertFrom-Json
            foreach ($Installation in @($LauncherData.InstallationList)) {
                if ($Installation.AppName -like "UE_5.8*" -or $Installation.AppVersion -like "5.8*") {
                    Add-UniquePath $EngineCandidates ([string]$Installation.InstallLocation)
                }
            }
        }
        catch {
            Write-Output "ENGINE_MANIFEST_WARNING=$LauncherFile could not be parsed: $($_.Exception.Message)"
        }
    }

    $SelectedEngine = $null
    foreach ($CandidateRoot in $EngineCandidates) {
        $BuildVersionPath = Join-Path $CandidateRoot "Engine\Build\Build.version"
        $UnrealEditorPath = Join-Path $CandidateRoot "Engine\Binaries\Win64\UnrealEditor.exe"
        $BuildBatchPath = Join-Path $CandidateRoot "Engine\Build\BatchFiles\Build.bat"
        $RunUATPath = Join-Path $CandidateRoot "Engine\Build\BatchFiles\RunUAT.bat"
        $UnrealBuildToolPath = Find-FirstExistingFile @(
            (Join-Path $CandidateRoot "Engine\Binaries\DotNET\UnrealBuildTool\UnrealBuildTool.exe"),
            (Join-Path $CandidateRoot "Engine\Binaries\DotNET\UnrealBuildTool\UnrealBuildTool.dll"),
            (Join-Path $CandidateRoot "Engine\Binaries\DotNET\UnrealBuildTool.exe")
        )
        $PixelStreaming2PluginPath = Find-FirstExistingFile @(
            (Join-Path $CandidateRoot "Engine\Plugins\Media\PixelStreaming2\PixelStreaming2.uplugin"),
            (Join-Path $CandidateRoot "Engine\Plugins\Media\PixelStreaming\PixelStreaming2.uplugin")
        )

        $Version = "UNKNOWN"
        $IsVersion58 = $false
        if ([IO.File]::Exists($BuildVersionPath)) {
            try {
                $BuildVersion = Get-Content -Raw -LiteralPath $BuildVersionPath | ConvertFrom-Json
                $Version = "$($BuildVersion.MajorVersion).$($BuildVersion.MinorVersion).$($BuildVersion.PatchVersion)"
                $IsVersion58 = $BuildVersion.MajorVersion -eq 5 -and $BuildVersion.MinorVersion -eq 8
            }
            catch {
                $Version = "INVALID_BUILD_VERSION"
            }
        }

        $HasEditor = [IO.File]::Exists($UnrealEditorPath)
        $HasBuildBatch = [IO.File]::Exists($BuildBatchPath)
        $HasRunUAT = [IO.File]::Exists($RunUATPath)
        $HasUBT = -not [string]::IsNullOrWhiteSpace($UnrealBuildToolPath)
        $HasPixelStreaming2 = -not [string]::IsNullOrWhiteSpace($PixelStreaming2PluginPath)
        Write-Output "ENGINE_CANDIDATE=$CandidateRoot;VERSION=$Version;EDITOR=$HasEditor;BUILD_BAT=$HasBuildBatch;RUN_UAT=$HasRunUAT;UBT=$HasUBT;PIXEL_STREAMING2=$HasPixelStreaming2"

        if (-not $SelectedEngine -and $IsVersion58 -and $HasEditor -and $HasBuildBatch -and $HasRunUAT -and $HasUBT) {
            $SelectedEngine = [PSCustomObject]@{
                Root = $CandidateRoot
                Version = $Version
                UnrealEditor = $UnrealEditorPath
                BuildBatch = $BuildBatchPath
                RunUAT = $RunUATPath
                UnrealBuildTool = $UnrealBuildToolPath
                PixelStreaming2Plugin = $PixelStreaming2PluginPath
            }
        }
    }

    $PythonCandidates = [System.Collections.Generic.List[object]]::new()
    Add-PythonCandidate $PythonCandidates $PythonExecutable
    Add-PythonCandidate $PythonCandidates $env:PYTHON

    $PythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($PythonCommand) {
        Add-PythonCandidate $PythonCandidates $PythonCommand.Source
    }

    $PythonLauncher = Get-Command py.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($PythonLauncher) {
        Add-PythonCandidate $PythonCandidates $PythonLauncher.Source @("-3")
    }

    if ($env:USERPROFILE) {
        Add-PythonCandidate $PythonCandidates (Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe")
    }
    if ($env:LOCALAPPDATA) {
        foreach ($PythonVersion in @("Python313", "Python312", "Python311")) {
            Add-PythonCandidate $PythonCandidates (Join-Path $env:LOCALAPPDATA "Programs\Python\$PythonVersion\python.exe")
        }
    }

    $SelectedPython = $null
    foreach ($CandidatePython in $PythonCandidates) {
        if (-not [IO.File]::Exists($CandidatePython.Executable)) {
            continue
        }

        & $CandidatePython.Executable @($CandidatePython.PrefixArguments) --version *> $null
        if ($LASTEXITCODE -eq 0) {
            $SelectedPython = $CandidatePython
            break
        }
    }

    $PreflightScripts = [ordered]@{
        BASE = "ci/preflight.py"
        PHASE2 = "ci/preflight_phase2.py"
        PHASE3 = "ci/preflight_phase3.py"
        PHASE4 = "ci/preflight_phase4.py"
        PHASE5 = "ci/preflight_phase5.py"
        STATIC_CPP_SANITY = "ci/static_cpp_sanity.py"
        WEB_DELIVERY = "ci/preflight_web_delivery.py"
        NATIVE_DELIVERY = "ci/preflight_native_delivery.py"
        SECURITY = "ci/security_static_audit.py"
    }
    $PreflightResults = [ordered]@{}

    if (-not $SelectedPython) {
        Write-Output "PYTHON=NOT_FOUND"
        foreach ($PreflightName in $PreflightScripts.Keys) {
            $PreflightResults[$PreflightName] = "NOT_RUN_NO_PYTHON"
        }
        $PreflightSucceeded = $false
        $VerificationFailed = $true
    }
    else {
        $PythonPrefix = @($SelectedPython.PrefixArguments)
        Write-Output "PYTHON=$($SelectedPython.Executable) $($PythonPrefix -join ' ')".TrimEnd()

        foreach ($PreflightName in $PreflightScripts.Keys) {
            $RelativeScript = $PreflightScripts[$PreflightName]
            $PreflightLog = Join-Path $VerificationLogRoot ("preflight_{0}.log" -f $PreflightName.ToLowerInvariant())
            $PythonArguments = $PythonPrefix + @((Join-Path $ProjectRoot $RelativeScript))
            Write-Output "COMMAND_PREFLIGHT_$PreflightName=`"$($SelectedPython.Executable)`" $($PythonArguments -join ' ')"

            & $SelectedPython.Executable @PythonArguments 2>&1 | Tee-Object -FilePath $PreflightLog
            $PreflightExitCode = $LASTEXITCODE
            if ($PreflightExitCode -eq 0) {
                $PreflightResults[$PreflightName] = "PASS"
            }
            else {
                $PreflightResults[$PreflightName] = "FAIL_EXIT_$PreflightExitCode"
                $PreflightSucceeded = $false
                $VerificationFailed = $true
            }
            Write-Output "LOG_PREFLIGHT_$PreflightName=$PreflightLog"
        }
    }

    $PowerShellSanityScript = Join-Path $ProjectRoot "ci\powershell_sanity.ps1"
    $PowerShellSanityLog = Join-Path $VerificationLogRoot "preflight_powershell_sanity.log"
    Write-Output "COMMAND_PREFLIGHT_POWERSHELL_SANITY=powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PowerShellSanityScript`""
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PowerShellSanityScript 2>&1 | Tee-Object -FilePath $PowerShellSanityLog
    $PowerShellSanityExitCode = $LASTEXITCODE
    if ($PowerShellSanityExitCode -eq 0) {
        $PreflightResults["POWERSHELL_SANITY"] = "PASS"
    }
    else {
        $PreflightResults["POWERSHELL_SANITY"] = "FAIL_EXIT_$PowerShellSanityExitCode"
        $PreflightSucceeded = $false
        $VerificationFailed = $true
    }
    Write-Output "LOG_PREFLIGHT_POWERSHELL_SANITY=$PowerShellSanityLog"

    $BuildTargets = [ordered]@{
        EDITOR = "ArabiaStrikeWorldWarEditor"
        CLIENT = "ArabiaStrikeWorldWar"
        SERVER = "ArabiaStrikeWorldWarServer"
    }
    $BuildResults = [ordered]@{}

    if (-not $SelectedEngine) {
        foreach ($BuildName in $BuildTargets.Keys) {
            $BuildResults[$BuildName] = "NOT_RUN_NO_VALID_UE58"
        }
        $VerificationFailed = $true
    }
    elseif (-not $BranchSucceeded) {
        foreach ($BuildName in $BuildTargets.Keys) {
            $BuildResults[$BuildName] = "NOT_RUN_BRANCH_MISMATCH"
        }
        $VerificationFailed = $true
    }
    elseif (-not $PreflightSucceeded) {
        foreach ($BuildName in $BuildTargets.Keys) {
            $BuildResults[$BuildName] = "NOT_RUN_PREFLIGHT_FAILURE"
        }
        $VerificationFailed = $true
    }
    else {
        foreach ($BuildName in $BuildTargets.Keys) {
            $TargetName = $BuildTargets[$BuildName]
            $BuildLog = Join-Path $VerificationLogRoot ("build_{0}_win64_development.log" -f $BuildName.ToLowerInvariant())
            $BuildArguments = @(
                $TargetName,
                "Win64",
                "Development",
                "-Project=$ProjectFile",
                "-WaitMutex",
                "-NoHotReloadFromIDE"
            )
            Write-Output "COMMAND_BUILD_$BuildName=`"$($SelectedEngine.BuildBatch)`" $($BuildArguments -join ' ')"

            & $SelectedEngine.BuildBatch @BuildArguments 2>&1 | Tee-Object -FilePath $BuildLog
            $BuildExitCode = $LASTEXITCODE
            if ($BuildExitCode -eq 0) {
                $BuildResults[$BuildName] = "PASS"
            }
            else {
                $BuildResults[$BuildName] = "FAIL_EXIT_$BuildExitCode"
                $VerificationFailed = $true
            }
            Write-Output "LOG_BUILD_$BuildName=$BuildLog"
        }
    }

    $PreflightSummary = ($PreflightResults.Keys | ForEach-Object { "$_=$($PreflightResults[$_])" }) -join ","
    $AllBuildsPassed = $BuildResults.Count -eq $BuildTargets.Count -and -not ($BuildResults.Values | Where-Object { $_ -ne "PASS" })

    if ($SelectedEngine) {
        $EngineVersionResult = $SelectedEngine.Version
        $EngineRootResult = $SelectedEngine.Root
        $EditorResult = $SelectedEngine.UnrealEditor
        $BuildBatchResult = $SelectedEngine.BuildBatch
        $RunUATResult = $SelectedEngine.RunUAT
        $UBTPathResult = $SelectedEngine.UnrealBuildTool
        $PixelStreaming2PluginResult = if ($SelectedEngine.PixelStreaming2Plugin) { $SelectedEngine.PixelStreaming2Plugin } else { "NOT_FOUND" }
    }
    else {
        $EngineVersionResult = "NOT_FOUND"
        $EngineRootResult = "NOT_FOUND"
        $EditorResult = "NOT_FOUND"
        $BuildBatchResult = "NOT_FOUND"
        $RunUATResult = "NOT_FOUND"
        $UBTPathResult = "NOT_FOUND"
        $PixelStreaming2PluginResult = "NOT_FOUND"
    }

    if ($AllBuildsPassed) {
        $UBTResult = "PASS_ALL_TARGETS"
        $UHTResult = "PASS_VIA_UBT"
    }
    elseif (-not $SelectedEngine) {
        $UBTResult = "NOT_RUN_NO_VALID_UE58"
        $UHTResult = "NOT_RUN_NO_VALID_UE58"
    }
    else {
        $UBTResult = "FAIL_OR_NOT_RUN_SEE_TARGET_RESULTS"
        $UHTResult = "FAIL_OR_INDETERMINATE_SEE_BUILD_LOGS"
    }

    $SummaryLines = @(
        "BRANCH=$CurrentBranch",
        "UE_VERSION=$EngineVersionResult",
        "UE_ROOT=$EngineRootResult",
        "UNREAL_EDITOR=$EditorResult",
        "BUILD_BAT=$BuildBatchResult",
        "RUN_UAT=$RunUATResult",
        "UNREAL_BUILD_TOOL=$UBTPathResult",
        "PIXEL_STREAMING2_PLUGIN=$PixelStreaming2PluginResult",
        "PREFLIGHT_RESULTS=$PreflightSummary",
        "UBT_RESULT=$UBTResult",
        "UHT_RESULT=$UHTResult",
        "EDITOR_BUILD_RESULT=$($BuildResults.EDITOR)",
        "CLIENT_BUILD_RESULT=$($BuildResults.CLIENT)",
        "SERVER_BUILD_RESULT=$($BuildResults.SERVER)",
        "VERIFICATION_LOG_ROOT=$VerificationLogRoot",
        "OVERALL_RESULT=$(if ($VerificationFailed) { 'FAIL' } else { 'PASS' })"
    )

    $SummaryPath = Join-Path $VerificationLogRoot "verification_summary.txt"
    [IO.File]::WriteAllLines($SummaryPath, $SummaryLines, [Text.UTF8Encoding]::new($false))
    Write-Output "VERIFICATION_SUMMARY=$SummaryPath"
    $SummaryLines | ForEach-Object { Write-Output $_ }
}
finally {
    Pop-Location
}

if ($VerificationFailed) {
    exit 1
}
exit 0
