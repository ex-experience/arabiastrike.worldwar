[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [switch]$LaunchEditorForManualQA
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Banner([string]$Text) {
    Write-Host ""
    Write-Host ("=" * 74) -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ("=" * 74) -ForegroundColor Cyan
}

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "OFFLINE_PHASE2=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

function Save-Checkpoint([string]$Label) {
    $Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $Root = Join-Path $ProjectRoot "Saved\OfflineCheckpoint\${Label}_$Stamp"
    $Files = Join-Path $Root "files"
    New-Item -ItemType Directory -Force -Path $Files | Out-Null

    $Branch = (& git -C $ProjectRoot branch --show-current).Trim()
    $Head = (& git -C $ProjectRoot rev-parse HEAD).Trim()

    @(
        "LABEL=$Label"
        "TIME=$(Get-Date -Format o)"
        "BRANCH=$Branch"
        "HEAD=$Head"
        "PROJECT_ROOT=$ProjectRoot"
    ) | Set-Content -LiteralPath (Join-Path $Root "CHECKPOINT.txt") -Encoding UTF8

    & git -C $ProjectRoot status --porcelain=v1 | Set-Content -LiteralPath (Join-Path $Root "git_status.txt") -Encoding UTF8
    & git -c core.safecrlf=false -C $ProjectRoot diff --binary | Set-Content -LiteralPath (Join-Path $Root "working_tree.patch") -Encoding UTF8
    & git -c core.safecrlf=false -C $ProjectRoot diff --cached --binary | Set-Content -LiteralPath (Join-Path $Root "index.patch") -Encoding UTF8
    & git -c core.safecrlf=false -C $ProjectRoot diff --stat | Set-Content -LiteralPath (Join-Path $Root "diff_stat.txt") -Encoding UTF8
    & git -C $ProjectRoot ls-files --others --exclude-standard | Set-Content -LiteralPath (Join-Path $Root "untracked.txt") -Encoding UTF8

    $Changed = @()
    $Changed += @(& git -c core.safecrlf=false -C $ProjectRoot diff --name-only)
    $Changed += @(& git -c core.safecrlf=false -C $ProjectRoot diff --cached --name-only)
    $Changed += @(& git -C $ProjectRoot ls-files --others --exclude-standard)
    $Changed = $Changed | Where-Object { $_ } | Sort-Object -Unique

    foreach ($Rel in $Changed) {
        $Src = Join-Path $ProjectRoot $Rel
        if (Test-Path -LiteralPath $Src -PathType Leaf) {
            $Dst = Join-Path $Files $Rel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dst) | Out-Null
            Copy-Item -LiteralPath $Src -Destination $Dst -Force
        }
    }

    try {
        & git -C $ProjectRoot bundle create (Join-Path $Root "repository_history.bundle") HEAD *> $null
    } catch {}

    Write-Host "CHECKPOINT=$Root" -ForegroundColor Green
    return $Root
}

Banner "ASWW OFFLINE PHASE 2 — POST EDITOR+GAME PASS"

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    Stop-Gate "PROJECT_ROOT_NOT_FOUND" 10
}
Set-Location $ProjectRoot

$Branch = (& git branch --show-current).Trim()
$Head = (& git rev-parse HEAD).Trim()
Write-Host "BRANCH=$Branch"
Write-Host "LOCAL_HEAD=$Head"

if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 11
}

foreach ($Required in @(
    (Join-Path $UERoot "Engine\Build\Build.version"),
    (Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor.exe"),
    (Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"),
    (Join-Path $UERoot "Engine\Build\BatchFiles\RunUAT.bat")
)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Gate "MISSING_LOCAL_DEPENDENCY_$Required" 12
    }
}

$V = Get-Content -Raw -LiteralPath (Join-Path $UERoot "Engine\Build\Build.version") | ConvertFrom-Json
$UEVersion = "$($V.MajorVersion).$($V.MinorVersion).$($V.PatchVersion)"
Write-Host "UE_VERSION=$UEVersion"
if ($V.MajorVersion -ne 5 -or $V.MinorVersion -ne 8) {
    Stop-Gate "UE_5_8_REQUIRED_FOUND_$UEVersion" 13
}

Banner "VERIFY SAVED EDITOR + GAME PASS CHECKPOINT"

$SavedPass = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "Saved\OfflineCheckpoint") -Directory -Filter "EDITOR_GAME_PASS_*" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $SavedPass) {
    Stop-Gate "EDITOR_GAME_PASS_CHECKPOINT_NOT_FOUND" 14
}

