[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$UERoot,
    [string]$ExpectedBranch = "codex/asww-development"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$GeneratorScript = Join-Path $ProjectRoot "Content\Python\asww_generate_jeddah_map.py"
$MapFile = Join-Path $ProjectRoot "Content\Maps\Jeddah_RedSea_Assault.umap"
$LogRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\JeddahMap"
$UnrealEditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$BuildVersionPath = Join-Path $UERoot "Engine\Build\Build.version"

function Find-FirstFile {
    param([string[]]$Candidates)
    foreach ($Candidate in $Candidates) {
        if ([IO.File]::Exists($Candidate)) {
            return $Candidate
        }
    }
    return $null
}

function Test-UnrealPackageFile {
    param([string]$Path)
    if (-not [IO.File]::Exists($Path) -or (Get-Item -LiteralPath $Path).Length -lt 32) {
        return $false
    }
    $Stream = [IO.File]::OpenRead($Path)
    try {
        $Reader = [IO.BinaryReader]::new($Stream)
        try {
            return $Reader.ReadUInt32() -eq [Convert]::ToUInt32("9E2A83C1", 16)
        }
        finally {
            $Reader.Dispose()
        }
    }
    finally {
        $Stream.Dispose()
    }
}

$CurrentBranch = (& git -C $ProjectRoot branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $CurrentBranch -ne $ExpectedBranch) {
    throw "Jeddah generation requires '$ExpectedBranch'; current branch is '$CurrentBranch'."
}
if (-not [IO.File]::Exists($ProjectFile) -or -not [IO.File]::Exists($GeneratorScript)) {
    throw "Project descriptor or Jeddah generator script is missing."
}
if (-not [IO.File]::Exists($BuildVersionPath) -or -not [IO.File]::Exists($UnrealEditorCmd)) {
    throw "A complete UE 5.8 installation with UnrealEditor-Cmd.exe is required under '$UERoot'."
}

$BuildVersion = Get-Content -Raw -LiteralPath $BuildVersionPath | ConvertFrom-Json
$DetectedVersion = "$($BuildVersion.MajorVersion).$($BuildVersion.MinorVersion).$($BuildVersion.PatchVersion)"
if ($BuildVersion.MajorVersion -ne 5 -or $BuildVersion.MinorVersion -ne 8) {
    throw "UE 5.8 is required; detected '$DetectedVersion'."
}

$PythonPlugin = Find-FirstFile @(
    (Join-Path $UERoot "Engine\Plugins\Experimental\PythonScriptPlugin\PythonScriptPlugin.uplugin"),
    (Join-Path $UERoot "Engine\Plugins\Scripting\PythonScriptPlugin\PythonScriptPlugin.uplugin")
)
$EditorScriptingPlugin = Find-FirstFile @(
    (Join-Path $UERoot "Engine\Plugins\Editor\EditorScriptingUtilities\EditorScriptingUtilities.uplugin"),
    (Join-Path $UERoot "Engine\Plugins\Experimental\EditorScriptingUtilities\EditorScriptingUtilities.uplugin")
)
if (-not $PythonPlugin -or -not $EditorScriptingPlugin) {
    throw "Required Unreal editor plugins are missing. PythonScriptPlugin='$PythonPlugin'; EditorScriptingUtilities='$EditorScriptingPlugin'."
}

Write-Output "BRANCH=$CurrentBranch"
Write-Output "UE_VERSION=$DetectedVersion"
Write-Output "UE_ROOT=$UERoot"
Write-Output "PYTHON_SCRIPT_PLUGIN=$PythonPlugin"
Write-Output "EDITOR_SCRIPTING_UTILITIES_PLUGIN=$EditorScriptingPlugin"

if ([IO.File]::Exists($MapFile)) {
    $ExistingState = if (Test-UnrealPackageFile $MapFile) { "REAL_PACKAGE_HEADER_UNVALIDATED" } else { "INVALID_NOT_UNREAL_PACKAGE" }
    Write-Output "JEDDAH_UMAP=$MapFile"
    Write-Output "JEDDAH_EXISTING_STATE=$ExistingState"
    Write-Output "MAP_GENERATION_RESULT=SKIPPED_REFUSING_TO_OVERWRITE"
    if ($ExistingState -eq "INVALID_NOT_UNREAL_PACKAGE") {
        exit 2
    }
    exit 0
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$LogPath = Join-Path $LogRoot "generate_$RunId.log"
$Arguments = @(
    $ProjectFile,
    "-ExecutePythonScript=$GeneratorScript",
    "-Unattended",
    "-NoSplash",
    "-NoSound",
    "-NullRHI",
    "-NoSourceControl",
    "-Log=$LogPath"
)
Write-Output "COMMAND=`"$UnrealEditorCmd`" $($Arguments -join ' ')"
Write-Output "GENERATION_LOG=$LogPath"
& $UnrealEditorCmd @Arguments
$EditorExitCode = $LASTEXITCODE
if ($EditorExitCode -ne 0) {
    Write-Output "MAP_GENERATION_RESULT=FAIL_EDITOR_EXIT_$EditorExitCode"
    exit $EditorExitCode
}
if (-not (Test-UnrealPackageFile $MapFile)) {
    Write-Output "MAP_GENERATION_RESULT=FAIL_NO_REAL_UMAP_PACKAGE"
    exit 3
}
$LogText = if ([IO.File]::Exists($LogPath)) { Get-Content -Raw -LiteralPath $LogPath } else { "" }
if ($LogText -notmatch "ASWW_MAP_GENERATION_RESULT=PASS" -or $LogText -notmatch "ASWW_WORLD_PARTITION=VERIFIED_BY_EDITOR_API") {
    Write-Output "MAP_GENERATION_RESULT=FAIL_MISSING_EDITOR_SUCCESS_MARKERS"
    exit 4
}

Write-Output "JEDDAH_UMAP=$MapFile"
Write-Output "MAP_GENERATION_RESULT=PASS_REAL_UNREAL_ASSET"
exit 0
