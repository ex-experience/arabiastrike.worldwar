[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\Phase02E_QuinnClosure",
    [int]$MaxPasses = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_02E_QUINN_CLOSURE=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_GAMEPLAY_SOURCE_WAS_MODIFIED" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Read-UAssetStrings([string]$Path) {
    $Bytes = [IO.File]::ReadAllBytes($Path)
    return ([Text.Encoding]::ASCII.GetString($Bytes) + "`n" + [Text.Encoding]::Unicode.GetString($Bytes))
}

function Get-ContentRelativePackage([string]$FilePath) {
    $File = Get-Item -LiteralPath $FilePath
    $Dir = $File.Directory
    while ($Dir) {
        if ($Dir.Name -ieq "Content") {
            $Rel = $File.FullName.Substring($Dir.FullName.Length).TrimStart('\','/')
            $NoExt = [IO.Path]::ChangeExtension($Rel, $null).Replace('\','/')
            return "/Game/" + $NoExt
        }
        $Dir = $Dir.Parent
    }
    return ""
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

function Resolve-ExactPackage([string]$PackagePath, [string]$UERoot) {
    $AssetName = ($PackagePath -split "/")[-1]
    $Candidates = @(
        Get-ChildItem -LiteralPath $UERoot -Recurse -File -Filter ($AssetName + ".uasset") -ErrorAction SilentlyContinue
    )

    Write-Host "CANDIDATE_COUNT|PACKAGE=$PackagePath|COUNT=$($Candidates.Count)"

    $Ranked = New-Object System.Collections.Generic.List[object]

    foreach ($Candidate in $Candidates) {
        $ContentPkg = Get-ContentRelativePackage $Candidate.FullName
        $EmbeddedExact = $false

        try {
            $Strings = Read-UAssetStrings $Candidate.FullName
            $EmbeddedExact = $Strings.IndexOf($PackagePath, [StringComparison]::OrdinalIgnoreCase) -ge 0
        }
        catch {}

        $Score = 0
        if ($ContentPkg -ieq $PackagePath) { $Score += 1000 }
        if ($EmbeddedExact) { $Score += 500 }
        if ($Candidate.FullName -match "\\Templates\\") { $Score += 100 }
        if ($Candidate.FullName -match "\\TemplateResources\\") { $Score += 80 }
        if ($Candidate.FullName -match "\\FeaturePacks\\") { $Score += 60 }

        $Ranked.Add([pscustomobject]@{
            Score=$Score
            Path=$Candidate.FullName
            ContentPackage=$ContentPkg
            EmbeddedExact=$EmbeddedExact
        })
    }

    $Ranked = @($Ranked | Sort-Object -Property @{Expression='Score';Descending=$true}, @{Expression='Path';Descending=$false})

    $i = 0
    foreach ($R in $Ranked | Select-Object -First 20) {
        $i++
        Write-Host ("PACKAGE_CANDIDATE_{0}|TARGET={1}|SCORE={2}|CONTENT_PACKAGE={3}|EMBEDDED_EXACT={4}|PATH={5}" -f
            $i,$PackagePath,$R.Score,$R.ContentPackage,$R.EmbeddedExact,$R.Path)
    }

    if ($Ranked.Count -eq 0) { return $null }

    $Best = $Ranked[0]
    if ($Best.Score -lt 500) {
        return $null
    }

    return $Best.Path
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
            print(f"ASWW_P02E_DEP_ENUM_ERROR|OWNER={owner}|ERR={exc}")
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

print(f"ASWW_P02E_VISITED_COUNT={len(visited)}")
print(f"ASWW_P02E_MISSING_COUNT={len(missing)}")
for pkg in sorted(missing):
    print(f"ASWW_P02E_MISSING={pkg}")

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
        print(f"ASWW_P02E_CRITICAL_LOAD_ERROR|PATH={obj_path}|ERR={exc}")
    print(f"ASWW_P02E_CRITICAL_LOAD|PATH={obj_path}|LOAD={obj is not None}")

print("ASWW_P02E_PROBE_DONE=True")
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
        Select-String -LiteralPath $Out -Pattern "ASWW_P02E_" |
            ForEach-Object { Write-Host $_.Line }
    }
    if (Test-Path -LiteralPath $Err) {
        $Combined += "`n" + (Get-Content -Raw -LiteralPath $Err)
    }

    $Done = $Combined -match "ASWW_P02E_PROBE_DONE=True"
    $PythonError = $Combined -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
    $Fatal = $Combined -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

    $Missing = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($Combined, "ASWW_P02E_MISSING=([^\r\n]+)")) {
        $Missing.Add($m.Groups[1].Value.Trim())
    }

    $CountMatch = [regex]::Match($Combined, "ASWW_P02E_MISSING_COUNT=(\d+)")
    $Count = if ($CountMatch.Success) { [int]$CountMatch.Groups[1].Value } else { -1 }

    return [pscustomobject]@{
        Exit = $Exit
        Done = $Done
        PythonError = $PythonError
        Fatal = $Fatal
        Missing = $Missing
        MissingCount = $Count
        Out = $Out
        Err = $Err
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

foreach ($Required in @($ProjectFile,$EditorCmd)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " EXACT SEARCH FOR CURRENT QUINN BLOCKER" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$QuinnPackage = "/Game/Characters/Heroes/Mannequin/Meshes/SKM_Quinn"
$QuinnSource = Resolve-ExactPackage $QuinnPackage $UERoot

if (-not $QuinnSource) {
    Stop-Gate "EXACT_SK_QUINN_PACKAGE_NOT_FOUND_ANYWHERE_UNDER_UE_ROOT" 20
}

Write-Host "QUINN_EXACT_SOURCE=$QuinnSource"

$QuinnDest = Join-Path $ProjectRoot "Content\Characters\Heroes\Mannequin\Meshes\SKM_Quinn.uasset"
if (-not (Test-Path -LiteralPath $QuinnDest -PathType Leaf)) {
    $Copied = Copy-UAssetFamily $QuinnSource $QuinnDest
    Write-Host "QUINN_FILE_FAMILY_COPIED=$Copied"
}
else {
    Write-Host "QUINN_DEST_ALREADY_EXISTS=True"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FINISH RECURSIVE SHOOTER DEPENDENCY CLOSURE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

for ($Pass = 1; $Pass -le $MaxPasses; $Pass++) {
    $Stamp = (Get-Date -Format "yyyyMMdd_HHmmss") + "_P$Pass"
    $Probe = Invoke-ClosureProbe $EditorCmd $ProjectFile $EvidenceRoot $Stamp

    Write-Host "PASS=$Pass"
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
        Stop-Gate "DEPENDENCY_PROBE_NOT_TRUSTWORTHY_PASS_$Pass" 21
    }

    if ($Probe.MissingCount -eq 0) {
        & git diff --check
        $DiffExit = $LASTEXITCODE
        Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"

        Write-Host ""
        Write-Host "SHOOTER_RECURSIVE_DEPENDENCY_CLOSURE=PASS" -ForegroundColor Green
        Write-Host "MISSING_GAME_PACKAGE_COUNT=0" -ForegroundColor Green
        Write-Host "PHASE_02E_QUINN_CLOSURE=PASS" -ForegroundColor Green
        Write-Host "NEXT_GATE=BUILD_ASWW_COMBAT_PLAYER_V1" -ForegroundColor Green
        Write-Host "NO_GAMEPLAY_SOURCE_WAS_MODIFIED" -ForegroundColor Green
        Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
        Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
        exit 0
    }

    if ($Probe.MissingCount -lt 0 -or $Probe.Missing.Count -eq 0) {
        Stop-Gate "MISSING_COUNT_PARSE_MISMATCH_PASS_$Pass" 22
    }

    $ResolvedThisPass = 0
    $Unresolved = New-Object System.Collections.Generic.List[string]

    foreach ($Pkg in $Probe.Missing) {
        $Source = Resolve-ExactPackage $Pkg $UERoot

        if (-not $Source) {
            $Unresolved.Add($Pkg)
            Write-Host "UNRESOLVED_PACKAGE=$Pkg"
            continue
        }

        Write-Host "RESOLVED_PACKAGE|PACKAGE=$Pkg|SOURCE=$Source"

        $Relative = $Pkg.Substring(6).Replace('/','\') + ".uasset"
        $Dest = Join-Path (Join-Path $ProjectRoot "Content") $Relative

        if (Test-Path -LiteralPath $Dest -PathType Leaf) {
            Write-Host "DEST_ALREADY_EXISTS=$Dest"
            continue
        }

        $CopiedCount = Copy-UAssetFamily $Source $Dest
        $ResolvedThisPass += $CopiedCount
    }

    Write-Host "PASS_${Pass}_COPIED_FILE_COUNT=$ResolvedThisPass"
    Write-Host "PASS_${Pass}_UNRESOLVED_COUNT=$($Unresolved.Count)"

    if ($Unresolved.Count -gt 0) {
        foreach ($Pkg in $Unresolved) {
            Write-Host "UNRESOLVED_FINAL_CANDIDATE=$Pkg"
        }
        Stop-Gate "UNRESOLVED_TEMPLATE_PACKAGES_REMAIN_PASS_$Pass" 23
    }

    if ($ResolvedThisPass -eq 0) {
        Stop-Gate "NO_PROGRESS_IN_DEPENDENCY_CLOSURE_PASS_$Pass" 24
    }
}

Stop-Gate "MAX_DEPENDENCY_CLOSURE_PASSES_REACHED_$MaxPasses" 25