$SavedPassText = Join-Path $SavedPass.FullName "CHECKPOINT.txt"
if (-not (Test-Path -LiteralPath $SavedPassText)) {
    Stop-Gate "CHECKPOINT_FILE_MISSING" 15
}

$CheckpointText = Get-Content -Raw -LiteralPath $SavedPassText
if ($CheckpointText -notmatch "EDITOR_BUILD=PASS" -or $CheckpointText -notmatch "GAME_BUILD=PASS") {
    Stop-Gate "CHECKPOINT_DOES_NOT_PROVE_EDITOR_AND_GAME_PASS" 16
}

Write-Host "EDITOR_BUILD=PASS_FROM_SAVED_CHECKPOINT" -ForegroundColor Green
Write-Host "GAME_BUILD=PASS_FROM_SAVED_CHECKPOINT" -ForegroundColor Green
Write-Host "SOURCE_CHECKPOINT=$($SavedPass.FullName)"

Banner "GIT SAFETY REVIEW — NO PAGER / NO COMMIT"

$Unmerged = @(& git diff --name-only --diff-filter=U)
if ($Unmerged.Count -gt 0) {
    $Unmerged | ForEach-Object { Write-Host "UNMERGED=$_ " -ForegroundColor Red }
    Stop-Gate "UNMERGED_GIT_PATHS_PRESENT" 20
}

& git -c core.safecrlf=false diff --check
if ($LASTEXITCODE -ne 0) {
    Stop-Gate "GIT_DIFF_CHECK_FAILED" 21
}

Write-Host "=== git status --short ==="
& git status --short
Write-Host ""
Write-Host "=== git diff --stat ==="
& git -c core.safecrlf=false --no-pager diff --stat

$PreRuntimeCheckpoint = Save-Checkpoint "BEFORE_JEDDAH_RUNTIME_PIPELINE"
Write-Host "AUTO_COMMIT=DISABLED" -ForegroundColor Yellow
Write-Host "REASON=LOCAL_DIFF_REVIEW_REQUIRED_BEFORE_COMMIT"

Banner "GATE 1 — GENERATE REAL JEDDAH UMAP"

