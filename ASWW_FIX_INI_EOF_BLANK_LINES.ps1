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

$Targets = @(
    (Join-Path $ProjectRoot "Config\DefaultEngine.ini"),
    (Join-Path $ProjectRoot "Config\DefaultInput.ini")
)

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ProjectRoot "Saved\Verification\FixBackups\IniEOF_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

foreach ($File in $Targets) {
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        throw "MISSING_FILE=$File"
    }

    Copy-Item -LiteralPath $File -Destination (Join-Path $BackupDir (Split-Path $File -Leaf)) -Force

    $Bytes = [IO.File]::ReadAllBytes($File)

    # Detect UTF-8 BOM and preserve it.
    $HasUtf8Bom = $Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF
    $Offset = if ($HasUtf8Bom) { 3 } else { 0 }

    # Treat INI files as UTF-8 text and preserve BOM state.
    $Text = [Text.Encoding]::UTF8.GetString($Bytes, $Offset, $Bytes.Length - $Offset)

    # Preserve the file's dominant/current EOL convention.
    $Eol = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }

    # Remove only trailing CR/LF characters, then restore exactly one final EOL.
    $Normalized = $Text.TrimEnd("`r", "`n") + $Eol

    $Utf8 = [Text.UTF8Encoding]::new($HasUtf8Bom)
    [IO.File]::WriteAllText($File, $Normalized, $Utf8)

    Write-Host "EOF_FIXED=$(Split-Path $File -Leaf)" -ForegroundColor Green
}

Write-Host "BACKUP=$BackupDir" -ForegroundColor Green
Write-Host ""
Write-Host "=== GIT DIFF CHECK ===" -ForegroundColor Cyan

& git -c core.safecrlf=false --no-pager diff --check
$Exit = $LASTEXITCODE

Write-Host "DIFF_CHECK_EXIT=$Exit"
if ($Exit -ne 0) {
    Write-Host "INI_EOF_FIX=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=OTHER_DIFF_CHECK_ERROR_REMAINS" -ForegroundColor Red
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Exit
}

Write-Host "WHITESPACE_ERRORS=NONE" -ForegroundColor Green
Write-Host "INI_EOF_FIX=PASS" -ForegroundColor Green
Write-Host "NEXT_1=powershell -ExecutionPolicy Bypass -File .\ASWW_FIX_PROMOTE_CRLF.ps1" -ForegroundColor Cyan
Write-Host "NEXT_2=powershell -ExecutionPolicy Bypass -File .\ASWW_FIX_VALIDATOR_LOGGING_AND_CONTINUE.ps1 -ContinueThroughPackage" -ForegroundColor Cyan
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
