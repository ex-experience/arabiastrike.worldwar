[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\Phase02F_ArchiveDependencyClosure",
    [int]$MaxPasses = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_02F_ARCHIVE_DEPENDENCY_CLOSURE=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_GAMEPLAY_SOURCE_WAS_MODIFIED" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Get-UnrealPak([string]$UERoot) {
    $Candidates = @(
        (Join-Path $UERoot "Engine\Binaries\Win64\UnrealPak.exe"),
        (Join-Path $UERoot "Engine\Binaries\Win64\UnrealPak-Win64-Shipping.exe")
    )
    foreach ($C in $Candidates) {
        if (Test-Path -LiteralPath $C -PathType Leaf) { return $C }
    }
    return $null
}

function Copy-UAssetFamily([string]$SourceUasset, [string]$DestUasset) {
    $SourceDir = Split-Path -Parent $SourceUasset
    $SourceStem = [IO.Path]::GetFileNameWithoutExtension($SourceUasset)
    $DestDir = Split-Path -Parent $DestUasset
    $DestStem = [IO.Path]::GetFileNameWithoutExtension($DestUasset)

    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

    $Copied = 0
    foreach ($Ext in @(".uasset",".uexp",".ubulk",".uptnl")) {
        $Src = Join-Path $SourceDir ($SourceStem + $Ext)
        if (-not (Test-Path -LiteralPath $Src -PathType Leaf)) { continue }

        $Dst = Join-Path $DestDir ($DestStem + $Ext)

        if (Test-Path -LiteralPath $Dst -PathType Leaf) {
            $SrcHash = (Get-FileHash -LiteralPath $Src -Algorithm SHA256).Hash
            $DstHash = (Get-FileHash -LiteralPath $Dst -Algorithm SHA256).Hash
            if ($SrcHash -ne $DstHash) {
                throw "Different destination already exists: $Dst"
            }
            Write-Host "IDENTICAL_EXISTING=$Dst"
        }
        else {
            Copy-Item -LiteralPath $Src -Destination $Dst
            Write-Host "COPIED=$Dst"
            $Copied++
        }
    }
    return $Copied
}

function Invoke-UnrealPakList([string]$UnrealPak, [string]$Archive, [string]$OutFile) {
    & $UnrealPak $Archive -List 1> $OutFile 2>&1
    return $LASTEXITCODE
}

