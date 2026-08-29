[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [switch]$ContinueThroughPackage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Banner([string]$Text) {
    Write-Host ""
    Write-Host ("=" * 76) -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ("=" * 76) -ForegroundColor Cyan
}

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "VALIDATOR_CONTINUE=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

Set-Location $ProjectRoot

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

$Project = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$Map = Join-Path $ProjectRoot "Content\Maps\Jeddah_RedSea_Assault.umap"
$ValidatorPy = Join-Path $ProjectRoot "Content\Python\asww_validate_jeddah_map.py"
$ValidatePS = Join-Path $ProjectRoot "BuildScripts\validate_jeddah_map.ps1"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$BuildVersion = Join-Path $UERoot "Engine\Build\Build.version"

foreach ($Required in @($Project,$Map,$ValidatorPy,$ValidatePS,$EditorCmd,$BuildVersion)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_$Required" 11
    }
}

$V = Get-Content -Raw -LiteralPath $BuildVersion | ConvertFrom-Json
$UEVersion = "$($V.MajorVersion).$($V.MinorVersion).$($V.PatchVersion)"
Write-Host "UE_VERSION=$UEVersion"
if ($V.MajorVersion -ne 5 -or $V.MinorVersion -ne 8) {
    Stop-Gate "UE_5_8_REQUIRED_FOUND_$UEVersion" 12
}

$RunningEditors = @(Get-Process UnrealEditor,UnrealEditor-Cmd -ErrorAction SilentlyContinue)
if ($RunningEditors.Count -gt 0) {
    $RunningEditors | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ALL_UNREAL_EDITOR_PROCESSES_FIRST" 13
}

# Confirm the map is still a real Unreal package.
$Stream = [IO.File]::OpenRead($Map)
try {
    $Reader = [IO.BinaryReader]::new($Stream)
    try { $Magic = $Reader.ReadUInt32() }
    finally { $Reader.Dispose() }
}
finally { $Stream.Dispose() }

$Expected = [Convert]::ToUInt32("9E2A83C1", 16)
Write-Host ("MAP_MAGIC=0x{0:X8}" -f $Magic)
if ($Magic -ne $Expected) {
    Stop-Gate "INVALID_UNREAL_PACKAGE_HEADER" 14
}
Write-Host "REAL_UNREAL_PACKAGE_HEADER=True" -ForegroundColor Green

Banner "VERIFY DESCRIPTOR PASS EVIDENCE"

$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\JeddahMap"
$DescLog = Get-ChildItem -LiteralPath $EvidenceRoot -File -Filter "validate_jeddah_actor_descriptors_*.log" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $DescLog) {
    Stop-Gate "DESCRIPTOR_LOG_NOT_FOUND" 20
}

$DescText = Get-Content -Raw -LiteralPath $DescLog.FullName
if ($DescText -notmatch "ASWW_DESCRIPTOR_VALIDATION=PASS" -or
    $DescText -notmatch "ASWW_MISSING_DESCRIPTOR_ACTORS=NONE") {
    Stop-Gate "DESCRIPTOR_PASS_EVIDENCE_MISSING" 21
}

Write-Host "DESCRIPTOR_LOG=$($DescLog.FullName)"
Write-Host "JEDDAH_DESCRIPTOR_VALIDATION=PASS" -ForegroundColor Green

Banner "PATCH VALIDATE_JEDDAH_MAP.PS1 LOGGING"

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ProjectRoot "Saved\Verification\FixBackups\ValidatorLogging_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $ValidatePS -Destination (Join-Path $BackupDir "validate_jeddah_map.ps1") -Force
Write-Host "VALIDATOR_WRAPPER_BACKUP=$BackupDir" -ForegroundColor Green

$Wrapper = @'
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
        finally { $Reader.Dispose() }
    }
    finally { $Stream.Dispose() }
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

