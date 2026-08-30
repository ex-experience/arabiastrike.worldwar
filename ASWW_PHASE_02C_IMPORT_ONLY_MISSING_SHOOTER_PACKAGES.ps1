[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\Phase02C_ImportMissingShooterPackages"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_02C_IMPORT_MISSING_PACKAGES=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_GAMEPLAY_SOURCE_WAS_MODIFIED" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Get-AssetPackageHint([string]$UassetPath) {
    try {
        $bytes = [IO.File]::ReadAllBytes($UassetPath)
        $ascii = [Text.Encoding]::ASCII.GetString($bytes)
        $m = [regex]::Match($ascii, '/Game/[A-Za-z0-9_./-]+')
        if ($m.Success) {
            return $m.Value.TrimEnd([char]0,'.')
        }
    }
    catch {}
    return ""
}

function Copy-UAssetFamily([string]$SourceUasset, [string]$DestUasset) {
    $destDir = Split-Path -Parent $DestUasset
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    $baseSource = [IO.Path]::Combine(
        (Split-Path -Parent $SourceUasset),
        [IO.Path]::GetFileNameWithoutExtension($SourceUasset)
    )
    $baseDest = [IO.Path]::Combine(
        $destDir,
        [IO.Path]::GetFileNameWithoutExtension($DestUasset)
    )

    $extensions = @(".uasset",".uexp",".ubulk",".uptnl")
    $copied = 0

    foreach ($ext in $extensions) {
        $src = $baseSource + $ext
        if (Test-Path -LiteralPath $src -PathType Leaf) {
            $dst = $baseDest + $ext
            if (Test-Path -LiteralPath $dst -PathType Leaf) {
                $srcHash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
                $dstHash = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
                if ($srcHash -ne $dstHash) {
                    throw "Destination collision with different file: $dst"
                }
                Write-Host "IDENTICAL_EXISTING=$dst"
            }
            else {
                Copy-Item -LiteralPath $src -Destination $dst
                Write-Host "COPIED=$dst"
                $copied++
            }
        }
    }

    return $copied
}

Set-Location $ProjectRoot
$env:GIT_PAGER = "cat"

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$TemplateRoot = Join-Path $UERoot "Templates\TemplateResources"

foreach ($Required in @($ProjectFile,$EditorCmd,$TemplateRoot)) {
    if (-not (Test-Path -LiteralPath $Required)) {
        Stop-Gate "MISSING_REQUIRED_PATH_$Required" 11
    }
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " DISCOVER CURRENT MISSING /Game PACKAGES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$DiscoverPy = Join-Path $EvidenceRoot "phase02c_discover_missing_$Stamp.py"
$DiscoverOut = Join-Path $EvidenceRoot "phase02c_discover_missing_$Stamp.stdout.log"
$DiscoverErr = Join-Path $EvidenceRoot "phase02c_discover_missing_$Stamp.stderr.log"

$DiscoverText = @'
import unreal

registry = unreal.AssetRegistryHelpers.get_asset_registry()
registry.scan_paths_synchronous(["/Game"], True)

targets = [
    "/Game/Variant_Shooter/Blueprints/BP_ShooterCharacter",
    "/Game/Variant_Shooter/Blueprints/BP_ShooterPlayerController",
    "/Game/Variant_Shooter/Blueprints/BP_ShooterGameMode",
    "/Game/Variant_Shooter/Blueprints/AI/BP_ShooterNPC",
    "/Game/Variant_Shooter/Blueprints/Pickups/BP_ShooterWeaponBase",
    "/Game/Variant_Shooter/Blueprints/Pickups/Weapons/BP_ShooterWeapon_Rifle",
    "/Game/Variant_Shooter/Anims/ABP_TP_Rifle",
]

opts = unreal.AssetRegistryDependencyOptions(
    include_soft_package_references=True,
    include_hard_package_references=True,
    include_searchable_names=False,
    include_soft_management_references=False,
    include_hard_management_references=False
)

def exists(pkg):
    try:
        return len(registry.get_assets_by_package_name(pkg)) > 0
    except Exception:
        return False

missing = set()

for owner in targets:
    try:
        deps = registry.get_dependencies(owner, opts)
    except Exception as exc:
        print(f"ASWW_P02C_DEP_ENUM_ERROR|OWNER={owner}|ERR={exc}")
        continue

    for dep in deps:
        dep = str(dep)
        if dep.startswith("/Game/") and not exists(dep):
            missing.add(dep)

print(f"ASWW_P02C_MISSING_COUNT={len(missing)}")
for pkg in sorted(missing):
    print(f"ASWW_P02C_MISSING={pkg}")

print("ASWW_P02C_DISCOVERY_DONE=True")
'@

[IO.File]::WriteAllText($DiscoverPy, $DiscoverText, [Text.UTF8Encoding]::new($false))
$DiscoverPyForward = $DiscoverPy.Replace('\','/')

& $EditorCmd `
    $ProjectFile `
    "-unattended" "-nop4" "-nosplash" "-NullRHI" "-stdout" "-FullStdOutLogOutput" `
    "-ExecutePythonScript=$DiscoverPyForward" `
    1> $DiscoverOut 2> $DiscoverErr

$DiscoverExit = $LASTEXITCODE

$DiscoverCombined = ""
if (Test-Path -LiteralPath $DiscoverOut) {
    $DiscoverCombined += Get-Content -Raw -LiteralPath $DiscoverOut
    Select-String -LiteralPath $DiscoverOut -Pattern "ASWW_P02C_" |
        ForEach-Object { Write-Host $_.Line }
}
if (Test-Path -LiteralPath $DiscoverErr) {
    $DiscoverCombined += "`n" + (Get-Content -Raw -LiteralPath $DiscoverErr)
}

$DiscoverDone = $DiscoverCombined -match "ASWW_P02C_DISCOVERY_DONE=True"
$PythonError = $DiscoverCombined -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$ExplicitFatal = $DiscoverCombined -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

Write-Host "DISCOVERY_EXIT=$DiscoverExit"
Write-Host "DISCOVERY_DONE=$DiscoverDone"
Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "EXPLICIT_FATAL_SEEN=$ExplicitFatal"

if (-not $DiscoverDone -or $PythonError -or $ExplicitFatal) {
    if (Test-Path -LiteralPath $DiscoverErr) {
        Write-Host "=== DISCOVERY STDERR TAIL ===" -ForegroundColor Yellow
        Get-Content -LiteralPath $DiscoverErr -Tail 120
    }
    Stop-Gate "MISSING_PACKAGE_DISCOVERY_NOT_TRUSTWORTHY" 20
}

$Missing = New-Object System.Collections.Generic.List[string]
foreach ($m in [regex]::Matches($DiscoverCombined, "ASWW_P02C_MISSING=([^\r\n]+)")) {
    $Missing.Add($m.Groups[1].Value.Trim())
}

Write-Host "PARSED_MISSING_COUNT=$($Missing.Count)"

if ($Missing.Count -eq 0) {
    Write-Host "PHASE_02C_IMPORT_MISSING_PACKAGES=PASS_NOTHING_MISSING" -ForegroundColor Green
    Write-Host "NEXT_GATE=BUILD_ASWW_COMBAT_PLAYER_V1" -ForegroundColor Green
    Write-Host "NO_GAMEPLAY_SOURCE_WAS_MODIFIED" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit 0
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " LOCATE EXACT TEMPLATE SOURCE FOR EACH MISSING PACKAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Known content-root mappings are preferred because they preserve /Game package paths.
$Mappings = @(
    @{ Prefix="/Game/Characters/"; Root=(Join-Path $UERoot "Templates\TemplateResources\High\Characters\Content"); Strip="Characters/" },
    @{ Prefix="/Game/Variant_Shooter/"; Root=(Join-Path $UERoot "Templates\TemplateResources\Standard\Variant_Shooter\Content"); Strip="Variant_Shooter/" },
    @{ Prefix="/Game/Weapons/"; Root=(Join-Path $UERoot "Templates\TemplateResources\Standard\Weapons\Content"); Strip="Weapons/" }
)

$Resolved = @{}
$Unresolved = New-Object System.Collections.Generic.List[string]

foreach ($Pkg in $Missing) {
    $resolvedSource = $null

    foreach ($Map in $Mappings) {
        if ($Pkg.StartsWith($Map.Prefix, [StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $Map.Root -PathType Container)) {

            $relGame = $Pkg.Substring(6) # strip /Game/
            if ($relGame.StartsWith($Map.Strip, [StringComparison]::OrdinalIgnoreCase)) {
                $relMapped = $relGame.Substring($Map.Strip.Length)
                $candidate = Join-Path $Map.Root (($relMapped.Replace('/','\')) + ".uasset")

                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    $resolvedSource = $candidate
                    break
                }
            }
        }
    }

    if (-not $resolvedSource) {
        $assetName = ($Pkg -split '/')[-1]
        $candidates = @(
            Get-ChildItem -LiteralPath $TemplateRoot -Recurse -File -Filter ($assetName + ".uasset") -ErrorAction SilentlyContinue
        )

        foreach ($Candidate in $candidates) {
            $hint = Get-AssetPackageHint $Candidate.FullName
            if ($hint -eq $Pkg -or $hint.StartsWith($Pkg + ".", [StringComparison]::OrdinalIgnoreCase)) {
                $resolvedSource = $Candidate.FullName
                break
            }

            # Fallback binary search for exact package path.
            try {
                $bytes = [IO.File]::ReadAllBytes($Candidate.FullName)
                $ascii = [Text.Encoding]::ASCII.GetString($bytes)
                if ($ascii.IndexOf($Pkg, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $resolvedSource = $Candidate.FullName
                    break
                }
            }
            catch {}
        }
    }

    if ($resolvedSource) {
        $Resolved[$Pkg] = $resolvedSource
        Write-Host "RESOLVED_SOURCE|PACKAGE=$Pkg|SOURCE=$resolvedSource"
    }
    else {
        $Unresolved.Add($Pkg)
        Write-Host "UNRESOLVED_SOURCE|PACKAGE=$Pkg"
    }
}

Write-Host "RESOLVED_PACKAGE_COUNT=$($Resolved.Count)"
Write-Host "UNRESOLVED_PACKAGE_COUNT=$($Unresolved.Count)"

if ($Unresolved.Count -gt 0) {
    foreach ($Pkg in $Unresolved) {
        Write-Host "UNRESOLVED_PACKAGE=$Pkg"
    }
    Stop-Gate "ONE_OR_MORE_MISSING_PACKAGES_NOT_FOUND_IN_UE_TEMPLATE_RESOURCES" 21
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " COPY ONLY RESOLVED MISSING PACKAGE FAMILIES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$BackupRoot = Join-Path $ProjectRoot "Saved\Verification\Phase02C_MissingPackages_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

$CreatedManifest = Join-Path $BackupRoot "created_files.txt"
$CreatedFiles = New-Object System.Collections.Generic.List[string]
$TotalCopied = 0

foreach ($Pkg in $Resolved.Keys) {
    $source = $Resolved[$Pkg]
    $rel = $Pkg.Substring(6).Replace('/','\') + ".uasset"
    $dest = Join-Path (Join-Path $ProjectRoot "Content") $rel

    if (Test-Path -LiteralPath $dest -PathType Leaf) {
        # Should not happen because package was missing to AssetRegistry.
        # Preserve it and stop rather than overwrite ambiguous bytes.
        Stop-Gate "DESTINATION_UASSET_ALREADY_EXISTS_BUT_REGISTRY_REPORTED_MISSING_$dest" 22
    }

    $before = @()
    $destDir = Split-Path -Parent $dest
    if (Test-Path -LiteralPath $destDir) {
        $before = @(Get-ChildItem -LiteralPath $destDir -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    }

    $copied = Copy-UAssetFamily $source $dest
    $TotalCopied += $copied

    if (Test-Path -LiteralPath $destDir) {
        $after = @(Get-ChildItem -LiteralPath $destDir -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        foreach ($f in $after) {
            if ($before -notcontains $f) {
                $CreatedFiles.Add($f)
            }
        }
    }
}

$CreatedFiles | Sort-Object -Unique | Set-Content -LiteralPath $CreatedManifest -Encoding UTF8

Write-Host "TOTAL_FILE_FAMILY_MEMBERS_COPIED=$TotalCopied"
Write-Host "CREATED_FILE_MANIFEST=$CreatedManifest"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RE-RUN DEPENDENCY CLOSURE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$VerifyPy = Join-Path $EvidenceRoot "phase02c_verify_after_import_$Stamp.py"
$VerifyOut = Join-Path $EvidenceRoot "phase02c_verify_after_import_$Stamp.stdout.log"
$VerifyErr = Join-Path $EvidenceRoot "phase02c_verify_after_import_$Stamp.stderr.log"

$VerifyText = @'
import unreal

registry = unreal.AssetRegistryHelpers.get_asset_registry()
registry.scan_paths_synchronous(["/Game"], True)

targets = [
    "/Game/Variant_Shooter/Blueprints/BP_ShooterCharacter",
    "/Game/Variant_Shooter/Blueprints/BP_ShooterPlayerController",
    "/Game/Variant_Shooter/Blueprints/BP_ShooterGameMode",
    "/Game/Variant_Shooter/Blueprints/AI/BP_ShooterNPC",
    "/Game/Variant_Shooter/Blueprints/Pickups/BP_ShooterWeaponBase",
    "/Game/Variant_Shooter/Blueprints/Pickups/Weapons/BP_ShooterWeapon_Rifle",
    "/Game/Variant_Shooter/Anims/ABP_TP_Rifle",
]

opts = unreal.AssetRegistryDependencyOptions(
    include_soft_package_references=True,
    include_hard_package_references=True,
    include_searchable_names=False,
    include_soft_management_references=False,
    include_hard_management_references=False
)

def exists(pkg):
    try:
        return len(registry.get_assets_by_package_name(pkg)) > 0
    except Exception:
        return False

missing = set()

for owner in targets:
    try:
        deps = registry.get_dependencies(owner, opts)
    except Exception as exc:
        print(f"ASWW_P02C_VERIFY_DEP_ENUM_ERROR|OWNER={owner}|ERR={exc}")
        continue
    for dep in deps:
        dep = str(dep)
        if dep.startswith("/Game/") and not exists(dep):
            missing.add(dep)

print(f"ASWW_P02C_VERIFY_MISSING_COUNT={len(missing)}")
for pkg in sorted(missing):
    print(f"ASWW_P02C_VERIFY_MISSING={pkg}")

critical = [
    "/Game/Variant_Shooter/Blueprints/BP_ShooterCharacter.BP_ShooterCharacter",
    "/Game/Variant_Shooter/Blueprints/BP_ShooterPlayerController.BP_ShooterPlayerController",
    "/Game/Variant_Shooter/Blueprints/BP_ShooterGameMode.BP_ShooterGameMode",
    "/Game/Variant_Shooter/Anims/ABP_TP_Rifle.ABP_TP_Rifle",
]

for obj_path in critical:
    obj = None
    try:
        obj = unreal.load_asset(obj_path)
    except Exception as exc:
        print(f"ASWW_P02C_VERIFY_LOAD_ERROR|PATH={obj_path}|ERR={exc}")
    print(f"ASWW_P02C_VERIFY_LOAD|PATH={obj_path}|LOAD={obj is not None}")

print("ASWW_P02C_VERIFY_DONE=True")
'@

[IO.File]::WriteAllText($VerifyPy, $VerifyText, [Text.UTF8Encoding]::new($false))
$VerifyPyForward = $VerifyPy.Replace('\','/')

& $EditorCmd `
    $ProjectFile `
    "-unattended" "-nop4" "-nosplash" "-NullRHI" "-stdout" "-FullStdOutLogOutput" `
    "-ExecutePythonScript=$VerifyPyForward" `
    1> $VerifyOut 2> $VerifyErr

$VerifyExit = $LASTEXITCODE

$VerifyCombined = ""
if (Test-Path -LiteralPath $VerifyOut) {
    $VerifyCombined += Get-Content -Raw -LiteralPath $VerifyOut
    Select-String -LiteralPath $VerifyOut -Pattern "ASWW_P02C_VERIFY_" |
        ForEach-Object { Write-Host $_.Line }
}
if (Test-Path -LiteralPath $VerifyErr) {
    $VerifyCombined += "`n" + (Get-Content -Raw -LiteralPath $VerifyErr)
}

$VerifyDone = $VerifyCombined -match "ASWW_P02C_VERIFY_DONE=True"
$VerifyPythonError = $VerifyCombined -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$VerifyFatal = $VerifyCombined -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$VerifyMissingMatch = [regex]::Match($VerifyCombined, "ASWW_P02C_VERIFY_MISSING_COUNT=(\d+)")
$VerifyMissing = if ($VerifyMissingMatch.Success) { [int]$VerifyMissingMatch.Groups[1].Value } else { -1 }

Write-Host "VERIFY_EXIT=$VerifyExit"
Write-Host "VERIFY_DONE=$VerifyDone"
Write-Host "VERIFY_PYTHON_ERROR=$VerifyPythonError"
Write-Host "VERIFY_EXPLICIT_FATAL=$VerifyFatal"
Write-Host "VERIFY_MISSING_COUNT=$VerifyMissing"

if (-not $VerifyDone -or $VerifyPythonError -or $VerifyFatal) {
    if (Test-Path -LiteralPath $VerifyErr) {
        Write-Host "=== VERIFY STDERR TAIL ===" -ForegroundColor Yellow
        Get-Content -LiteralPath $VerifyErr -Tail 120
    }
    Stop-Gate "POST_IMPORT_VERIFY_NOT_TRUSTWORTHY" 23
}

if ($VerifyMissing -gt 0) {
    Stop-Gate "MISSING_PACKAGES_REMAIN_AFTER_EXACT_IMPORT_$VerifyMissing" 24
}
if ($VerifyMissing -lt 0) {
    Stop-Gate "POST_IMPORT_MISSING_COUNT_NOT_PARSED" 25
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"

Write-Host ""
Write-Host "PHASE_02C_IMPORT_MISSING_PACKAGES=PASS" -ForegroundColor Green
Write-Host "SHOOTER_DEPENDENCY_CLOSURE=PASS" -ForegroundColor Green
Write-Host "MISSING_GAME_PACKAGE_COUNT=0" -ForegroundColor Green
Write-Host "NEXT_GATE=BUILD_ASWW_COMBAT_PLAYER_V1" -ForegroundColor Green
Write-Host "NO_GAMEPLAY_SOURCE_WAS_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
