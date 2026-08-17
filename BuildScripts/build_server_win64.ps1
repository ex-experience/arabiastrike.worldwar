[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$UERoot,
    [ValidateSet("Development", "Shipping")][string]$Configuration = "Development"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$RunUAT = Join-Path $UERoot "Engine\Build\BatchFiles\RunUAT.bat"
$BuildVersionPath = Join-Path $UERoot "Engine\Build\Build.version"
$ArchiveRoot = Join-Path $ProjectRoot "BuildOutput\Server"

if (-not [IO.Directory]::Exists($UERoot)) {
    throw "Unreal Engine root does not exist: '$UERoot'."
}
if (-not [IO.File]::Exists($ProjectFile)) {
    throw "Project descriptor was not found: '$ProjectFile'."
}
if (-not [IO.File]::Exists($RunUAT) -or -not [IO.File]::Exists($BuildVersionPath)) {
    throw "RunUAT.bat or Build.version was not found under '$UERoot'."
}

$BuildVersion = Get-Content -Raw -LiteralPath $BuildVersionPath | ConvertFrom-Json
$DetectedVersion = "$($BuildVersion.MajorVersion).$($BuildVersion.MinorVersion).$($BuildVersion.PatchVersion)"
if ($BuildVersion.MajorVersion -ne 5 -or $BuildVersion.MinorVersion -ne 8) {
    throw "UE 5.8 is required; detected '$DetectedVersion'."
}

New-Item -ItemType Directory -Force -Path $ArchiveRoot | Out-Null
$Arguments = @(
    "BuildCookRun",
    "-project=$ProjectFile",
    "-noP4",
    "-server",
    "-noclient",
    "-serverplatform=Win64",
    "-serverconfig=$Configuration",
    "-build",
    "-cook",
    "-stage",
    "-pak",
    "-package",
    "-archive",
    "-archivedirectory=$ArchiveRoot",
    "-utf8output"
)

Write-Output "UE_VERSION=$DetectedVersion"
Write-Output "UE_ROOT=$UERoot"
Write-Output "PROJECT=$ProjectFile"
Write-Output "ARCHIVE_ROOT=$ArchiveRoot"
Write-Output "COMMAND=`"$RunUAT`" $($Arguments -join ' ')"
& $RunUAT @Arguments
if ($LASTEXITCODE -ne 0) {
    Write-Output "WIN64_SERVER_PACKAGE_RESULT=FAIL_EXIT_$LASTEXITCODE"
    exit $LASTEXITCODE
}

$Artifacts = @(Get-ChildItem -LiteralPath $ArchiveRoot -Recurse -File -Filter "ArabiaStrikeWorldWarServer.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\Engine\\Binaries\\' })
if ($Artifacts.Count -eq 0) {
    throw "UAT completed but no packaged ArabiaStrikeWorldWarServer.exe was found under '$ArchiveRoot'."
}

$Artifacts | ForEach-Object { Write-Output "WIN64_SERVER_ARTIFACT=$($_.FullName)" }
Write-Output "WIN64_SERVER_PACKAGE_RESULT=PASS"
exit 0
