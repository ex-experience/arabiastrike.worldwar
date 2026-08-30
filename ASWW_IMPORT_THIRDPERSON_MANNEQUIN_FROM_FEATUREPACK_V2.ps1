[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$WorkRoot = "D:\ASWW_FEATUREPACK_IMPORT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "THIRDPERSON_MANNEQUIN_IMPORT=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
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

$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$UnrealPak = Join-Path $UERoot "Engine\Binaries\Win64\UnrealPak.exe"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"

if (-not (Test-Path -LiteralPath $ProjectFile -PathType Leaf)) {
    Stop-Gate "UPROJECT_NOT_FOUND" 11
}
if (-not (Test-Path -LiteralPath $UnrealPak -PathType Leaf)) {
    Stop-Gate "UNREALPAK_NOT_FOUND" 12
}
if (-not (Test-Path -LiteralPath $EditorCmd -PathType Leaf)) {
    Stop-Gate "UNREALEDITOR_CMD_NOT_FOUND" 13
}

$Packs = @(
    (Join-Path $UERoot "FeaturePacks\TP_ThirdPerson.upack")
    (Join-Path $UERoot "FeaturePacks\TP_ThirdPersonBP.upack")
)

foreach ($Pack in $Packs) {
    if (-not (Test-Path -LiteralPath $Pack -PathType Leaf)) {
        Stop-Gate "FEATUREPACK_NOT_FOUND_$Pack" 14
    }
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$SessionRoot = Join-Path $WorkRoot $Stamp
New-Item -ItemType Directory -Force -Path $SessionRoot | Out-Null

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " EXTRACT THIRD PERSON FEATURE PACKS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$PackInfo = @()

foreach ($Pack in $Packs) {
    $Name = [IO.Path]::GetFileNameWithoutExtension($Pack)
    $ExtractRoot = Join-Path $SessionRoot $Name
    New-Item -ItemType Directory -Force -Path $ExtractRoot | Out-Null

    Write-Host "EXTRACTING_PACK=$Pack"
    & $UnrealPak $Pack -Extract $ExtractRoot | Out-Host
    $Exit = $LASTEXITCODE
    Write-Host "UNREALPAK_EXIT_$Name=$Exit"

    if ($Exit -ne 0) {
        Stop-Gate "UNREALPAK_EXTRACT_FAILED_$Name" $Exit
    }

    $Assets = @(Get-ChildItem -LiteralPath $ExtractRoot -File -Recurse -Filter "*.uasset" -ErrorAction SilentlyContinue)
    $MannyMeshes = @($Assets | Where-Object { $_.Name -in @("SKM_Manny.uasset","SKM_Manny_Simple.uasset") })
    $MannyABPs = @($Assets | Where-Object { $_.Name -eq "ABP_Manny.uasset" })
    $MannequinAssets = @($Assets | Where-Object { $_.FullName -match '(?i)\\Mannequins\\' })

    $Score = 0
    if ($MannyMeshes.Count -gt 0) { $Score += 100 }
    if ($MannyABPs.Count -gt 0) { $Score += 100 }
    $Score += [Math]::Min(80, $MannequinAssets.Count)

    Write-Host "PACK=$Name"
    Write-Host "PACK_TOTAL_UASSET_COUNT=$($Assets.Count)"
    Write-Host "PACK_MANNEQUIN_UASSET_COUNT=$($MannequinAssets.Count)"
    Write-Host "PACK_MANNY_MESH_COUNT=$($MannyMeshes.Count)"
    Write-Host "PACK_ABP_MANNY_COUNT=$($MannyABPs.Count)"
    Write-Host "PACK_SCORE=$Score"

    $PackInfo += [PSCustomObject]@{
        Name = $Name
        PackPath = $Pack
        ExtractRoot = $ExtractRoot
        Assets = $Assets
        MannyMeshes = $MannyMeshes
        MannyABPs = $MannyABPs
        MannequinAssets = $MannequinAssets
        Score = $Score
    }
}

$Best = $PackInfo |
    Where-Object { $_.MannyMeshes.Count -gt 0 -and $_.MannyABPs.Count -gt 0 } |
    Sort-Object Score -Descending |
    Select-Object -First 1

if (-not $Best) {
    Write-Host ""
    Write-Host "=== PACK INVENTORY SAMPLE ===" -ForegroundColor Yellow
    foreach ($Info in $PackInfo) {
        Write-Host "PACK=$($Info.Name)"
        $Info.Assets |
            Where-Object { $_.Name -match '(?i)Manny|Quinn|Mannequin|ABP_' } |
            Select-Object -First 80 |
            ForEach-Object { Write-Host "ASSET=$($_.FullName)" }
    }
    Stop-Gate "NO_FEATUREPACK_CONTAINS_BOTH_MANNY_MESH_AND_ABP" 20
}

Write-Host ""
Write-Host "SELECTED_FEATUREPACK=$($Best.Name)" -ForegroundColor Green
Write-Host "SELECTED_PACK_SCORE=$($Best.Score)"

# Find the Mannequins directory that contains the selected Manny mesh.
$SelectedMesh = $Best.MannyMeshes | Select-Object -First 1
$Cursor = $SelectedMesh.Directory
$MannequinsDir = $null
while ($Cursor -and $Cursor.FullName.StartsWith($Best.ExtractRoot, [StringComparison]::OrdinalIgnoreCase)) {
    if ($Cursor.Name -eq "Mannequins") {
        $MannequinsDir = $Cursor
        break
    }
    $Cursor = $Cursor.Parent
}

if (-not $MannequinsDir) {
    Stop-Gate "CANNOT_LOCATE_MANNEQUINS_DIRECTORY_IN_SELECTED_PACK" 21
}

# Find nearest ancestor named Content so the original package-relative path can be preserved.
$Cursor = $MannequinsDir
$ContentRoot = $null
while ($Cursor -and $Cursor.FullName.StartsWith($Best.ExtractRoot, [StringComparison]::OrdinalIgnoreCase)) {
    if ($Cursor.Name -eq "Content") {
        $ContentRoot = $Cursor
        break
    }
    $Cursor = $Cursor.Parent
}

if (-not $ContentRoot) {
    Stop-Gate "CANNOT_LOCATE_CONTENT_ROOT_IN_SELECTED_PACK" 22
}

$RelativeMannequins = $MannequinsDir.FullName.Substring($ContentRoot.FullName.Length).TrimStart('\')
$Destination = Join-Path (Join-Path $ProjectRoot "Content") $RelativeMannequins

Write-Host "FEATUREPACK_CONTENT_ROOT=$($ContentRoot.FullName)"
Write-Host "FEATUREPACK_MANNEQUINS_SOURCE=$($MannequinsDir.FullName)"
Write-Host "PROJECT_MANNEQUINS_DESTINATION=$Destination"

$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\ThirdPersonFeaturePackImport_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

if (Test-Path -LiteralPath $Destination -PathType Container) {
    $ExistingBackup = Join-Path $BackupRoot "ExistingProjectMannequins"
    Copy-Item -LiteralPath $Destination -Destination $ExistingBackup -Recurse -Force
    Write-Host "EXISTING_DESTINATION_BACKUP=$ExistingBackup"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
Copy-Item -LiteralPath $MannequinsDir.FullName -Destination (Split-Path -Parent $Destination) -Recurse -Force

if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
    Stop-Gate "COPY_FINISHED_BUT_DESTINATION_NOT_FOUND" 23
}

$CopiedAssets = @(Get-ChildItem -LiteralPath $Destination -File -Recurse -Filter "*.uasset" -ErrorAction SilentlyContinue)
$CopiedMesh = @($CopiedAssets | Where-Object { $_.Name -in @("SKM_Manny.uasset","SKM_Manny_Simple.uasset") })
$CopiedABP = @($CopiedAssets | Where-Object { $_.Name -eq "ABP_Manny.uasset" })

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COPY VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "COPIED_UASSET_COUNT=$($CopiedAssets.Count)"
Write-Host "COPIED_MANNY_MESH_COUNT=$($CopiedMesh.Count)"
Write-Host "COPIED_ABP_MANNY_COUNT=$($CopiedABP.Count)"

if ($CopiedMesh.Count -eq 0 -or $CopiedABP.Count -eq 0) {
    Stop-Gate "COPIED_MANNEQUIN_SET_INCOMPLETE" 24
}

# Compute candidate /Game package paths from copied files.
function To-GamePath([System.IO.FileInfo]$File) {
    $ProjectContent = Join-Path $ProjectRoot "Content"
    $Rel = $File.FullName.Substring($ProjectContent.Length).TrimStart('\')
    $RelNoExt = [IO.Path]::ChangeExtension($Rel, $null).TrimEnd('.')
    return "/Game/" + ($RelNoExt -replace '\\','/')
}

$MeshPaths = @($CopiedMesh | ForEach-Object { To-GamePath $_ })
$ABPPaths = @($CopiedABP | ForEach-Object { To-GamePath $_ })

foreach ($Path in $MeshPaths) { Write-Host "IMPORTED_MESH_CANDIDATE=$Path" }
foreach ($Path in $ABPPaths) { Write-Host "IMPORTED_ABP_CANDIDATE=$Path" }

# Real Unreal load + skeleton compatibility verification after copy.
$EvidenceRoot = Join-Path $ProjectRoot "Saved\Verification\ThirdPersonFeaturePackImportVerify_$Stamp"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$PyFile = Join-Path $EvidenceRoot "verify_imported_manny.py"
$StdOut = Join-Path $EvidenceRoot "verify_imported_manny.stdout.log"
$StdErr = Join-Path $EvidenceRoot "verify_imported_manny.stderr.log"

$MeshListPy = ($MeshPaths | ForEach-Object { '"' + $_.Replace('"','\"') + '"' }) -join ","
$ABPListPy = ($ABPPaths | ForEach-Object { '"' + $_.Replace('"','\"') + '"' }) -join ","

$Python = @"
import unreal

mesh_paths = [$MeshListPy]
abp_paths = [$ABPListPy]

def safe_path(obj):
    try:
        return obj.get_path_name() if obj else "NONE"
    except Exception:
        return "ERROR"

def mesh_skeleton(mesh):
    try:
        return mesh.get_editor_property("skeleton")
    except Exception:
        try:
            return mesh.skeleton
        except Exception:
            return None

def abp_skeleton(abp):
    for prop in ("target_skeleton", "skeleton"):
        try:
            v = abp.get_editor_property(prop)
            if v:
                return v
        except Exception:
            pass
    return None

print("=== ASWW IMPORTED MANNY VERIFY ===")

loaded_meshes = []
loaded_abps = []

for path in mesh_paths:
    exists = unreal.EditorAssetLibrary.does_asset_exist(path)
    obj = unreal.EditorAssetLibrary.load_asset(path) if exists else None
    cls = obj.get_class().get_name() if obj else "NONE"
    skel = mesh_skeleton(obj) if obj else None
    print(f"IMPORTED_MESH|{path}|EXISTS={exists}|LOAD={obj is not None}|CLASS={cls}|SKELETON={safe_path(skel)}")
    if obj and cls == "SkeletalMesh":
        loaded_meshes.append((path, obj, safe_path(skel)))

for path in abp_paths:
    exists = unreal.EditorAssetLibrary.does_asset_exist(path)
    obj = unreal.EditorAssetLibrary.load_asset(path) if exists else None
    cls = obj.get_class().get_name() if obj else "NONE"
    skel = abp_skeleton(obj) if obj else None
    print(f"IMPORTED_ABP|{path}|EXISTS={exists}|LOAD={obj is not None}|CLASS={cls}|SKELETON={safe_path(skel)}")
    if obj and cls == "AnimBlueprint":
        loaded_abps.append((path, obj, safe_path(skel)))

best = None
for mp, mo, ms in loaded_meshes:
    for ap, ao, aps in loaded_abps:
        compat = (ms != "NONE" and aps != "NONE" and ms == aps)
        print(f"PAIR_CHECK|MESH={mp}|ABP={ap}|COMPATIBLE={compat}|MESH_SKEL={ms}|ABP_SKEL={aps}")
        if best is None and compat:
            best = (mp, ap, ms)

if best:
    print(f"BEST_IMPORTED_MESH={best[0]}")
    print(f"BEST_IMPORTED_ABP={best[1]}")
    print(f"BEST_IMPORTED_SKELETON={best[2]}")
    print("IMPORTED_MANNY_COMPATIBILITY=PASS")
else:
    print("BEST_IMPORTED_MESH=NONE")
    print("BEST_IMPORTED_ABP=NONE")
    print("BEST_IMPORTED_SKELETON=NONE")
    print("IMPORTED_MANNY_COMPATIBILITY=FAIL")

print("NO_ASSETS_MODIFIED_BY_VERIFY=TRUE")
"@

[IO.File]::WriteAllText($PyFile, $Python, [Text.UTF8Encoding]::new($false))
$PyForward = $PyFile.Replace('\','/')

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " UNREAL LOAD + SKELETON VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Args = @(
    $ProjectFile,
    "-unattended",
    "-nop4",
    "-nosplash",
    "-NullRHI",
    "-stdout",
    "-FullStdOutLogOutput",
    "-ExecutePythonScript=$PyForward"
)

$Proc = Start-Process `
    -FilePath $EditorCmd `
    -ArgumentList $Args `
    -WorkingDirectory $ProjectRoot `
    -PassThru `
    -Wait `
    -RedirectStandardOutput $StdOut `
    -RedirectStandardError $StdErr

$Exit = $Proc.ExitCode
Write-Host "UNREAL_EDITOR_CMD_EXIT=$Exit"

$Out = if (Test-Path -LiteralPath $StdOut) { Get-Content -Raw -LiteralPath $StdOut } else { "" }
$Err = if (Test-Path -LiteralPath $StdErr) { Get-Content -Raw -LiteralPath $StdErr } else { "" }
$Text = $Out + "`n" + $Err

$Interesting = @($Text -split "`r?`n" | Where-Object {
    $_ -match 'IMPORTED_MESH\||IMPORTED_ABP\||PAIR_CHECK\||BEST_IMPORTED_|IMPORTED_MANNY_COMPATIBILITY=|NO_ASSETS_MODIFIED_BY_VERIFY='
})

foreach ($Line in $Interesting) {
    if ($Line -match 'LogPython:\s*(.*)$') {
        Write-Host $Matches[1]
    } else {
        Write-Host $Line
    }
}

$PythonError = $Text -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$Compat = $Text -match "IMPORTED_MANNY_COMPATIBILITY=PASS"

Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "FATAL_ERROR_SEEN=$Fatal"

if ($Exit -ne 0 -or $PythonError -or $Fatal) {
    Stop-Gate "UNREAL_VERIFY_FAILED_AFTER_IMPORT" $(if ($Exit -gt 0) { $Exit } else { 30 })
}

if (-not $Compat) {
    Write-Host "THIRDPERSON_MANNEQUIN_IMPORT=PARTIAL_COPY_DONE_BUT_COMPATIBILITY_FAILED" -ForegroundColor Red
    Write-Host "IMPORT_BACKUP_ROOT=$BackupRoot"
    Write-Host "NEXT_GATE=INSPECT_IMPORTED_ASSET_CLASSES_AND_DEPENDENCIES" -ForegroundColor Yellow
    Write-Host "DO_NOT_COMMIT" -ForegroundColor Yellow
    exit 31
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"
if ($DiffExit -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 32
}

Write-Host ""
Write-Host "THIRDPERSON_MANNEQUIN_IMPORT=PASS" -ForegroundColor Green
Write-Host "FEATUREPACK_SOURCE=$($Best.PackPath)" -ForegroundColor Green
Write-Host "PROJECT_MANNEQUIN_PATH=$Destination" -ForegroundColor Green
Write-Host "IMPORTED_MANNY_COMPATIBILITY=PASS" -ForegroundColor Green
Write-Host "NEXT_GATE=INTEGRATE_IMPORTED_MANNY_IN_ASCHARACTER_AND_PACKAGE" -ForegroundColor Green
Write-Host "KEEP_TEMP_VISUAL_PROOF_UNTIL_REAL_MANNY_PACKAGE_PASSES" -ForegroundColor Yellow
Write-Host "DO_NOT_COMMIT_VISUAL_PROOF_OR_TELEMETRY" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
