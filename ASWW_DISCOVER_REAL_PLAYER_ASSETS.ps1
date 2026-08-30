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
    Write-Host "REAL_PLAYER_ASSET_DISCOVERY=STOPPED" -ForegroundColor Red
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

if (-not (Test-Path -LiteralPath $UERoot -PathType Container)) {
    Stop-Gate "UE_ROOT_NOT_FOUND_$UERoot" 11
}

$Keywords = '(?i)(manny|quinn|mannequin|soldier|military|operator|trooper|character|human|hero|metahuman|skm_|sk_|abp_|anim_)'
$Files = New-Object System.Collections.Generic.List[System.IO.FileInfo]

function Add-CandidatesFromRoot {
    param([string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return
    }

    Write-Host "SCANNING=$Root"
    Get-ChildItem -LiteralPath $Root -File -Recurse -Filter "*.uasset" -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match $Keywords } |
        ForEach-Object { $Files.Add($_) }
}

# Project assets first.
Add-CandidatesFromRoot (Join-Path $ProjectRoot "Content")

# Common UE locations that can contain mannequin/template assets.
$UERoots = @(
    (Join-Path $UERoot "Templates"),
    (Join-Path $UERoot "FeaturePacks"),
    (Join-Path $UERoot "Engine\Content"),
    (Join-Path $UERoot "Engine\Plugins\Animation"),
    (Join-Path $UERoot "Engine\Plugins\Runtime"),
    (Join-Path $UERoot "Engine\Plugins\Experimental"),
    (Join-Path $UERoot "Engine\Plugins\Marketplace")
)

foreach ($R in $UERoots) {
    Add-CandidatesFromRoot $R
}

$Unique = @($Files | Sort-Object FullName -Unique)

