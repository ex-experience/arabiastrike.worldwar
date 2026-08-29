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

$Promote = Join-Path $ProjectRoot "BuildScripts\promote_jeddah_default_map.ps1"
if (-not (Test-Path -LiteralPath $Promote -PathType Leaf)) {
    throw "PROMOTE_SCRIPT_NOT_FOUND"
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ProjectRoot "Saved\Verification\FixBackups\PromoteCRLF_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Promote -Destination (Join-Path $BackupDir "promote_jeddah_default_map.ps1") -Force

$Text = [IO.File]::ReadAllText($Promote)

$OldGame   = '(?m)^GameDefaultMap=.*$'
$OldServer = '(?m)^ServerDefaultMap=.*$'
$NewGame   = '(?m)^GameDefaultMap=[^\r\n]*'
$NewServer = '(?m)^ServerDefaultMap=[^\r\n]*'

$Before = $Text

$Text = $Text.Replace($OldGame, $NewGame)
$Text = $Text.Replace($OldServer, $NewServer)

if ($Text -eq $Before) {
    # Already patched is acceptable only if both corrected patterns are present.
    if (-not $Text.Contains($NewGame) -or -not $Text.Contains($NewServer)) {
        throw "PROMOTE_PATTERN_PATCH_NOT_APPLIED"
    }
    Write-Host "PROMOTE_CRLF_FIX=ALREADY_PRESENT" -ForegroundColor Yellow
}
else {
    [IO.File]::WriteAllText($Promote, $Text, [Text.UTF8Encoding]::new($false))
    Write-Host "PROMOTE_CRLF_FIX=APPLIED" -ForegroundColor Green
}

Write-Host "BACKUP=$BackupDir" -ForegroundColor Green

Write-Host ""
Write-Host "=== VERIFY PATCH ===" -ForegroundColor Cyan
Select-String -LiteralPath $Promote -Pattern "GameDefaultMap=\[\^\\r\\n\]\*|ServerDefaultMap=\[\^\\r\\n\]\*" |
    Select-Object LineNumber,Line

git -c core.safecrlf=false diff --check
if ($LASTEXITCODE -ne 0) {
    throw "GIT_DIFF_CHECK_FAILED_AFTER_PROMOTE_PATCH"
}

Write-Host ""
Write-Host "PROMOTE_PATCH_VALIDATION=PASS" -ForegroundColor Green
Write-Host "NEXT_COMMAND=powershell -ExecutionPolicy Bypass -File .\ASWW_FIX_VALIDATOR_LOGGING_AND_CONTINUE.ps1 -ContinueThroughPackage" -ForegroundColor Cyan
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
