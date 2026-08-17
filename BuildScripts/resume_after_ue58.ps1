[CmdletBinding()]
param(
    [string]$UERoot,
    [string]$PythonExecutable,
    [string]$ExpectedBranch = "codex/asww-development"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$VerificationScript = Join-Path $PSScriptRoot "verify_unreal_local.ps1"
$ResumeLogRoot = Join-Path $ProjectRoot "Saved\Verification\Resume"
$UnrealSummaryPath = Join-Path $ProjectRoot "Saved\Verification\Local\verification_summary.txt"
$JeddahMapPath = Join-Path $ProjectRoot "Content\Maps\Jeddah_RedSea_Assault.umap"

function Add-UniqueCandidate {
    param(
        [System.Collections.Generic.List[string]]$Candidates,
        [string]$Candidate
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return
    }
    $Expanded = [Environment]::ExpandEnvironmentVariables($Candidate.Trim().Trim('"'))
    if (-not $Candidates.Contains($Expanded)) {
        $Candidates.Add($Expanded)
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

function Get-SummaryValue {
    param(
        [string[]]$Lines,
        [string]$Key,
        [string]$Fallback = "NOT_REPORTED"
    )

    $Prefix = "$Key="
    $Line = $Lines | Where-Object { $_.StartsWith($Prefix, [StringComparison]::Ordinal) } | Select-Object -Last 1
    if ($Line) {
        return $Line.Substring($Prefix.Length)
    }
    return $Fallback
}

if (-not [IO.File]::Exists($VerificationScript)) {
    throw "Unreal verification script was not found: $VerificationScript"
}

$Candidates = [System.Collections.Generic.List[string]]::new()
Add-UniqueCandidate $Candidates $UERoot
Add-UniqueCandidate $Candidates $env:UE_ROOT

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
        Add-UniqueCandidate $Candidates ([IO.Path]::Combine($Drive.Root, $Suffix))
    }
}

foreach ($RegistryPath in @(
    "HKLM:\SOFTWARE\EpicGames\Unreal Engine\5.8",
    "HKLM:\SOFTWARE\WOW6432Node\EpicGames\Unreal Engine\5.8"
)) {
    $RegistryInstall = Get-ItemProperty -Path $RegistryPath -ErrorAction SilentlyContinue
    if ($RegistryInstall -and $RegistryInstall.InstalledDirectory) {
        Add-UniqueCandidate $Candidates ([string]$RegistryInstall.InstalledDirectory)
    }
}

$UserBuilds = Get-ItemProperty -Path "HKCU:\Software\Epic Games\Unreal Engine\Builds" -ErrorAction SilentlyContinue
if ($UserBuilds) {
    foreach ($Property in $UserBuilds.PSObject.Properties) {
        if ($Property.Name -notlike "PS*" -and $Property.Value -is [string]) {
            Add-UniqueCandidate $Candidates ([string]$Property.Value)
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
                Add-UniqueCandidate $Candidates ([string]$Installation.InstallLocation)
            }
        }
    }
    catch {
        Write-Output "ENGINE_MANIFEST_WARNING=$LauncherFile could not be parsed"
    }
}

$SelectedEngine = $null
foreach ($CandidateRoot in $Candidates) {
    $BuildVersionPath = Join-Path $CandidateRoot "Engine\Build\Build.version"
    $UnrealEditorPath = Join-Path $CandidateRoot "Engine\Binaries\Win64\UnrealEditor.exe"
    $BuildBatchPath = Join-Path $CandidateRoot "Engine\Build\BatchFiles\Build.bat"
    $RunUATPath = Join-Path $CandidateRoot "Engine\Build\BatchFiles\RunUAT.bat"
    $UnrealBuildToolPath = Find-FirstExistingFile @(
        (Join-Path $CandidateRoot "Engine\Binaries\DotNET\UnrealBuildTool\UnrealBuildTool.exe"),
        (Join-Path $CandidateRoot "Engine\Binaries\DotNET\UnrealBuildTool\UnrealBuildTool.dll"),
        (Join-Path $CandidateRoot "Engine\Binaries\DotNET\UnrealBuildTool.exe")
    )

    $Version = "NOT_FOUND"
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

    $ToolsPresent = [IO.File]::Exists($UnrealEditorPath) -and
        [IO.File]::Exists($BuildBatchPath) -and
        [IO.File]::Exists($RunUATPath) -and
        -not [string]::IsNullOrWhiteSpace($UnrealBuildToolPath)
    Write-Output "UE_CANDIDATE=$CandidateRoot;VERSION=$Version;TOOLS_PRESENT=$ToolsPresent"

    if (-not $SelectedEngine -and $IsVersion58 -and $ToolsPresent) {
        $SelectedEngine = [PSCustomObject]@{
            Root = $CandidateRoot
            Version = $Version
            UnrealEditor = $UnrealEditorPath
            BuildBatch = $BuildBatchPath
            RunUAT = $RunUATPath
            UnrealBuildTool = $UnrealBuildToolPath
        }
    }
}