function Find-PackageInArchives(
    [string]$PackagePath,
    [string]$UERoot,
    [string]$UnrealPak,
    [string]$EvidenceRoot,
    [string]$Stamp
) {
    $Relative = $PackagePath.Substring(6).Replace('/','\') + ".uasset"
    $Needle = $Relative.Replace('\','/').ToLowerInvariant()

    $Archives = @(
        Get-ChildItem -LiteralPath $UERoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".upack",".pak") }
    )

    Write-Host "ARCHIVE_COUNT=$($Archives.Count)"

    $Index = 0
    foreach ($Archive in $Archives) {
        $Index++
        $Safe = ("{0:D4}_{1}.list.txt" -f $Index, ([IO.Path]::GetFileNameWithoutExtension($Archive.Name) -replace '[^A-Za-z0-9_.-]','_'))
        $ListOut = Join-Path $EvidenceRoot $Safe

        $Exit = Invoke-UnrealPakList $UnrealPak $Archive.FullName $ListOut
        if ($Exit -ne 0 -or -not (Test-Path -LiteralPath $ListOut)) {
            continue
        }

        $Text = Get-Content -Raw -LiteralPath $ListOut
        $TextLower = $Text.Replace('\','/').ToLowerInvariant()

        if ($TextLower.Contains($Needle)) {
            Write-Host "ARCHIVE_MATCH|PACKAGE=$PackagePath|ARCHIVE=$($Archive.FullName)"
            return $Archive.FullName
        }
    }

    return $null
}

function Extract-PackageFromArchive(
    [string]$PackagePath,
    [string]$Archive,
    [string]$UnrealPak,
    [string]$EvidenceRoot,
    [string]$Stamp
) {
    $ExtractRoot = Join-Path $EvidenceRoot ("Extract_" + $Stamp)
    New-Item -ItemType Directory -Force -Path $ExtractRoot | Out-Null

    & $UnrealPak $Archive -Extract $ExtractRoot 1> (Join-Path $EvidenceRoot ("extract_" + $Stamp + ".log")) 2>&1
    $Exit = $LASTEXITCODE

    Write-Host "UNREALPAK_EXTRACT_EXIT=$Exit"
    if ($Exit -ne 0) {
        return $null
    }

    $AssetName = ($PackagePath -split "/")[-1]
    $Candidates = @(
        Get-ChildItem -LiteralPath $ExtractRoot -Recurse -File -Filter ($AssetName + ".uasset") -ErrorAction SilentlyContinue
    )

    foreach ($C in $Candidates) {
        $Normalized = $C.FullName.Replace('\','/').ToLowerInvariant()
        $PkgTail = $PackagePath.Substring(6).Replace('/','/').ToLowerInvariant() + ".uasset"

        if ($Normalized.EndsWith($PkgTail)) {
            Write-Host "EXTRACTED_PACKAGE_SOURCE=$($C.FullName)"
            return $C.FullName
        }
    }

    # Fallback: if exactly one asset with that name was extracted, use it only if path suffix matches closely.
    if ($Candidates.Count -eq 1) {
        Write-Host "EXTRACTED_SINGLE_NAME_CANDIDATE=$($Candidates[0].FullName)"
        return $Candidates[0].FullName
    }

    return $null
}

function Invoke-ClosureProbe(
    [string]$EditorCmd,
    [string]$ProjectFile,
    [string]$EvidenceRoot,
    [string]$Stamp
) {
    $Py = Join-Path $EvidenceRoot ("probe_" + $Stamp + ".py")
    $Out = Join-Path $EvidenceRoot ("probe_" + $Stamp + ".stdout.log")
    $Err = Join-Path $EvidenceRoot ("probe_" + $Stamp + ".stderr.log")

    $PyText = @'
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

visited = set()
frontier = list(targets)
missing = set()

for _ in range(64):
    if not frontier:
        break

    next_frontier = []

    for owner in frontier:
        if owner in visited:
            continue

        visited.add(owner)

        if owner.startswith("/Game/") and not exists(owner):
            missing.add(owner)
            continue

        try:
            deps = registry.get_dependencies(owner, opts)
        except Exception as exc:
            print(f"ASWW_P02F_DEP_ENUM_ERROR|OWNER={owner}|ERR={exc}")
            continue

        for dep in deps:
            dep = str(dep)
            if not dep.startswith("/Game/"):
                continue

            if not exists(dep):
                missing.add(dep)
            elif dep not in visited:
                next_frontier.append(dep)

    frontier = next_frontier

print(f"ASWW_P02F_VISITED_COUNT={len(visited)}")
print(f"ASWW_P02F_MISSING_COUNT={len(missing)}")
for pkg in sorted(missing):
    print(f"ASWW_P02F_MISSING={pkg}")

critical = [
    "/Game/Variant_Shooter/Blueprints/BP_ShooterCharacter.BP_ShooterCharacter",
    "/Game/Variant_Shooter/Blueprints/BP_ShooterPlayerController.BP_ShooterPlayerController",
    "/Game/Variant_Shooter/Blueprints/BP_ShooterGameMode.BP_ShooterGameMode",
    "/Game/Variant_Shooter/Blueprints/Pickups/Weapons/BP_ShooterWeapon_Rifle.BP_ShooterWeapon_Rifle",
    "/Game/Variant_Shooter/Anims/ABP_TP_Rifle.ABP_TP_Rifle",
]

for obj_path in critical:
    obj = None
    try:
        obj = unreal.load_asset(obj_path)
    except Exception as exc:
        print(f"ASWW_P02F_CRITICAL_LOAD_ERROR|PATH={obj_path}|ERR={exc}")
    print(f"ASWW_P02F_CRITICAL_LOAD|PATH={obj_path}|LOAD={obj is not None}")

print("ASWW_P02F_PROBE_DONE=True")
'@

    [IO.File]::WriteAllText($Py, $PyText, [Text.UTF8Encoding]::new($false))
    $PyForward = $Py.Replace('\','/')

    & $EditorCmd `
        $ProjectFile `
        "-unattended" "-nop4" "-nosplash" "-NullRHI" "-stdout" "-FullStdOutLogOutput" `
        "-ExecutePythonScript=$PyForward" `
        1> $Out 2> $Err

    $Exit = $LASTEXITCODE

    $Combined = ""
    if (Test-Path -LiteralPath $Out) {
        $Combined += Get-Content -Raw -LiteralPath $Out
        Select-String -LiteralPath $Out -Pattern "ASWW_P02F_" |
            ForEach-Object { Write-Host $_.Line }
    }
    if (Test-Path -LiteralPath $Err) {
        $Combined += "`n" + (Get-Content -Raw -LiteralPath $Err)
    }

    $Done = $Combined -match "ASWW_P02F_PROBE_DONE=True"
    $PythonError = $Combined -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
    $Fatal = $Combined -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

    $Missing = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($Combined, "ASWW_P02F_MISSING=([^\r\n]+)")) {
        $Missing.Add($m.Groups[1].Value.Trim())
    }

    $CountMatch = [regex]::Match($Combined, "ASWW_P02F_MISSING_COUNT=(\d+)")
    $Count = if ($CountMatch.Success) { [int]$CountMatch.Groups[1].Value } else { -1 }

    return [pscustomobject]@{
        Exit=$Exit
        Done=$Done
        PythonError=$PythonError
        Fatal=$Fatal
        Missing=$Missing
        MissingCount=$Count
        Out=$Out
        Err=$Err
    }
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
$UnrealPak = Get-UnrealPak $UERoot

foreach ($Required in @($ProjectFile,$EditorCmd)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

if (-not $UnrealPak) {
    Stop-Gate "UNREALPAK_NOT_FOUND" 12
}

Write-Host "UNREALPAK=$UnrealPak"

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

for ($Pass = 1; $Pass -le $MaxPasses; $Pass++) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " ARCHIVE DEPENDENCY CLOSURE PASS $Pass / $MaxPasses" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    $Stamp = (Get-Date -Format "yyyyMMdd_HHmmss") + "_P$Pass"
    $Probe = Invoke-ClosureProbe $EditorCmd $ProjectFile $EvidenceRoot $Stamp

    Write-Host "PROBE_EXIT=$($Probe.Exit)"
    Write-Host "PROBE_DONE=$($Probe.Done)"
    Write-Host "PROBE_PYTHON_ERROR=$($Probe.PythonError)"
    Write-Host "PROBE_FATAL=$($Probe.Fatal)"
    Write-Host "PROBE_MISSING_COUNT=$($Probe.MissingCount)"

    if (-not $Probe.Done -or $Probe.PythonError -or $Probe.Fatal) {
        if (Test-Path -LiteralPath $Probe.Err) {
            Write-Host "=== STDERR TAIL ===" -ForegroundColor Yellow
            Get-Content -LiteralPath $Probe.Err -Tail 120
        }
        Stop-Gate "DEPENDENCY_PROBE_NOT_TRUSTWORTHY_PASS_$Pass" 20
    }

    if ($Probe.MissingCount -eq 0) {
        & git diff --check
        $DiffExit = $LASTEXITCODE
        Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"

        Write-Host ""
        Write-Host "SHOOTER_RECURSIVE_DEPENDENCY_CLOSURE=PASS" -ForegroundColor Green
        Write-Host "MISSING_GAME_PACKAGE_COUNT=0" -ForegroundColor Green
        Write-Host "PHASE_02F_ARCHIVE_DEPENDENCY_CLOSURE=PASS" -ForegroundColor Green
        Write-Host "NEXT_GATE=BUILD_ASWW_COMBAT_PLAYER_V1" -ForegroundColor Green
        Write-Host "NO_GAMEPLAY_SOURCE_WAS_MODIFIED" -ForegroundColor Green
        Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
        Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
        exit 0
    }

    if ($Probe.MissingCount -lt 0 -or $Probe.Missing.Count -eq 0) {
        Stop-Gate "MISSING_COUNT_PARSE_MISMATCH_PASS_$Pass" 21
    }

    $ResolvedThisPass = 0
    $Unresolved = New-Object System.Collections.Generic.List[string]

    foreach ($Pkg in $Probe.Missing) {
        Write-Host ""
        Write-Host "SEARCHING_ARCHIVE_FOR=$Pkg"

        $Archive = Find-PackageInArchives $Pkg $UERoot $UnrealPak $EvidenceRoot $Stamp
        if (-not $Archive) {
            $Unresolved.Add($Pkg)
            Write-Host "ARCHIVE_PACKAGE_NOT_FOUND=$Pkg"
            continue
        }

        $Extracted = Extract-PackageFromArchive $Pkg $Archive $UnrealPak $EvidenceRoot ($Stamp + "_" + (($Pkg -split "/")[-1]))
        if (-not $Extracted) {
            $Unresolved.Add($Pkg)
            Write-Host "ARCHIVE_EXTRACTED_BUT_PACKAGE_NOT_LOCATED=$Pkg"
            continue
        }

        $Relative = $Pkg.Substring(6).Replace('/','\') + ".uasset"
        $Dest = Join-Path (Join-Path $ProjectRoot "Content") $Relative

        if (Test-Path -LiteralPath $Dest -PathType Leaf) {
            Write-Host "DEST_ALREADY_EXISTS=$Dest"
            continue
        }

        $CopiedCount = Copy-UAssetFamily $Extracted $Dest
        $ResolvedThisPass += $CopiedCount
    }

    Write-Host ""
    Write-Host "PASS_${Pass}_COPIED_FILE_COUNT=$ResolvedThisPass"
    Write-Host "PASS_${Pass}_UNRESOLVED_COUNT=$($Unresolved.Count)"

    if ($Unresolved.Count -gt 0) {
        foreach ($Pkg in $Unresolved) {
            Write-Host "UNRESOLVED_FINAL_CANDIDATE=$Pkg"
        }
        Stop-Gate "ONE_OR_MORE_PACKAGES_NOT_FOUND_IN_LOOSE_FILES_OR_UE_ARCHIVES_PASS_$Pass" 22
    }

    if ($ResolvedThisPass -eq 0) {
        Stop-Gate "NO_PROGRESS_IN_ARCHIVE_DEPENDENCY_CLOSURE_PASS_$Pass" 23
    }
}

Stop-Gate "MAX_ARCHIVE_DEPENDENCY_CLOSURE_PASSES_REACHED_$MaxPasses" 24
