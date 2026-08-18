[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$UERoot,
    [string]$ExpectedBranch = "codex/asww-development"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$ValidationScript = Join-Path $ProjectRoot "Content\Python\asww_validate_jeddah_map.py"
$MapFile = Join-Path $ProjectRoot "Content\Maps\Jeddah_RedSea_Assault.umap"
$LogRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\JeddahMap"
$UnrealEditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$BuildVersionPath = Join-Path $UERoot "Engine\Build\Build.version"

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
    throw "Jeddah validation requires '$ExpectedBranch'; current branch is '$CurrentBranch'."
}
if (-not [IO.File]::Exists($ProjectFile) -or -not [IO.File]::Exists($ValidationScript)) {
    throw "Project descriptor or Jeddah validation script is missing."
}
if (-not [IO.File]::Exists($BuildVersionPath) -or -not [IO.File]::Exists($UnrealEditorCmd)) {
    throw "A complete UE 5.8 installation with UnrealEditor-Cmd.exe is required under '$UERoot'."
}
if (-not (Test-UnrealPackageFile $MapFile)) {
    Write-Output "JEDDAH_UMAP=NOT_FOUND_OR_NOT_REAL_UNREAL_PACKAGE"
    Write-Output "MAP_LOAD_RESULT=BLOCKED"
    exit 2
}

$BuildVersion = Get-Content -Raw -LiteralPath $BuildVersionPath | ConvertFrom-Json
$DetectedVersion = "$($BuildVersion.MajorVersion).$($BuildVersion.MinorVersion).$($BuildVersion.PatchVersion)"
if ($BuildVersion.MajorVersion -ne 5 -or $BuildVersion.MinorVersion -ne 8) {
    throw "UE 5.8 is required; detected '$DetectedVersion'."
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$LogPath = Join-Path $LogRoot "validate_$RunId.log"
$Arguments = @(
    $ProjectFile,
    "-ExecutePythonScript=$ValidationScript",
    "-Unattended",
    "-NoSplash",
    "-NoSound",
    "-NullRHI",
    "-NoSourceControl",
    "-Log=$LogPath"
)
Write-Output "BRANCH=$CurrentBranch"
Write-Output "UE_VERSION=$DetectedVersion"
Write-Output "UE_ROOT=$UERoot"
Write-Output "JEDDAH_UMAP=$MapFile"
Write-Output "COMMAND=`"$UnrealEditorCmd`" $($Arguments -join ' ')"
Write-Output "MAP_VALIDATION_LOG=$LogPath"
& $UnrealEditorCmd @Arguments
$EditorExitCode = $LASTEXITCODE
if ($EditorExitCode -ne 0) {
    Write-Output "MAP_LOAD_RESULT=FAIL_EDITOR_EXIT_$EditorExitCode"
    exit $EditorExitCode
}

$LogText = if ([IO.File]::Exists($LogPath)) { Get-Content -Raw -LiteralPath $LogPath } else { "" }
if ($LogText -notmatch "ASWW_MAP_LOAD_RESULT=PASS" -or $LogText -notmatch "ASWW_WORLD_PARTITION=PASS") {
    Write-Output "MAP_LOAD_RESULT=FAIL_MISSING_EDITOR_SUCCESS_MARKERS"
    exit 3
}

Write-Output "MAP_LOAD_RESULT=PASS_REAL_EDITOR_LOAD"
Write-Output "WORLD_PARTITION_RESULT=PASS_EDITOR_API"
exit 0