$JeddahMapResult = if ([IO.File]::Exists($JeddahMapPath)) { "FOUND_UNVALIDATED" } else { "NOT_FOUND" }
if (-not $SelectedEngine) {
    Write-Output "UE_DETECTED=NO"
    Write-Output "UE_ROOT=NOT_FOUND"
    Write-Output "UE_TASKS=BLOCKED"
    Write-Output "UHT=NOT_RUN_NO_VALID_UE58"
    Write-Output "UBT=NOT_RUN_NO_VALID_UE58"
    Write-Output "EDITOR_BUILD=NOT_RUN_NO_VALID_UE58"
    Write-Output "CLIENT_BUILD=NOT_RUN_NO_VALID_UE58"
    Write-Output "SERVER_BUILD=NOT_RUN_NO_VALID_UE58"
    Write-Output "JEDDAH_UMAP=$JeddahMapResult"
    Write-Output "NEXT_ACTION=Complete the UE 5.8 installation, then rerun BuildScripts/resume_after_ue58.ps1."
    exit 2
}

Write-Output "UE_DETECTED=YES"
Write-Output "UE_VERSION=$($SelectedEngine.Version)"
Write-Output "UE_ROOT=$($SelectedEngine.Root)"
Write-Output "UNREAL_EDITOR=$($SelectedEngine.UnrealEditor)"
Write-Output "BUILD_BAT=$($SelectedEngine.BuildBatch)"
Write-Output "RUN_UAT=$($SelectedEngine.RunUAT)"
Write-Output "UNREAL_BUILD_TOOL=$($SelectedEngine.UnrealBuildTool)"

New-Item -ItemType Directory -Force -Path $ResumeLogRoot | Out-Null
$ResumeLog = Join-Path $ResumeLogRoot ("verify_unreal_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$VerifyArguments = @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy", "Bypass",
    "-File", $VerificationScript,
    "-UERoot", $SelectedEngine.Root,
    "-ExpectedBranch", $ExpectedBranch
)
if (-not [string]::IsNullOrWhiteSpace($PythonExecutable)) {
    $VerifyArguments += @("-PythonExecutable", $PythonExecutable)
}

& powershell.exe @VerifyArguments 2>&1 | Tee-Object -FilePath $ResumeLog
$VerifyExitCode = $LASTEXITCODE
Write-Output "UNREAL_VERIFICATION_LOG=$ResumeLog"

$SummaryLines = if ([IO.File]::Exists($UnrealSummaryPath)) { @(Get-Content -LiteralPath $UnrealSummaryPath) } else { @() }
$UHTResult = Get-SummaryValue $SummaryLines "UHT_RESULT"
$UBTResult = Get-SummaryValue $SummaryLines "UBT_RESULT"
$EditorBuildResult = Get-SummaryValue $SummaryLines "EDITOR_BUILD_RESULT"
$ClientBuildResult = Get-SummaryValue $SummaryLines "CLIENT_BUILD_RESULT"
$ServerBuildResult = Get-SummaryValue $SummaryLines "SERVER_BUILD_RESULT"

Write-Output "UHT=$UHTResult"
Write-Output "UBT=$UBTResult"
Write-Output "EDITOR_BUILD=$EditorBuildResult"
Write-Output "CLIENT_BUILD=$ClientBuildResult"
Write-Output "SERVER_BUILD=$ServerBuildResult"
Write-Output "JEDDAH_UMAP=$JeddahMapResult"

if ($VerifyExitCode -ne 0) {
    Write-Output "UE_TASKS=FAILED_OR_BLOCKED"
    Write-Output "NEXT_ACTION=Resolve the first real failure in the Unreal verification log, then rerun this script."
    exit $VerifyExitCode
}
if ($JeddahMapResult -eq "NOT_FOUND") {
    Write-Output "UE_TASKS=BUILDS_PASS_MAP_BLOCKED"
    Write-Output "NEXT_ACTION=Create Content/Maps/Jeddah_RedSea_Assault.umap in Unreal Editor, then validate map load and PIE."
    exit 3
}

Write-Output "UE_TASKS=BUILDS_PASS_MAP_REQUIRES_EDITOR_VALIDATION"
Write-Output "NEXT_ACTION=Run real editor map-load and PIE validation before packaging."
exit 0
