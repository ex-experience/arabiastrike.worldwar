[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "TEMP_QA_MARKER_AUDIT=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

Set-Location $ProjectRoot
$env:GIT_PAGER = "cat"

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

$CharacterCpp = Join-Path $ProjectRoot "Source\ArabiaStrikeWorldWar\Private\Player\ASCharacter.cpp"
if (-not (Test-Path -LiteralPath $CharacterCpp -PathType Leaf)) {
    Stop-Gate "ASCHARACTER_CPP_NOT_FOUND" 11
}

$Lines = Get-Content -LiteralPath $CharacterCpp
$Patterns = @(
    "ASWW_TELEMETRY",
    "ASWW_MOVE_STATE",
    "ASWW_VISUAL_PROOF",
    "ASWW_PlayerVisualProof",
    "ASWW_REAL_PLAYER_MANNY"
)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TEMP / REAL PLAYER MARKER COUNTS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

foreach ($Pattern in $Patterns) {
    $Matches = @(
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            if ($Lines[$i] -match [regex]::Escape($Pattern)) {
                [PSCustomObject]@{
                    Line = $i + 1
                    Text = $Lines[$i]
                }
            }
        }
    )

    Write-Host "$($Pattern)_COUNT=$($Matches.Count)"

    foreach ($M in $Matches) {
        Write-Host "$Pattern LINE=$($M.Line) TEXT=$($M.Text.Trim())"
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " MARKER CONTEXT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$HitLines = @()
for ($i = 0; $i -lt $Lines.Count; $i++) {
    foreach ($Pattern in $Patterns) {
        if ($Lines[$i] -match [regex]::Escape($Pattern)) {
            $HitLines += ($i + 1)
            break
        }
    }
}

$Ranges = @()
foreach ($LineNo in ($HitLines | Sort-Object -Unique)) {
    $Start = [Math]::Max(1, $LineNo - 8)
    $End = [Math]::Min($Lines.Count, $LineNo + 10)
    $Ranges += [PSCustomObject]@{ Start=$Start; End=$End }
}

# Merge overlapping ranges.
$Merged = @()
foreach ($R in ($Ranges | Sort-Object Start,End)) {
    if ($Merged.Count -eq 0) {
        $Merged += $R
        continue
    }

    $Last = $Merged[$Merged.Count - 1]
    if ($R.Start -le ($Last.End + 1)) {
        if ($R.End -gt $Last.End) {
            $Last.End = $R.End
        }
    } else {
        $Merged += $R
    }
}

foreach ($R in $Merged) {
    Write-Host ""
    Write-Host "----- LINES $($R.Start)-$($R.End) -----" -ForegroundColor Yellow
    for ($n = $R.Start; $n -le $R.End; $n++) {
        Write-Host ("{0,4}: {1}" -f $n, $Lines[$n - 1])
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " GIT SAFETY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"

Write-Host ""
Write-Host "=== STATUS SHORT ==="
& git status --short

Write-Host ""
Write-Host "TEMP_QA_MARKER_AUDIT=PASS" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "NEXT_GATE=REMOVE_ONLY_TEMP_TELEMETRY_MARKERS_KEEP_REAL_MANNY" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
