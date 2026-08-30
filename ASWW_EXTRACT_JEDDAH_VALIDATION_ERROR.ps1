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
$Log = Get-ChildItem -LiteralPath $LogRoot -File -Filter "validate_console_*.log" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $Log) {
    Write-Host "VALIDATION_LOG=NOT_FOUND" -ForegroundColor Red
    exit 2
}

Write-Host ""
Write-Host "VALIDATION_LOG=$($Log.FullName)" -ForegroundColor Cyan
Write-Host "LOG_SIZE_BYTES=$($Log.Length)"
Write-Host "LOG_TIME=$($Log.LastWriteTime.ToString('o'))"

$MapMarker = Select-String -LiteralPath $Log.FullName -SimpleMatch "ASWW_MAP_LOAD_RESULT=PASS" -Quiet
$WorldMarker = Select-String -LiteralPath $Log.FullName -SimpleMatch "ASWW_WORLD_PARTITION=PASS" -Quiet

Write-Host ""
Write-Host "MAP_LOAD_MARKER=$MapMarker"
Write-Host "WORLD_PARTITION_MARKER=$WorldMarker"

Write-Host ""
Write-Host "=== PYTHON / JEDDAH / VALIDATION LINES ===" -ForegroundColor Yellow

$Patterns = @(
    "LogPython",
    "Traceback",
    "RuntimeError:",
    "AttributeError:",
    "TypeError:",
    "Exception:",
    "Jeddah",
    "ASWW_",
    "World Partition",
    "PlayerStart",
    "ASGameMode",
    "failed to load",
    "actors missing",
    "ExecutePythonScript"
)

$All = New-Object System.Collections.Generic.List[object]
foreach ($Pattern in $Patterns) {
    $Matches = Select-String -LiteralPath $Log.FullName -SimpleMatch $Pattern -Context 3,10 -ErrorAction SilentlyContinue
    foreach ($M in $Matches) {
        $All.Add($M)
    }
}

if ($All.Count -gt 0) {
    $All |
        Sort-Object LineNumber -Unique |
        Select-Object -First 100
}
else {
    Write-Host "NO_RELEVANT_LINES_FOUND" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== FIRST ERROR-LIKE LINES ===" -ForegroundColor Yellow

$Err = Select-String -LiteralPath $Log.FullName `
    -Pattern "LogPython:\s*Error|Traceback|RuntimeError:|AttributeError:|TypeError:|Fatal error|Error:|failed|missing" `
    -Context 4,12 `
    -ErrorAction SilentlyContinue

if ($Err) {
    $Err | Select-Object -First 50
}
else {
    Write-Host "NO_ERROR_PATTERN_MATCHES" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== LAST 220 LINES ===" -ForegroundColor Cyan
Get-Content -LiteralPath $Log.FullName -Tail 220

Write-Host ""
Write-Host "DIAGNOSTIC_COMPLETE=YES" -ForegroundColor Green
Write-Host "DO_NOT_PROMOTE_MAP_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_REGENERATE_OR_DELETE_UMAP_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
