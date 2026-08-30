[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$UERoot,
    [ValidateSet("Development", "Shipping")][string]$Configuration = "Development",
    [ValidateSet("APK", "AAB")][string]$OutputFormat = "APK",
    [ValidateSet("ASTC", "ETC2", "DXT")][string]$CookFlavor = "ASTC",
    [switch]$ForDistribution
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Project = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
if ([string]::IsNullOrWhiteSpace($UERoot) -or -not [IO.Directory]::Exists($UERoot)) {
    throw "Unreal Engine root does not exist: '$UERoot'."
}
$RunUAT = Join-Path $UERoot "Engine\Build\BatchFiles\RunUAT.bat"
$BuildVersionPath = Join-Path $UERoot "Engine\Build\Build.version"
$ArchiveRoot = Join-Path $ProjectRoot "BuildOutput\Android\$OutputFormat"

if (-not [IO.File]::Exists($RunUAT) -or -not [IO.File]::Exists($BuildVersionPath)) {
    throw "UE 5.8 RunUAT or Build.version was not found under '$UERoot'."
}

$BuildVersion = Get-Content -Raw -LiteralPath $BuildVersionPath | ConvertFrom-Json
$DetectedVersion = "$($BuildVersion.MajorVersion).$($BuildVersion.MinorVersion).$($BuildVersion.PatchVersion)"
if ($BuildVersion.MajorVersion -ne 5 -or $BuildVersion.MinorVersion -ne 8) {
    throw "UE 5.8 is required; detected '$DetectedVersion'."
}

$MissingToolchain = [System.Collections.Generic.List[string]]::new()
foreach ($VariableName in @("ANDROID_HOME", "JAVA_HOME")) {
    $Value = [Environment]::GetEnvironmentVariable($VariableName)
    if ([string]::IsNullOrWhiteSpace($Value) -or -not [IO.Directory]::Exists($Value)) {
        $MissingToolchain.Add($VariableName)
    }
}
$NdkRoot = if ($env:NDKROOT) { $env:NDKROOT } elseif ($env:NDK_ROOT) { $env:NDK_ROOT } else { $null }
if ([string]::IsNullOrWhiteSpace($NdkRoot) -or -not [IO.Directory]::Exists($NdkRoot)) {
    $MissingToolchain.Add("NDKROOT/NDK_ROOT")
}
if ($MissingToolchain.Count -gt 0) {
    throw "Android toolchain is unavailable: $($MissingToolchain -join ', '). Configure UE 5.8 Turnkey before packaging."
}

New-Item -ItemType Directory -Force -Path $ArchiveRoot | Out-Null
$Arguments = @(
    "BuildCookRun",
    "-project=$Project",
    "-noP4",
    "-platform=Android",
    "-clientconfig=$Configuration",
    "-build",
    "-cook",
    "-cookflavor=$CookFlavor",
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
Write-Output "ANDROID_OUTPUT_FORMAT_EXPECTED=$OutputFormat"
Write-Output "COMMAND=`"$RunUAT`" $($Arguments -join ' ')"
& $RunUAT @Arguments
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$ExpectedExtension = if ($OutputFormat -eq "AAB") { ".aab" } else { ".apk" }
$Artifacts = @(Get-ChildItem -LiteralPath $ArchiveRoot -Recurse -File | Where-Object { $_.Extension -ieq $ExpectedExtension })
if ($Artifacts.Count -eq 0) {
    throw "UAT completed but no $ExpectedExtension artifact was found. Configure AndroidRuntimeSettings for the requested output format."
}

$Artifacts | ForEach-Object { Write-Output "ANDROID_ARTIFACT=$($_.FullName)" }
Write-Output "ANDROID_PACKAGE_RESULT=PASS"
