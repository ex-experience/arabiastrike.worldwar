[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$BuildScriptsRoot = Join-Path $ProjectRoot "BuildScripts"
$Failures = [System.Collections.Generic.List[string]]::new()
$Scripts = @(Get-ChildItem -LiteralPath $BuildScriptsRoot -File -Filter "*.ps1" | Sort-Object Name)

if ($Scripts.Count -eq 0) {
    Write-Output "POWERSHELL_SANITY=FAIL"
    Write-Output "ERROR=No BuildScripts/*.ps1 files were found."
    exit 1
}

foreach ($Script in $Scripts) {
    $Tokens = $null
    $ParseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($Script.FullName, [ref]$Tokens, [ref]$ParseErrors)
    foreach ($ParseError in @($ParseErrors)) {
        $Failures.Add("$($Script.Name):$($ParseError.Extent.StartLineNumber): $($ParseError.Message)")
    }

    $Source = [IO.File]::ReadAllText($Script.FullName)
    if ($Source -notmatch '(?m)^Set-StrictMode\s+-Version\s+Latest\s*$') {
        $Failures.Add("$($Script.Name): missing Set-StrictMode -Version Latest")
    }
    if ($Source -notmatch '(?m)^\$ErrorActionPreference\s*=\s*["'']Stop["'']\s*$') {
        $Failures.Add("$($Script.Name): missing ErrorActionPreference=Stop")
    }
    Write-Output "POWERSHELL_SCRIPT=$($Script.Name);PARSE_ERRORS=$(@($ParseErrors).Count)"
}

if ($Failures.Count -gt 0) {
    $Failures | ForEach-Object { Write-Output "ERROR=$_" }
    Write-Output "POWERSHELL_SCRIPT_COUNT=$($Scripts.Count)"
    Write-Output "POWERSHELL_SANITY=FAIL"
    exit 1
}

Write-Output "POWERSHELL_SCRIPT_COUNT=$($Scripts.Count)"
Write-Output "POWERSHELL_SANITY=PASS"
exit 0