$GenerateMap = Join-Path $ProjectRoot "BuildScripts\generate_jeddah_map.ps1"
if (-not (Test-Path -LiteralPath $GenerateMap)) {
    Stop-Gate "MISSING_generate_jeddah_map.ps1" 30
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $GenerateMap -UERoot $UERoot
$MapGenExit = $LASTEXITCODE
Write-Host "MAP_GENERATION_EXIT=$MapGenExit"
if ($MapGenExit -ne 0) {
    Stop-Gate "MAP_GENERATION_FAIL_EXIT_$MapGenExit" $MapGenExit
}

$MapPath = Join-Path $ProjectRoot "Content\Maps\Jeddah_RedSea_Assault.umap"
if (-not (Test-Path -LiteralPath $MapPath -PathType Leaf)) {
    Stop-Gate "JEDDAH_UMAP_NOT_CREATED" 31
}
Write-Host "JEDDAH_UMAP=$MapPath" -ForegroundColor Green

Banner "GATE 2 — VALIDATE JEDDAH THROUGH REAL UNREAL EDITOR API"

$ValidateMap = Join-Path $ProjectRoot "BuildScripts\validate_jeddah_map.ps1"
if (-not (Test-Path -LiteralPath $ValidateMap)) {
    Stop-Gate "MISSING_validate_jeddah_map.ps1" 32
}

$ValidationCapture = Join-Path $ProjectRoot "Saved\Verification\Local\offline_phase2_map_validate.txt"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ValidateMap -UERoot $UERoot 2>&1 |
    Tee-Object -FilePath $ValidationCapture
$MapValidateExit = $LASTEXITCODE
if ($MapValidateExit -ne 0) {
    Stop-Gate "MAP_VALIDATION_FAIL_EXIT_$MapValidateExit" $MapValidateExit
}

$ValidationLine = Get-Content -LiteralPath $ValidationCapture |
    Where-Object { $_ -like "MAP_VALIDATION_LOG=*" } |
    Select-Object -Last 1

if (-not $ValidationLine) {
    Stop-Gate "MAP_VALIDATION_LOG_NOT_REPORTED" 33
}
$ValidationLog = $ValidationLine.Substring("MAP_VALIDATION_LOG=".Length)
Write-Host "MAP_VALIDATION_LOG=$ValidationLog" -ForegroundColor Green
Write-Host "MAP_VALIDATION=PASS" -ForegroundColor Green

Banner "GATE 3 — PROMOTE JEDDAH AS DEFAULT MAP"

$PromoteMap = Join-Path $ProjectRoot "BuildScripts\promote_jeddah_default_map.ps1"
if (-not (Test-Path -LiteralPath $PromoteMap)) {
    Stop-Gate "MISSING_promote_jeddah_default_map.ps1" 34
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PromoteMap -ValidationLog $ValidationLog
$PromoteExit = $LASTEXITCODE
if ($PromoteExit -ne 0) {
    Stop-Gate "MAP_PROMOTION_FAIL_EXIT_$PromoteExit" $PromoteExit
}
Write-Host "MAP_PROMOTION=PASS" -ForegroundColor Green

$MapCheckpoint = Save-Checkpoint "JEDDAH_MAP_VALIDATED_AND_PROMOTED"

Banner "GATE 4 — AUTOMATED PIE STARTUP SMOKE"

$Pie = Join-Path $ProjectRoot "BuildScripts\run_jeddah_pie_smoke.ps1"
if (-not (Test-Path -LiteralPath $Pie)) {
    Stop-Gate "MISSING_run_jeddah_pie_smoke.ps1" 40
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Pie -UERoot $UERoot -TimeoutSeconds 600
$PieExit = $LASTEXITCODE
if ($PieExit -ne 0) {
    Stop-Gate "PIE_STARTUP_SMOKE_FAIL_EXIT_$PieExit" $PieExit
}
Write-Host "PIE_STARTUP_SMOKE=PASS" -ForegroundColor Green
Write-Host "PIE_SCOPE=STARTUP_POSSESSION_ACTOR_PRESENCE_ONLY" -ForegroundColor Yellow
Write-Host "FULL_GAMEPLAY_MATRIX=NOT_PROVEN_BY_THIS_AUTOMATION" -ForegroundColor Yellow

Banner "GATE 5 — PACKAGE WIN64 DEVELOPMENT"

$Package = Join-Path $ProjectRoot "BuildScripts\build_win64.ps1"
if (-not (Test-Path -LiteralPath $Package)) {
    Stop-Gate "MISSING_build_win64.ps1" 50
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Package -UERoot $UERoot -Configuration Development
$PackageExit = $LASTEXITCODE
if ($PackageExit -ne 0) {
    Stop-Gate "WIN64_PACKAGE_FAIL_EXIT_$PackageExit" $PackageExit
}

$PackageRoot = Join-Path $ProjectRoot "BuildOutput\Client"
$Exe = Get-ChildItem -LiteralPath $PackageRoot -Recurse -File -Filter "ArabiaStrikeWorldWar.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch "\\Engine\\Binaries\\" } |
    Sort-Object FullName |
    Select-Object -First 1

if (-not $Exe) {
    Stop-Gate "PACKAGED_EXE_NOT_FOUND_AFTER_UAT_PASS" 51
}
Write-Host "WIN64_PACKAGE=PASS" -ForegroundColor Green
Write-Host "WIN64_EXE=$($Exe.FullName)"

Banner "GATE 6 — PACKAGED EXE PROCESS STARTUP SMOKE"

$NativeEvidence = Join-Path $ProjectRoot "Saved\RuntimeEvidence\Native"
New-Item -ItemType Directory -Force -Path $NativeEvidence | Out-Null
$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$RuntimeLog = Join-Path $NativeEvidence "packaged_startup_$RunStamp.log"

$RuntimeArgs = @(
    "-windowed",
    "-ResX=1280",
    "-ResY=720",
    "-log",
    "-abslog=$RuntimeLog"
)

$Proc = Start-Process -FilePath $Exe.FullName -ArgumentList $RuntimeArgs -WorkingDirectory $Exe.DirectoryName -PassThru
Start-Sleep -Seconds 30

if ($Proc.HasExited) {
    $Proc.Refresh()
    Stop-Gate "PACKAGED_RUNTIME_EXITED_EARLY_CODE_$($Proc.ExitCode)" 52
}

Write-Host "WIN64_RUNTIME_PROCESS_START=PASS_30_SECONDS" -ForegroundColor Green
Write-Host "WIN64_RUNTIME_LOG=$RuntimeLog"
Stop-Process -Id $Proc.Id -Force -ErrorAction SilentlyContinue
$Proc.WaitForExit(5000) | Out-Null

Banner "GATE 7 — MULTIPLAYER / SERVER TRUTHFUL STATUS"

Write-Host "SERVER_BUILD=BLOCKED_BY_EPIC_INSTALLED_ENGINE" -ForegroundColor Yellow
Write-Host "MULTIPLAYER_2P=NOT_PROVEN" -ForegroundColor Yellow
Write-Host "MULTIPLAYER_4P=NOT_PROVEN" -ForegroundColor Yellow
Write-Host "REASON=NO_VERIFIED_PACKAGED_DEDICATED_SERVER_AND_NO_MANUAL_LISTEN_SESSION_TEST_YET"

Banner "GATE 8 — PIXEL STREAMING OFFLINE STATUS"

$InfraRoot = Join-Path $ProjectRoot "LocalInfrastructure\PixelStreamingInfrastructure-UE5.8"
$StartBat = Join-Path $InfraRoot "SignallingWebServer\platform_scripts\cmd\start.bat"

if (Test-Path -LiteralPath $StartBat -PathType Leaf) {
    Write-Host "PIXEL_STREAMING_INFRASTRUCTURE=FOUND_LOCAL" -ForegroundColor Green
    Write-Host "PIXEL_STREAMING_CAN_BE_TESTED_OFFLINE_LOCALLY=YES" -ForegroundColor Green
    Write-Host "WEBRTC_SESSION=NOT_RUN_BY_PHASE2" -ForegroundColor Yellow
} else {
    Write-Host "PIXEL_STREAMING_INFRASTRUCTURE=NOT_FOUND_LOCAL" -ForegroundColor Yellow
    Write-Host "PIXEL_STREAMING_OFFLINE_TEST=BLOCKED_UNTIL_INFRASTRUCTURE_IS_PRELOADED" -ForegroundColor Yellow
    Write-Host "NO_DOWNLOAD_ATTEMPTED=YES" -ForegroundColor Green
}

$Final = Save-Checkpoint "PHASE2_AUTOMATED_GATES_COMPLETE"

$Summary = Join-Path $Final "PHASE2_SUMMARY.txt"
@(
    "TIME=$(Get-Date -Format o)"
    "BRANCH=$Branch"
    "LOCAL_HEAD=$Head"
    "UE_VERSION=$UEVersion"
    "EDITOR_BUILD=PASS_FROM_PRIOR_CHECKPOINT"
    "GAME_BUILD=PASS_FROM_PRIOR_CHECKPOINT"
    "JEDDAH_UMAP=$MapPath"
    "MAP_VALIDATION=PASS"
    "MAP_PROMOTION=PASS"
    "PIE_STARTUP_SMOKE=PASS_STARTUP_ONLY"
    "WIN64_PACKAGE=PASS"
    "WIN64_RUNTIME_PROCESS_START=PASS_30_SECONDS"
    "SERVER_BUILD=BLOCKED_BY_EPIC_INSTALLED_ENGINE"
    "MULTIPLAYER_2P=NOT_PROVEN"
    "MULTIPLAYER_4P=NOT_PROVEN"
    "FULL_GAMEPLAY_QA=MANUAL_NOT_PROVEN"
    "GIT_COMMIT=NOT_CREATED"
    "GIT_PUSH=NOT_ATTEMPTED"
    "INTERNET_REQUIRED_BY_THIS_SCRIPT=NO"
) | Set-Content -LiteralPath $Summary -Encoding UTF8

Banner "PHASE 2 COMPLETE"
Write-Host "OFFLINE_PHASE2=AUTOMATED_GATES_COMPLETE" -ForegroundColor Green
Write-Host "FINAL_CHECKPOINT=$Final" -ForegroundColor Green
Write-Host "SUMMARY=$Summary" -ForegroundColor Green

if ($LaunchEditorForManualQA) {
    Banner "OPTIONAL — LAUNCH UNREAL EDITOR FOR MANUAL GAMEPLAY QA"
    $Editor = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor.exe"
    Start-Process -FilePath $Editor -ArgumentList @(
        "$ProjectRoot\ArabiaStrikeWorldWar.uproject",
        "/Game/Maps/Jeddah_RedSea_Assault"
    ) -WorkingDirectory $ProjectRoot
    Write-Host "EDITOR_MANUAL_QA=LAUNCHED" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "NEXT_MANUAL_GATE=RUN_WITH_-LaunchEditorForManualQA_OR_OPEN_EDITOR_MANUALLY" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
Write-Host "NO_COMMIT_OR_PUSH_WAS_PERFORMED" -ForegroundColor Green