# IMPORTANT:
# - Use forward-slash paths for Unreal's ExecutePythonScript argument.
# - Capture Unreal stdout directly with Tee-Object instead of relying on -Log=<absolute path>.
$ProjectFileForUE = $ProjectFile.Replace('\','/')
$ValidationScriptForUE = $ValidationScript.Replace('\','/')

$Arguments = @(
    $ProjectFileForUE,
    "-ExecutePythonScript=$ValidationScriptForUE",
    "-Unattended",
    "-NoSplash",
    "-NoSound",
    "-NullRHI",
    "-NoSourceControl",
    "-stdout",
    "-FullStdOutLogOutput"
)

Write-Output "BRANCH=$CurrentBranch"
Write-Output "UE_VERSION=$DetectedVersion"
Write-Output "UE_ROOT=$UERoot"
Write-Output "JEDDAH_UMAP=$MapFile"
Write-Output "COMMAND=`"$UnrealEditorCmd`" $($Arguments -join ' ')"
Write-Output "MAP_VALIDATION_LOG=$LogPath"

& $UnrealEditorCmd @Arguments 2>&1 | Tee-Object -FilePath $LogPath
$EditorExitCode = $LASTEXITCODE

Write-Output "EDITOR_EXIT_CODE=$EditorExitCode"
if ($EditorExitCode -ne 0) {
    Write-Output "MAP_LOAD_RESULT=FAIL_EDITOR_EXIT_$EditorExitCode"
    exit $EditorExitCode
}

$LogText = if ([IO.File]::Exists($LogPath)) { Get-Content -Raw -LiteralPath $LogPath } else { "" }

if ($LogText -notmatch "ASWW_MAP_LOAD_RESULT=PASS" -or
    $LogText -notmatch "ASWW_WORLD_PARTITION=PASS" -or
    $LogText -notmatch "ASWW_DESCRIPTOR_VALIDATION=PASS") {
    Write-Output "MAP_LOAD_RESULT=FAIL_MISSING_EDITOR_SUCCESS_MARKERS"
    Write-Output "MARKER_MAP_LOAD=$($LogText -match 'ASWW_MAP_LOAD_RESULT=PASS')"
    Write-Output "MARKER_WORLD_PARTITION=$($LogText -match 'ASWW_WORLD_PARTITION=PASS')"
    Write-Output "MARKER_DESCRIPTOR=$($LogText -match 'ASWW_DESCRIPTOR_VALIDATION=PASS')"
    exit 3
}

Write-Output "MAP_LOAD_RESULT=PASS_REAL_EDITOR_LOAD"
Write-Output "WORLD_PARTITION_RESULT=PASS_EDITOR_API"
Write-Output "DESCRIPTOR_RESULT=PASS_WORLD_PARTITION_ACTOR_DESCRIPTORS"
exit 0
'@

[IO.File]::WriteAllText($ValidatePS, $Wrapper, [Text.UTF8Encoding]::new($false))
Write-Host "VALIDATOR_LOGGING_PATCH=APPLIED" -ForegroundColor Green

Banner "RUN PERMANENT VALIDATOR WITH DIRECT STDOUT CAPTURE"

$Capture = Join-Path $ProjectRoot "Saved\Verification\Local\validator_wrapper_capture_$Stamp.txt"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Capture) | Out-Null

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ValidatePS -UERoot $UERoot 2>&1 |
    Tee-Object -FilePath $Capture

$ValidateExit = $LASTEXITCODE
Write-Host ""
Write-Host "PERMANENT_VALIDATOR_EXIT=$ValidateExit"

$ValidationLine = Get-Content -LiteralPath $Capture |
    Where-Object { $_ -like "MAP_VALIDATION_LOG=*" } |
    Select-Object -Last 1

if ($ValidationLine) {
    $ValidationLog = $ValidationLine.Substring("MAP_VALIDATION_LOG=".Length)
    Write-Host "MAP_VALIDATION_LOG=$ValidationLog" -ForegroundColor Cyan
}
else {
    $ValidationLog = $null
}

if ($ValidateExit -ne 0) {
    if ($ValidationLog -and (Test-Path -LiteralPath $ValidationLog)) {
        Write-Host ""
        Write-Host "=== PERMANENT VALIDATOR ROOT CAUSE ===" -ForegroundColor Yellow
        Select-String -LiteralPath $ValidationLog `
            -Pattern "ASWW_|LogPython:\s*Error|Traceback|RuntimeError:|AttributeError:|TypeError:|PlayerStart|ASGameMode|World Partition|failed to load" `
            -Context 4,14 |
            Select-Object -First 100
    }
    Stop-Gate "PERMANENT_VALIDATOR_FAIL_EXIT_$ValidateExit" $ValidateExit
}

if (-not $ValidationLog -or -not (Test-Path -LiteralPath $ValidationLog)) {
    Stop-Gate "VALIDATION_LOG_NOT_CREATED_AFTER_LOGGING_PATCH" 31
}

Write-Host "PERMANENT_JEDDAH_VALIDATION=PASS" -ForegroundColor Green

if (-not $ContinueThroughPackage) {
    Write-Host ""
    Write-Host "NEXT_GATE=PROMOTE_DEFAULT_MAP" -ForegroundColor Green
    Write-Host "RERUN_THIS_SCRIPT_WITH_-ContinueThroughPackage_TO_CONTINUE" -ForegroundColor Yellow
    Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
    exit 0
}

Banner "PROMOTE JEDDAH DEFAULT MAP"

$Promote = Join-Path $ProjectRoot "BuildScripts\promote_jeddah_default_map.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Promote -ValidationLog $ValidationLog
$PromoteExit = $LASTEXITCODE
if ($PromoteExit -ne 0) {
    Stop-Gate "MAP_PROMOTION_FAIL_EXIT_$PromoteExit" $PromoteExit
}
Write-Host "MAP_PROMOTION=PASS" -ForegroundColor Green

Banner "PIE STARTUP SMOKE"

$Pie = Join-Path $ProjectRoot "BuildScripts\run_jeddah_pie_smoke.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Pie -UERoot $UERoot -TimeoutSeconds 600
$PieExit = $LASTEXITCODE
if ($PieExit -ne 0) {
    Stop-Gate "PIE_STARTUP_SMOKE_FAIL_EXIT_$PieExit" $PieExit
}
Write-Host "PIE_STARTUP_SMOKE=PASS_STARTUP_ONLY" -ForegroundColor Green

Banner "PACKAGE WIN64 DEVELOPMENT"

$Package = Join-Path $ProjectRoot "BuildScripts\build_win64.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Package -UERoot $UERoot -Configuration Development
$PackageExit = $LASTEXITCODE
if ($PackageExit -ne 0) {
    Stop-Gate "WIN64_PACKAGE_FAIL_EXIT_$PackageExit" $PackageExit
}

Write-Host ""
Write-Host "POST_DESCRIPTOR_PIPELINE=PASS_THROUGH_PACKAGE" -ForegroundColor Green
Write-Host "PERMANENT_JEDDAH_VALIDATION=PASS" -ForegroundColor Green
Write-Host "MAP_PROMOTION=PASS" -ForegroundColor Green
Write-Host "PIE_STARTUP_SMOKE=PASS_STARTUP_ONLY" -ForegroundColor Green
Write-Host "WIN64_PACKAGE=PASS" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
