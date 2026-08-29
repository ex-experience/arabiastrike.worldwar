[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "JEDDAH_WP_REPAIR=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_DELETE_OR_REGENERATE_UMAP" -ForegroundColor Yellow
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
$ValidatePy = Join-Path $ProjectRoot "Content\Python\asww_validate_jeddah_map.py"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$BuildVersion = Join-Path $UERoot "Engine\Build\Build.version"

foreach ($Required in @($Project, $Map, $ValidatePy, $EditorCmd, $BuildVersion)) {
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

# Refuse to mutate the map while an Editor process is open.
$RunningEditors = @(Get-Process UnrealEditor,UnrealEditor-Cmd -ErrorAction SilentlyContinue)
if ($RunningEditors.Count -gt 0) {
    $RunningEditors | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize
    Stop-Gate "CLOSE_ALL_UNREAL_EDITOR_PROCESSES_FIRST" 13
}

# Verify the current file is still a real Unreal package.
$Stream = [IO.File]::OpenRead($Map)
try {
    $Reader = [IO.BinaryReader]::new($Stream)
    try { $Magic = $Reader.ReadUInt32() }
    finally { $Reader.Dispose() }
}
finally { $Stream.Dispose() }

$ExpectedMagic = [Convert]::ToUInt32("9E2A83C1", 16)
Write-Host ("MAP_MAGIC=0x{0:X8}" -f $Magic)
if ($Magic -ne $ExpectedMagic) {
    Stop-Gate "CURRENT_JEDDAH_MAP_IS_NOT_A_REAL_UNREAL_PACKAGE" 14
}
Write-Host "REAL_UNREAL_PACKAGE_HEADER=True" -ForegroundColor Green

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\FixBackups\Jeddah_PreWorldPartition_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

Copy-Item -LiteralPath $Map -Destination (Join-Path $BackupRoot "Jeddah_RedSea_Assault.umap") -Force

# Preserve any related external actor/object data if it unexpectedly already exists.
$PotentialExternalPaths = @(
    (Join-Path $ProjectRoot "Content\__ExternalActors__\Maps\Jeddah_RedSea_Assault"),
    (Join-Path $ProjectRoot "Content\__ExternalObjects__\Maps\Jeddah_RedSea_Assault")
)
foreach ($Path in $PotentialExternalPaths) {
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $Name = Split-Path $Path -Leaf
        $ParentName = Split-Path (Split-Path $Path -Parent) -Leaf
        $Dest = Join-Path $BackupRoot "$ParentName\$Name"
        New-Item -ItemType Directory -Force -Path (Split-Path $Dest -Parent) | Out-Null
        Copy-Item -LiteralPath $Path -Destination $Dest -Recurse -Force
    }
}

git -c core.safecrlf=false --no-pager diff --binary -- "Content/Maps/Jeddah_RedSea_Assault.umap" |
    Set-Content -LiteralPath (Join-Path $BackupRoot "map_git_diff_before_conversion.patch") -Encoding UTF8

Write-Host "BACKUP=$BackupRoot" -ForegroundColor Green

$EvidenceRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\JeddahMap"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

$ConvertLog = Join-Path $EvidenceRoot "world_partition_convert_$Stamp.log"

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host " WORLD PARTITION CONVERSION — OFFICIAL UE COMMANDLET / IN-PLACE" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

$ConvertArgs = @(
    $Project,
    "-run=WorldPartitionConvertCommandlet",
    $Map,
    "-SCCProvider=None",
    "-AllowCommandletRendering",
    "-Verbose",
    "-Unattended",
    "-NoSplash",
    "-NoSound",
    "-stdout",
    "-FullStdOutLogOutput"
)

Write-Host "CONVERT_COMMAND=`"$EditorCmd`" $($ConvertArgs -join ' ')" -ForegroundColor DarkGray

& $EditorCmd @ConvertArgs 2>&1 | Tee-Object -FilePath $ConvertLog
$ConvertExit = $LASTEXITCODE

Write-Host ""
Write-Host "WORLD_PARTITION_CONVERT_EXIT=$ConvertExit"
Write-Host "WORLD_PARTITION_CONVERT_LOG=$ConvertLog"

if ($ConvertExit -ne 0) {
    Write-Host ""
    Write-Host "=== CONVERSION ERRORS ===" -ForegroundColor Yellow
    Select-String -LiteralPath $ConvertLog `
        -Pattern "Error:|Fatal error|LogWorldPartition.*Error|failed|exception" `
        -Context 4,12 |
        Select-Object -First 50
    Stop-Gate "WORLD_PARTITION_CONVERT_FAIL_EXIT_$ConvertExit" $ConvertExit
}

if (-not (Test-Path -LiteralPath $Map -PathType Leaf)) {
    Stop-Gate "MAP_MISSING_AFTER_CONVERSION" 20
}

Write-Host "WORLD_PARTITION_CONVERT_COMMANDLET=EXIT_0" -ForegroundColor Green

# Real Editor validation of the converted asset.
$ValidateLog = Join-Path $EvidenceRoot "validate_after_wp_convert_$Stamp.log"

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host " REAL JEDDAH VALIDATION AFTER WORLD PARTITION CONVERSION" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

$ValidateArgs = @(
    $Project,
    "-ExecutePythonScript=$ValidatePy",
    "-Unattended",
    "-NoSplash",
    "-NoSound",
    "-NullRHI",
    "-NoSourceControl",
    "-stdout",
    "-FullStdOutLogOutput"
)

& $EditorCmd @ValidateArgs 2>&1 | Tee-Object -FilePath $ValidateLog
$ValidateExit = $LASTEXITCODE

$MapPass = Select-String -LiteralPath $ValidateLog -SimpleMatch "ASWW_MAP_LOAD_RESULT=PASS" -Quiet
$WorldPass = Select-String -LiteralPath $ValidateLog -SimpleMatch "ASWW_WORLD_PARTITION=PASS" -Quiet

Write-Host ""
Write-Host "VALIDATION_EXIT=$ValidateExit"
Write-Host "MAP_LOAD_MARKER=$MapPass"
Write-Host "WORLD_PARTITION_MARKER=$WorldPass"
Write-Host "VALIDATION_LOG=$ValidateLog"

if ($ValidateExit -eq 0 -and $MapPass -and $WorldPass) {
    Write-Host ""
    Write-Host "JEDDAH_WORLD_PARTITION=PASS" -ForegroundColor Green
    Write-Host "JEDDAH_VALIDATION=PASS" -ForegroundColor Green
    Write-Host "NEXT_GATE=PROMOTE_DEFAULT_MAP_THEN_PIE" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "=== VALIDATION ROOT CAUSE ===" -ForegroundColor Yellow
Select-String -LiteralPath $ValidateLog `
    -Pattern "LogPython:\s*Error|Traceback|RuntimeError:|AttributeError:|TypeError:|Jeddah actors missing|World Partition|PlayerStart|ASGameMode|failed to load" `
    -Context 4,12 |
    Select-Object -First 60

Stop-Gate "POST_CONVERSION_VALIDATION_FAILED" 30
