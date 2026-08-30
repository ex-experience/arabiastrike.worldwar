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

$TestScript = Join-Path $ProjectRoot "Content\Python\test_asww_jeddah_pie.py"
$PieRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\PIE"

if (-not (Test-Path -LiteralPath $TestScript -PathType Leaf)) {
    throw "TEST_SCRIPT_NOT_FOUND=$TestScript"
}

$LatestPie = Get-ChildItem -LiteralPath $PieRoot -File -Filter "pie_*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike "pie_wrapper_*" -and $_.Name -notlike "*.stderr.log" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

$LatestReport = Get-ChildItem -LiteralPath $PieRoot -Directory -Filter "Report_*" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TEST SCRIPT — REGISTRATION / GROUP DISCOVERY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEST_SCRIPT=$TestScript"

Select-String -LiteralPath $TestScript `
    -Pattern "ASWWPIE|Automation|automation|unreal\.|@|def |class |PIE|ASWW_PIE_SMOKE|log\(" `
    -Context 3,8 |
    Select-Object -First 220

Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host " LATEST PIE LOG — AUTOMATION DISCOVERY / EXECUTION" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow

if (-not $LatestPie) {
    Write-Host "LATEST_PIE_LOG=NONE" -ForegroundColor Red
} else {
    Write-Host "LATEST_PIE_LOG=$($LatestPie.FullName)" -ForegroundColor Cyan

    Select-String -LiteralPath $LatestPie.FullName `
        -Pattern "ASWWPIE|ASWW_PIE|Automation RunTest|Automation Test|RunTests|RunTest|Test Started|Test Completed|Test Passed|Test Failed|No tests|no tests|Found .* test|PythonAutomation|LogPython|ExecutePython|Queue Empty|ReportExport|Error:|Warning:" `
        -Context 4,12 |
        Select-Object -First 240
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " AUTOMATION REPORT FILES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (-not $LatestReport) {
    Write-Host "LATEST_REPORT_DIR=NONE" -ForegroundColor Yellow
} else {
    Write-Host "LATEST_REPORT_DIR=$($LatestReport.FullName)" -ForegroundColor Cyan
    $ReportFiles = Get-ChildItem -LiteralPath $LatestReport.FullName -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object FullName

    if (-not $ReportFiles) {
        Write-Host "REPORT_FILES=NONE" -ForegroundColor Yellow
    } else {
        $ReportFiles | Select-Object Length,FullName | Format-Table -AutoSize

        foreach ($F in $ReportFiles | Where-Object { $_.Extension -in @(".json",".txt",".log") } | Select-Object -First 10) {
            Write-Host ""
            Write-Host "----- REPORT FILE: $($F.FullName) -----" -ForegroundColor Green
            Get-Content -LiteralPath $F.FullName -TotalCount 220
        }
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " DIAGNOSIS COMPLETE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "SEND_BACK=TEST_SCRIPT_REGISTRATION_AND_LATEST_PIE_AUTOMATION_DISCOVERY" -ForegroundColor Yellow
Write-Host "DO_NOT_MODIFY_MAP_OR_RERUN_PROMOTION" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
