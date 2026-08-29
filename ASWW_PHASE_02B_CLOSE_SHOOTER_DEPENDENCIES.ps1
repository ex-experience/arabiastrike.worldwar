[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\Phase02B_ShooterDependencies"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "PHASE_02B_SHOOTER_DEPENDENCIES=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_GAMEPLAY_SOURCE_WAS_MODIFIED" -ForegroundColor Green
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
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"

foreach ($Required in @($ProjectFile,$EditorCmd)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_REQUIRED_FILE_$Required" 11
    }
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Py = Join-Path $EvidenceRoot "phase02b_dependency_closure_$Stamp.py"
$Out = Join-Path $EvidenceRoot "phase02b_dependency_closure_$Stamp.stdout.log"
$Err = Join-Path $EvidenceRoot "phase02b_dependency_closure_$Stamp.stderr.log"

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

def package_exists(pkg):
    try:
        assets = registry.get_assets_by_package_name(pkg)
        return len(assets) > 0
    except Exception:
        return False

print("ASWW_P02B_BEGIN=True")

all_missing = set()

for pkg in targets:
    print(f"ASWW_P02B_TARGET={pkg}")
    exists = package_exists(pkg)
    print(f"ASWW_P02B_TARGET_EXISTS|PACKAGE={pkg}|EXISTS={exists}")

    try:
        deps = registry.get_dependencies(pkg, opts)
    except Exception as exc:
        print(f"ASWW_P02B_DEP_ENUM_ERROR|PACKAGE={pkg}|ERR={exc}")
        continue

    print(f"ASWW_P02B_DEP_COUNT|PACKAGE={pkg}|COUNT={len(deps)}")

    for dep in deps:
        dep_s = str(dep)
        if dep_s.startswith("/Script/") or dep_s.startswith("/Engine/"):
            print(f"ASWW_P02B_DEP|OWNER={pkg}|DEP={dep_s}|SCOPE=ENGINE_OR_SCRIPT")
            continue

        if dep_s.startswith("/Game/"):
            ok = package_exists(dep_s)
            print(f"ASWW_P02B_DEP|OWNER={pkg}|DEP={dep_s}|SCOPE=GAME|EXISTS={ok}")
            if not ok:
                all_missing.add(dep_s)
        else:
            print(f"ASWW_P02B_DEP|OWNER={pkg}|DEP={dep_s}|SCOPE=OTHER")

print(f"ASWW_P02B_MISSING_GAME_PACKAGE_COUNT={len(all_missing)}")
for dep in sorted(all_missing):
    print(f"ASWW_P02B_MISSING_GAME_PACKAGE={dep}")

# Test only three critical loads after dependency enumeration.
# Avoid the broad blueprint load loop that caused Phase 02A to exit abnormally.
critical_objects = [
    "/Game/Variant_Shooter/Blueprints/BP_ShooterCharacter.BP_ShooterCharacter",
    "/Game/Variant_Shooter/Blueprints/BP_ShooterPlayerController.BP_ShooterPlayerController",
    "/Game/Variant_Shooter/Blueprints/BP_ShooterGameMode.BP_ShooterGameMode",
]

for obj_path in critical_objects:
    obj = None
    try:
        obj = unreal.load_asset(obj_path)
    except Exception as exc:
        print(f"ASWW_P02B_CRITICAL_LOAD_ERROR|PATH={obj_path}|ERR={exc}")

    print(f"ASWW_P02B_CRITICAL_LOAD|PATH={obj_path}|LOAD={obj is not None}")

    if obj:
        gen = None
        # Blueprint.generated_class() is not consistently exposed in UE Python.
        # Try multiple safe APIs and report capability rather than assuming failure.
        try:
            gen = obj.generated_class()
        except Exception:
            pass

        if gen is None:
            try:
                gen = obj.get_editor_property("generated_class")
            except Exception:
                pass

        print(
            f"ASWW_P02B_CRITICAL_GENERATED_CLASS|PATH={obj_path}|"
            f"CLASS={gen.get_name() if gen else 'UNAVAILABLE_FROM_PYTHON_API'}"
        )

print("ASWW_P02B_END=True")
'@

[IO.File]::WriteAllText($Py, $PyText, [Text.UTF8Encoding]::new($false))
$PyForward = $Py.Replace('\','/')

$Args = @(
    $ProjectFile
    "-unattended"
    "-nop4"
    "-nosplash"
    "-NullRHI"
    "-stdout"
    "-FullStdOutLogOutput"
    "-ExecutePythonScript=$PyForward"
)

& $EditorCmd @Args 1> $Out 2> $Err
$Exit = $LASTEXITCODE

$StdoutText = ""
$StderrText = ""

if (Test-Path -LiteralPath $Out) {
    $StdoutText = Get-Content -Raw -LiteralPath $Out
    Select-String -LiteralPath $Out -Pattern "ASWW_P02B_" |
        ForEach-Object { Write-Host $_.Line }
}

if (Test-Path -LiteralPath $Err) {
    $StderrText = Get-Content -Raw -LiteralPath $Err
}

$Combined = $StdoutText + "`n" + $StderrText

$ScriptFinished = $Combined -match "ASWW_P02B_END=True"
$PythonError = $Combined -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$FatalLine = $Combined -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"
$MissingCountMatch = [regex]::Match($Combined, "ASWW_P02B_MISSING_GAME_PACKAGE_COUNT=(\d+)")
$MissingCount = if ($MissingCountMatch.Success) { [int]$MissingCountMatch.Groups[1].Value } else { -1 }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PROCESS / ERROR CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "UNREAL_EDITOR_CMD_EXIT=$Exit"
Write-Host "PYTHON_SCRIPT_FINISHED=$ScriptFinished"
Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "EXPLICIT_FATAL_LINE_SEEN=$FatalLine"
Write-Host "MISSING_GAME_PACKAGE_COUNT=$MissingCount"

if ($Exit -ne 0 -or $PythonError -or $FatalLine) {
    Write-Host ""
    Write-Host "=== STDERR TAIL ===" -ForegroundColor Yellow
    if (Test-Path -LiteralPath $Err) {
        Get-Content -LiteralPath $Err -Tail 120
    }
    Write-Host ""
    Write-Host "=== STDOUT TAIL ===" -ForegroundColor Yellow
    if (Test-Path -LiteralPath $Out) {
        Get-Content -LiteralPath $Out -Tail 160
    }
}

if (-not $ScriptFinished) {
    Stop-Gate "DEPENDENCY_SCRIPT_DID_NOT_FINISH" 20
}

if ($PythonError) {
    Stop-Gate "PYTHON_ERROR_DURING_DEPENDENCY_AUDIT" 21
}

if ($FatalLine) {
    Stop-Gate "EXPLICIT_UNREAL_FATAL_DURING_DEPENDENCY_AUDIT" 22
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PHASE 02B CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if ($MissingCount -eq 0) {
    Write-Host "SHOOTER_DEPENDENCY_CLOSURE=PASS" -ForegroundColor Green

    if ($Exit -eq 0) {
        Write-Host "UNREAL_HEADLESS_EXIT=PASS" -ForegroundColor Green
        Write-Host "PHASE_02B_SHOOTER_DEPENDENCIES=PASS" -ForegroundColor Green
        Write-Host "NEXT_GATE=BUILD_ASWW_COMBAT_PLAYER_V1" -ForegroundColor Green
    }
    else {
        # A nonzero exit after the Python script fully completed, without an explicit
        # fatal line or Python error, is reported separately instead of falsely
        # invalidating the verified asset dependency closure.
        Write-Host "UNREAL_HEADLESS_EXIT=NONZERO_AFTER_SCRIPT_COMPLETION" -ForegroundColor Yellow
        Write-Host "PHASE_02B_SHOOTER_DEPENDENCIES=PASS_DEPENDENCIES_PROCESS_EXIT_NEEDS_REVIEW" -ForegroundColor Yellow
        Write-Host "NEXT_GATE=REVIEW_STDERR_TAIL_THEN_BUILD_ASWW_COMBAT_PLAYER_V1_IF_NO_REAL_FATAL" -ForegroundColor Yellow
    }
}
elseif ($MissingCount -gt 0) {
    Write-Host "SHOOTER_DEPENDENCY_CLOSURE=FAIL_MISSING_GAME_PACKAGES" -ForegroundColor Yellow
    Write-Host "PHASE_02B_SHOOTER_DEPENDENCIES=PARTIAL" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=IMPORT_ONLY_LISTED_MISSING_GAME_PACKAGES" -ForegroundColor Yellow
}
else {
    Stop-Gate "MISSING_DEPENDENCY_COUNT_NOT_PARSED" 23
}

& git diff --check
$DiffExit = $LASTEXITCODE
Write-Host "GIT_DIFF_CHECK_EXIT=$DiffExit"

Write-Host "NO_GAMEPLAY_SOURCE_WAS_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
