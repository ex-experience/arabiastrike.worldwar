[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$UERoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$MinimumWindowsSdk = [Version]"10.0.19041.0"
$BuildVersionPath = Join-Path $UERoot "Engine\Build\Build.version"
$RequiredEngineFiles = [ordered]@{
    UNREAL_EDITOR = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor.exe"
    UNREAL_EDITOR_CMD = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
    BUILD_BAT = Join-Path $UERoot "Engine\Build\BatchFiles\Build.bat"
    RUN_UAT = Join-Path $UERoot "Engine\Build\BatchFiles\RunUAT.bat"
    TOOL_COMPLETE = Join-Path $UERoot "ToolComplete.txt"
}
$RequiredPlugins = [ordered]@{
    PIXEL_STREAMING2 = Join-Path $UERoot "Engine\Plugins\Media\PixelStreaming2\PixelStreaming2.uplugin"
    PYTHON_SCRIPT = Join-Path $UERoot "Engine\Plugins\Experimental\PythonScriptPlugin\PythonScriptPlugin.uplugin"
    EDITOR_SCRIPTING = Join-Path $UERoot "Engine\Plugins\Editor\EditorScriptingUtilities\EditorScriptingUtilities.uplugin"
    PYTHON_AUTOMATION = Join-Path $UERoot "Engine\Plugins\Tests\PythonAutomationTest\PythonAutomationTest.uplugin"
}

$Failures = [System.Collections.Generic.List[string]]::new()
if (-not [IO.File]::Exists($BuildVersionPath)) {
    $Failures.Add("UE Build.version is missing")
    $DetectedVersion = "NOT_FOUND"
}
else {
    $BuildVersion = Get-Content -Raw -LiteralPath $BuildVersionPath | ConvertFrom-Json
    $DetectedVersion = "$($BuildVersion.MajorVersion).$($BuildVersion.MinorVersion).$($BuildVersion.PatchVersion)"
    if ($BuildVersion.MajorVersion -ne 5 -or $BuildVersion.MinorVersion -ne 8) {
        $Failures.Add("UE 5.8 is required; detected '$DetectedVersion'")
    }
}

Write-Output "UE_VERSION=$DetectedVersion"
Write-Output "UE_ROOT=$UERoot"
foreach ($Entry in $RequiredEngineFiles.GetEnumerator()) {
    $Exists = [IO.File]::Exists($Entry.Value)
    Write-Output "$($Entry.Key)=$(if ($Exists) { $Entry.Value } else { 'NOT_FOUND' })"
    if (-not $Exists) {
        $Failures.Add("$($Entry.Key) is missing")
    }
}
foreach ($Entry in $RequiredPlugins.GetEnumerator()) {
    $Exists = [IO.File]::Exists($Entry.Value)
    Write-Output "$($Entry.Key)_PLUGIN=$(if ($Exists) { $Entry.Value } else { 'NOT_FOUND' })"
    if (-not $Exists) {
        $Failures.Add("$($Entry.Key) plugin is missing")
    }
}

$UBT = @(
    (Join-Path $UERoot "Engine\Binaries\DotNET\UnrealBuildTool\UnrealBuildTool.exe"),
    (Join-Path $UERoot "Engine\Binaries\DotNET\UnrealBuildTool\UnrealBuildTool.dll"),
    (Join-Path $UERoot "Engine\Binaries\DotNET\UnrealBuildTool.exe")
) | Where-Object { [IO.File]::Exists($_) } | Select-Object -First 1
Write-Output "UNREAL_BUILD_TOOL=$(if ($UBT) { $UBT } else { 'NOT_FOUND' })"
if (-not $UBT) {
    $Failures.Add("UnrealBuildTool is missing")
}

$VsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$VisualStudioRoot = $null
if ([IO.File]::Exists($VsWhere)) {
    $VsWhereResult = @(& $VsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath) |
        Select-Object -First 1
    if (-not [string]::IsNullOrWhiteSpace($VsWhereResult)) {
        $VisualStudioRoot = ([string]$VsWhereResult).Trim()
    }
}
if ([string]::IsNullOrWhiteSpace($VisualStudioRoot) -or -not [IO.Directory]::Exists($VisualStudioRoot)) {
    Write-Output "VISUAL_STUDIO_CPP=NOT_FOUND"
    $Failures.Add("Visual Studio 2022 or Build Tools with MSVC x64 is missing")
}
else {
    Write-Output "VISUAL_STUDIO_CPP=$VisualStudioRoot"
}

$Compiler = $null
if ($VisualStudioRoot) {
    $Compiler = Get-ChildItem -LiteralPath (Join-Path $VisualStudioRoot "VC\Tools\MSVC") -Recurse -File -Filter "cl.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\bin\\Hostx64\\x64\\cl\.exe$' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
}
Write-Output "MSVC_COMPILER=$(if ($Compiler) { $Compiler.FullName } else { 'NOT_FOUND' })"
if (-not $Compiler) {
    $Failures.Add("MSVC Hostx64/x64 compiler is missing")
}

$KitsRoot = $null
$KitsRegistry = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots" -ErrorAction SilentlyContinue
if ($KitsRegistry -and $KitsRegistry.KitsRoot10) {
    $KitsRoot = [string]$KitsRegistry.KitsRoot10
}
if (-not $KitsRoot) {
    $DefaultKitsRoot = "${env:ProgramFiles(x86)}\Windows Kits\10"
    if ([IO.Directory]::Exists($DefaultKitsRoot)) {
        $KitsRoot = $DefaultKitsRoot
    }
}

$SdkCandidates = [System.Collections.Generic.List[object]]::new()
if ($KitsRoot -and [IO.Directory]::Exists((Join-Path $KitsRoot "Include"))) {
    foreach ($Directory in Get-ChildItem -LiteralPath (Join-Path $KitsRoot "Include") -Directory -ErrorAction SilentlyContinue) {
        $ParsedVersion = $null
        if ([Version]::TryParse($Directory.Name, [ref]$ParsedVersion)) {
            $WindowsHeader = Join-Path $Directory.FullName "um\Windows.h"
            $ResourceCompiler = Join-Path $KitsRoot "bin\$($Directory.Name)\x64\rc.exe"
            if ($ParsedVersion -ge $MinimumWindowsSdk -and [IO.File]::Exists($WindowsHeader) -and [IO.File]::Exists($ResourceCompiler)) {
                $SdkCandidates.Add([PSCustomObject]@{
                    Version = $ParsedVersion
                    Root = $KitsRoot
                    WindowsHeader = $WindowsHeader
                    ResourceCompiler = $ResourceCompiler
                })
            }
        }
    }
}
$SelectedSdk = $SdkCandidates | Sort-Object Version -Descending | Select-Object -First 1
if ($SelectedSdk) {
    Write-Output "WINDOWS_SDK_VERSION=$($SelectedSdk.Version)"
    Write-Output "WINDOWS_SDK_ROOT=$($SelectedSdk.Root)"
    Write-Output "WINDOWS_SDK_RC=$($SelectedSdk.ResourceCompiler)"
}
else {
    Write-Output "WINDOWS_SDK_VERSION=NOT_FOUND"
    Write-Output "WINDOWS_SDK_ROOT=$(if ($KitsRoot) { $KitsRoot } else { 'NOT_FOUND' })"
    $Failures.Add("Windows SDK $MinimumWindowsSdk or newer with Windows.h and x64 rc.exe is missing")
}

if ($Failures.Count -gt 0) {
    foreach ($Failure in $Failures) {
        Write-Output "BLOCKER=$Failure"
    }
    Write-Output "HOST_PREREQUISITE_RESULT=BLOCKED"
    exit 2
}

Write-Output "HOST_PREREQUISITE_RESULT=PASS"
exit 0
