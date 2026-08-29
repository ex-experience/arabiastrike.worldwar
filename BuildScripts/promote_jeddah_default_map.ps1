[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ValidationLog,
    [string]$ExpectedBranch = "codex/asww-development"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$EngineConfig = Join-Path $ProjectRoot "Config\DefaultEngine.ini"
$MapFile = Join-Path $ProjectRoot "Content\Maps\Jeddah_RedSea_Assault.umap"
$MapPackage = "/Game/Maps/Jeddah_RedSea_Assault"

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
    throw "Map promotion requires '$ExpectedBranch'; current branch is '$CurrentBranch'."
}
if (-not (Test-UnrealPackageFile $MapFile)) {
    throw "Refusing to promote a missing or non-Unreal Jeddah map package."
}
$ResolvedValidationLog = (Resolve-Path -LiteralPath $ValidationLog).Path
$LogText = Get-Content -Raw -LiteralPath $ResolvedValidationLog
if ($LogText -notmatch "ASWW_MAP_LOAD_RESULT=PASS" -or $LogText -notmatch "ASWW_WORLD_PARTITION=PASS") {
    throw "Refusing to promote Jeddah without real Editor map-load and World Partition markers."
}
if (-not [IO.File]::Exists($EngineConfig)) {
    throw "DefaultEngine.ini was not found."
}

$ConfigText = Get-Content -Raw -LiteralPath $EngineConfig
$AllowedGameDefaults = @("GameDefaultMap=/Engine/Maps/Entry", "GameDefaultMap=$MapPackage")
$AllowedServerDefaults = @("ServerDefaultMap=/Engine/Maps/Entry", "ServerDefaultMap=$MapPackage")
$CurrentGameDefault = [regex]::Match($ConfigText, '(?m)^GameDefaultMap=[^\r\n]*').Value
$CurrentServerDefault = [regex]::Match($ConfigText, '(?m)^ServerDefaultMap=[^\r\n]*').Value
if ($CurrentGameDefault -notin $AllowedGameDefaults -or $CurrentServerDefault -notin $AllowedServerDefaults) {
    throw "Unexpected map defaults; refusing an unsafe replacement. Game='$CurrentGameDefault'; Server='$CurrentServerDefault'."
}

$GameDefaultPattern = [regex]::new('(?m)^GameDefaultMap=[^\r\n]*')
$ServerDefaultPattern = [regex]::new('(?m)^ServerDefaultMap=[^\r\n]*')
$UpdatedConfig = $GameDefaultPattern.Replace($ConfigText, "GameDefaultMap=$MapPackage", 1)
$UpdatedConfig = $ServerDefaultPattern.Replace($UpdatedConfig, "ServerDefaultMap=$MapPackage", 1)
if ($UpdatedConfig -ne $ConfigText) {
    [IO.File]::WriteAllText($EngineConfig, $UpdatedConfig, [Text.UTF8Encoding]::new($false))
}

Write-Output "BRANCH=$CurrentBranch"
Write-Output "VALIDATION_LOG=$ResolvedValidationLog"
Write-Output "GAME_DEFAULT_MAP=$MapPackage"
Write-Output "SERVER_DEFAULT_MAP=$MapPackage"
Write-Output "MAP_PROMOTION_RESULT=PASS_AFTER_REAL_EDITOR_VALIDATION"
exit 0
