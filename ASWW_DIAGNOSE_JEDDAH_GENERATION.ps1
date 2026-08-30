[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location $ProjectRoot

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    throw "WRONG_BRANCH_STOP"
}

$Map = Join-Path $ProjectRoot "Content\Maps\Jeddah_RedSea_Assault.umap"
$LogRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\JeddahMap"

Write-Host ""
Write-Host "=== MAP FILE STATUS ===" -ForegroundColor Cyan

if (Test-Path -LiteralPath $Map -PathType Leaf) {
    $Info = Get-Item -LiteralPath $Map
    Write-Host "JEDDAH_UMAP=FOUND" -ForegroundColor Green
    Write-Host "MAP_PATH=$($Info.FullName)"
    Write-Host "MAP_SIZE_BYTES=$($Info.Length)"
    Write-Host "MAP_LAST_WRITE=$($Info.LastWriteTime.ToString('o'))"

    $IsUnreal = $false
    if ($Info.Length -ge 4) {
        $Stream = [IO.File]::OpenRead($Map)
        try {
            $Reader = [IO.BinaryReader]::new($Stream)
            try {
                $Magic = $Reader.ReadUInt32()
                $Expected = [Convert]::ToUInt32("9E2A83C1",16)
                $IsUnreal = ($Magic -eq $Expected)
                Write-Host ("MAP_MAGIC=0x{0:X8}" -f $Magic)
                Write-Host ("EXPECTED_MAGIC=0x{0:X8}" -f $Expected)
            }
            finally { $Reader.Dispose() }
        }
        finally { $Stream.Dispose() }
    }
    Write-Host "REAL_UNREAL_PACKAGE_HEADER=$IsUnreal" -ForegroundColor $(if($IsUnreal){"Green"}else{"Red"})
}
else {
    Write-Host "JEDDAH_UMAP=NOT_FOUND" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== LATEST GENERATION LOG ===" -ForegroundColor Cyan

$Log = Get-ChildItem -LiteralPath $LogRoot -File -Filter "generate_*.log" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $Log) {
    Write-Host "GENERATION_LOG=NOT_FOUND" -ForegroundColor Red
    exit 2
}

Write-Host "GENERATION_LOG=$($Log.FullName)"
Write-Host "GENERATION_LOG_SIZE=$($Log.Length)"
Write-Host "GENERATION_LOG_TIME=$($Log.LastWriteTime.ToString('o'))"

Write-Host ""
Write-Host "=== EXPECTED SUCCESS MARKERS ===" -ForegroundColor Cyan
$Markers = @(
    "ASWW_MAP_ASSET=",
    "ASWW_WORLD_PARTITION=VERIFIED_BY_EDITOR_API",
    "ASWW_MAP_GENERATION_RESULT=PASS"
)

foreach ($Marker in $Markers) {
    $Found = Select-String -LiteralPath $Log.FullName -SimpleMatch $Marker -Quiet
    Write-Host "$Marker => $Found"
}

Write-Host ""
Write-Host "=== PYTHON / UNREAL ERRORS ===" -ForegroundColor Yellow

$Patterns = @(
    "Traceback",
    "Python Error",
    "LogPython: Error",
    "LogPython: Exception",
    "RuntimeError:",
    "AttributeError:",
    "TypeError:",
    "Exception:",
    "Error:",
    "Fatal error",
    "ensure condition failed",
    "Failed to create partitioned Jeddah level",
    "World Partition",
    "Project class failed to load",
    "Failed to spawn actor",
    "Failed to save Jeddah level"
)

$Matches = foreach ($Pattern in $Patterns) {
    Select-String -LiteralPath $Log.FullName -SimpleMatch $Pattern -Context 3,8 -ErrorAction SilentlyContinue
}

if ($Matches) {
    $Matches | Select-Object -First 50
}
else {
    Write-Host "NO_MATCHING_ERROR_LINES_FOUND" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== LAST 160 LINES ===" -ForegroundColor Cyan
Get-Content -LiteralPath $Log.FullName -Tail 160

Write-Host ""
Write-Host "DIAGNOSTIC_COMPLETE=YES" -ForegroundColor Green
Write-Host "DO_NOT_DELETE_THE_UMAP_OR_LOG" -ForegroundColor Yellow
Write-Host "DO_NOT_RERUN_MAP_GENERATION_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