function Get-MountPath {
    param([System.IO.FileInfo]$File)

    $Full = $File.FullName

    $ProjectContent = Join-Path $ProjectRoot "Content"
    if ($Full.StartsWith($ProjectContent, [System.StringComparison]::OrdinalIgnoreCase)) {
        $Rel = $Full.Substring($ProjectContent.Length).TrimStart('\')
        $RelNoExt = [IO.Path]::ChangeExtension($Rel, $null).TrimEnd('.')
        return "/Game/" + ($RelNoExt -replace '\\','/')
    }

    $EngineContent = Join-Path $UERoot "Engine\Content"
    if ($Full.StartsWith($EngineContent, [System.StringComparison]::OrdinalIgnoreCase)) {
        $Rel = $Full.Substring($EngineContent.Length).TrimStart('\')
        $RelNoExt = [IO.Path]::ChangeExtension($Rel, $null).TrimEnd('.')
        return "/Engine/" + ($RelNoExt -replace '\\','/')
    }

    # Try to find the plugin root and derive its mount point from the .uplugin filename.
    $Dir = $File.Directory
    while ($Dir -and $Dir.FullName.StartsWith($UERoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $Plugin = Get-ChildItem -LiteralPath $Dir.FullName -File -Filter "*.uplugin" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($Plugin) {
            $PluginName = [IO.Path]::GetFileNameWithoutExtension($Plugin.Name)
            $ContentDir = Join-Path $Dir.FullName "Content"
            if ($Full.StartsWith($ContentDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                $Rel = $Full.Substring($ContentDir.Length).TrimStart('\')
                $RelNoExt = [IO.Path]::ChangeExtension($Rel, $null).TrimEnd('.')
                return "/$PluginName/" + ($RelNoExt -replace '\\','/')
            }
            break
        }
        $Dir = $Dir.Parent
    }

    return ""
}

$Rows = foreach ($F in $Unique) {
    $Mount = Get-MountPath $F

    $Kind = if ($F.BaseName -match '(?i)^ABP_|AnimBP|AnimBlueprint') {
        "ANIM_BP_CANDIDATE"
    }
    elseif ($F.BaseName -match '(?i)^SKM_|^SK_|Manny|Quinn|Mannequin|Soldier|Military|Operator|Trooper|MetaHuman') {
        "CHARACTER_MESH_CANDIDATE"
    }
    else {
        "RELATED_ASSET"
    }

    [PSCustomObject]@{
        Kind = $Kind
        Name = $F.BaseName
        MountPath = $Mount
        File = $F.FullName
    }
}

$ProjectRows = @($Rows | Where-Object { $_.MountPath -like "/Game/*" })
$MannyRows   = @($Rows | Where-Object { $_.Name -match '(?i)manny' })
$QuinnRows   = @($Rows | Where-Object { $_.Name -match '(?i)quinn' })
$MilitaryRows= @($Rows | Where-Object { $_.Name -match '(?i)soldier|military|operator|trooper' })
$AnimRows    = @($Rows | Where-Object { $_.Kind -eq "ANIM_BP_CANDIDATE" })

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REAL PLAYER ASSET DISCOVERY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TOTAL_CANDIDATES=$($Rows.Count)"
Write-Host "PROJECT_CONTENT_CANDIDATES=$($ProjectRows.Count)"
Write-Host "MANNY_CANDIDATES=$($MannyRows.Count)"
Write-Host "QUINN_CANDIDATES=$($QuinnRows.Count)"
Write-Host "MILITARY_CANDIDATES=$($MilitaryRows.Count)"
Write-Host "ANIM_BP_CANDIDATES=$($AnimRows.Count)"

Write-Host ""
Write-Host "=== BEST CHARACTER / ANIMATION CANDIDATES ===" -ForegroundColor Yellow
$Best = @(
    $MilitaryRows
    $MannyRows
    $QuinnRows
    $ProjectRows
    $AnimRows
) | Sort-Object Kind,Name,MountPath -Unique | Select-Object -First 160

if ($Best.Count -eq 0) {
    Write-Host "BEST_CANDIDATES=NONE"
}
else {
    $Best | Format-Table Kind,Name,MountPath -AutoSize
}

$EvidenceDir = Join-Path $ProjectRoot "Saved\Verification"
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Csv = Join-Path $EvidenceDir "real_player_asset_candidates_$Stamp.csv"
$Rows | Export-Csv -LiteralPath $Csv -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "CANDIDATE_REPORT=$Csv"

if ($ProjectRows.Count -gt 0) {
    Write-Host "REAL_PLAYER_ASSET_DISCOVERY=PROJECT_CANDIDATES_FOUND" -ForegroundColor Green
    Write-Host "NEXT_GATE=VERIFY_ASSET_CLASS_SKELETON_AND_ANIMATION_COMPATIBILITY" -ForegroundColor Green
}
elseif (($MannyRows.Count + $QuinnRows.Count) -gt 0) {
    Write-Host "REAL_PLAYER_ASSET_DISCOVERY=UE_MANNEQUIN_CANDIDATES_FOUND" -ForegroundColor Green
    Write-Host "NEXT_GATE=VERIFY_MANNY_OR_QUINN_ASSET_PATHS_AND_COOKABILITY" -ForegroundColor Green
}
elseif ($MilitaryRows.Count -gt 0) {
    Write-Host "REAL_PLAYER_ASSET_DISCOVERY=UE_MILITARY_CANDIDATES_FOUND" -ForegroundColor Green
    Write-Host "NEXT_GATE=VERIFY_MILITARY_ASSET_CLASS_SKELETON_AND_COOKABILITY" -ForegroundColor Green
}
else {
    Write-Host "REAL_PLAYER_ASSET_DISCOVERY=NO_REAL_CHARACTER_ASSET_FOUND" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=IMPORT_OR_ADD_REAL_SKELETAL_CHARACTER_ASSET" -ForegroundColor Yellow
}

Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "KEEP_TEMP_VISUAL_PROOF_UNTIL_REAL_MESH_SELECTED" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_VISUAL_PROOF_OR_TELEMETRY" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
