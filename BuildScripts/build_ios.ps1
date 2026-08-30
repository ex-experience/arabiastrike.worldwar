[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$UERoot,
    [ValidateSet("Development", "Shipping")][string]$Configuration = "Development",
    [switch]$ForDistribution
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Project = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
if ([string]::IsNullOrWhiteSpace($UERoot) -or -not [IO.Directory]::Exists($UERoot)) {
    throw "Unreal Engine root does not exist: '$UERoot'."
}
$HostPlatform = [System.Environment]::OSVersion.Platform
if ($HostPlatform -ne [System.PlatformID]::Win32NT) {
    throw "This PowerShell entry automates Unreal's Windows-to-Mac remote-build path. On macOS, invoke Engine/Build/BatchFiles/RunUAT.sh directly."
}
$RunUAT = Join-Path $UERoot "Engine\Build\BatchFiles\RunUAT.bat"
$BuildVersionPath = Join-Path $UERoot "Engine\Build\Build.version"
$ArchiveRoot = Join-Path $ProjectRoot "BuildOutput\IOS"

if (-not [IO.File]::Exists($RunUAT) -or -not [IO.File]::Exists($BuildVersionPath)) {
    throw "UE 5.8 RunUAT or Build.version was not found under '$UERoot'."
}

$BuildVersion = Get-Content -Raw -LiteralPath $BuildVersionPath | ConvertFrom-Json
$DetectedVersion = "$($BuildVersion.MajorVersion).$($BuildVersion.MinorVersion).$($BuildVersion.PatchVersion)"
if ($BuildVersion.MajorVersion -ne 5 -or $BuildVersion.MinorVersion -ne 8) {
    throw "UE 5.8 is required; detected '$DetectedVersion'."
}

Write-Output "IOS_BUILD_PATH=WINDOWS_TO_REMOTE_MAC"
Write-Output "IOS_PREREQUISITES=PRECONFIGURED_REMOTE_MAC,XCODE,SIGNING_CERTIFICATE,PROVISIONING_PROFILE"
Write-Output "IOS_CREDENTIALS=NOT_COLLECTED_BY_SCRIPT"

New-Item -ItemType Directory -Force -Path $ArchiveRoot | Out-Null
$Arguments = @(
    "BuildCookRun",
    "-project=$Project",
    "-noP4",
    "-platform=IOS",
    "-clientconfig=$Configuration",
    "-build",
    "-cook",
    "-stage",
    "-pak",
    "-package",
    "-archive",
    "-archivedirectory=$ArchiveRoot",
    "-utf8output"
)
if ($ForDistribution) {
    $Arguments += "-distribution"
}

Write-Output "UE_VERSION=$DetectedVersion"
Write-Output "UE_ROOT=$UERoot"
Write-Output "PROJECT=$Project"
Write-Output "COMMAND=`"$RunUAT`" $($Arguments -join ' ')"
& $RunUAT @Arguments
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$Artifacts = @(Get-ChildItem -LiteralPath $ArchiveRoot -Recurse -File -Filter "*.ipa")
if ($Artifacts.Count -eq 0) {
    throw "UAT completed but no .ipa artifact was found. Verify remote Mac and Apple signing configuration."
}

$Artifacts | ForEach-Object { Write-Output "IOS_ARTIFACT=$($_.FullName)" }
Write-Output "IOS_PACKAGE_RESULT=PASS"
