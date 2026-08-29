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

$LogRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\JeddahMap"
$Log = Get-ChildItem -LiteralPath $LogRoot -File -Filter "world_partition_convert_*.log" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $Log) {
    Write-Host "WP_CONVERT_LOG=NOT_FOUND" -ForegroundColor Red
    exit 2
}

Write-Host ""
Write-Host "WP_CONVERT_LOG=$($Log.FullName)" -ForegroundColor Cyan
Write-Host "LOG_SIZE_BYTES=$($Log.Length)"
Write-Host "LOG_TIME=$($Log.LastWriteTime.ToString('o'))"

Write-Host ""
Write-Host "=== WORLD PARTITION CONVERT ROOT CAUSE ===" -ForegroundColor Yellow

$Patterns = @(
    "LogWorldPartition",
    "WorldPartitionConvertCommandlet",
    "Error:",
    "Fatal error",
    "failed",
    "Failed",
    "Unable",
    "Cannot",
    "can't",
    "not found",
    "DoesPackageExist",
    "LongPackageName",
    "PackageName",
    "Map",
    "level"
)

$Matches = New-Object System.Collections.Generic.List[object]
foreach ($Pattern in $Patterns) {
    foreach ($M in (Select-String -LiteralPath $Log.FullName -SimpleMatch $Pattern -Context 4,12 -ErrorAction SilentlyContinue)) {
        $Matches.Add($M)
    }
}

if ($Matches.Count -gt 0) {
    $Matches |
        Sort-Object LineNumber -Unique |
        Select-Object -First 100
} else {
    Write-Host "NO_MATCHING_ROOT_CAUSE_LINES_FOUND" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== FIRST ERROR-LIKE LINES ===" -ForegroundColor Yellow

$Errors = Select-String -LiteralPath $Log.FullName `
    -Pattern "Error:|Fatal error|LogWorldPartition.*Error|failed|Failed|Unable|Cannot|not found|LongPackageName|PackageName" `
    -Context 5,15 `
    -ErrorAction SilentlyContinue

if ($Errors) {
    $Errors | Select-Object -First 60
} else {
    Write-Host "NO_ERROR_PATTERN_MATCHES" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== FIRST 180 LINES ===" -ForegroundColor Cyan
Get-Content -LiteralPath $Log.FullName -TotalCount 180

Write-Host ""
Write-Host "DIAGNOSTIC_COMPLETE=YES" -ForegroundColor Green
Write-Host "DO_NOT_RERUN_CONVERSION_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_DELETE_OR_REGENERATE_UMAP" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
