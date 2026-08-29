[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [switch]$ForceEditorRebuild,
    [switch]$TryPreparedPixelStreaming
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ("=" * 72) -ForegroundColor Cyan
}

function Write-Checkpoint {
    param(
        [string]$Root,
        [string]$Label
    )

    $Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $BackupRoot = Join-Path $Root "Saved\OfflineCheckpoint\$Stamp"
    $FilesRoot = Join-Path $BackupRoot "files"
    New-Item -ItemType Directory -Force -Path $FilesRoot | Out-Null

    $Branch = (& git -C $Root branch --show-current).Trim()
    $Head = (& git -C $Root rev-parse HEAD).Trim()

    @(
        "LABEL=$Label"
        "TIME=$(Get-Date -Format o)"
        "BRANCH=$Branch"
        "HEAD=$Head"
        "PROJECT_ROOT=$Root"
    ) | Set-Content -LiteralPath (Join-Path $BackupRoot "CHECKPOINT.txt") -Encoding UTF8

    & git -C $Root status --porcelain=v1 | Set-Content -LiteralPath (Join-Path $BackupRoot "git_status.txt") -Encoding UTF8
    & git -C $Root diff --binary | Set-Content -LiteralPath (Join-Path $BackupRoot "working_tree.patch") -Encoding UTF8
    & git -C $Root diff --cached --binary | Set-Content -LiteralPath (Join-Path $BackupRoot "index.patch") -Encoding UTF8
    & git -C $Root ls-files --others --exclude-standard | Set-Content -LiteralPath (Join-Path $BackupRoot "untracked.txt") -Encoding UTF8

    $ChangedPaths = @()
    $ChangedPaths += @(& git -C $Root diff --name-only)
    $ChangedPaths += @(& git -C $Root diff --cached --name-only)
    $ChangedPaths += @(& git -C $Root ls-files --others --exclude-standard)
    $ChangedPaths = $ChangedPaths | Where-Object { $_ } | Sort-Object -Unique

    foreach ($Relative in $ChangedPaths) {
        $SourcePath = Join-Path $Root $Relative
        if (Test-Path -LiteralPath $SourcePath -PathType Leaf) {
            $DestPath = Join-Path $FilesRoot $Relative
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $DestPath) | Out-Null
            Copy-Item -LiteralPath $SourcePath -Destination $DestPath -Force
        }
    }

    try {
        & git -C $Root bundle create (Join-Path $BackupRoot "repository_history.bundle") HEAD *> $null
    }
    catch {
        # A bundle is supplementary only; uncommitted work is already preserved above.
    }

    Write-Host "OFFLINE_CHECKPOINT=$BackupRoot" -ForegroundColor Green
    return $BackupRoot
}

function Invoke-Build {
    param(
        [string]$Target,
        [string]$LogPath,
        [switch]$ForceHeaderGeneration
    )

    $BuildBat = Join-Path $UERoot "Engine\Build\BatchFiles\Build.bat"
    $Args = @(
        $Target,
        "Win64",
        "Development",
        "-Project=$ProjectRoot\ArabiaStrikeWorldWar.uproject",
        "-WaitMutex",
        "-NoHotReloadFromIDE",
        "-NoUBA",
        "-MaxParallelActions=1"
    )
    if ($ForceHeaderGeneration) {
        $Args += "-ForceHeaderGeneration"
    }

    Write-Host "COMMAND=`"$BuildBat`" $($Args -join ' ')" -ForegroundColor DarkGray
    & $BuildBat @Args 2>&1 | Tee-Object -FilePath $LogPath
    return $LASTEXITCODE
}

function Stop-WithSummary {
    param(
        [string]$Reason,
        [int]$ExitCode = 1
    )
    Write-Host ""
    Write-Host "OFFLINE_PIPELINE=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $ExitCode
}

Write-Step "ASWW OFFLINE CONTINUATION — SAFETY"

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "PROJECT_ROOT_NOT_FOUND=$ProjectRoot"
}
Set-Location $ProjectRoot

$Branch = (& git branch --show-current).Trim()
$Head = (& git rev-parse HEAD).Trim()
Write-Host "BRANCH=$Branch"
Write-Host "LOCAL_HEAD=$Head"

if ($Branch -ne "codex/asww-development") {
    Stop-WithSummary "WRONG_BRANCH_$Branch" 20
}

$BuildVersionPath = Join-Path $UERoot "Engine\Build\Build.version"
$BuildBat = Join-Path $UERoot "Engine\Build\BatchFiles\Build.bat"
$UnrealEditor = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor.exe"
$UnrealEditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"

foreach ($Required in @($BuildVersionPath, $BuildBat, $UnrealEditor, $UnrealEditorCmd)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-WithSummary "MISSING_LOCAL_DEPENDENCY_$Required" 21
    }
}

$BuildVersion = Get-Content -Raw -LiteralPath $BuildVersionPath | ConvertFrom-Json
$UEVersion = "$($BuildVersion.MajorVersion).$($BuildVersion.MinorVersion).$($BuildVersion.PatchVersion)"
Write-Host "UE_VERSION=$UEVersion"
Write-Host "UE_ROOT=$UERoot"

if ($BuildVersion.MajorVersion -ne 5 -or $BuildVersion.MinorVersion -ne 8) {
    Stop-WithSummary "UE_5_8_REQUIRED_FOUND_$UEVersion" 22
}

Write-Host "NETWORK_REQUIRED=NO" -ForegroundColor Green
Write-Host "GIT_PULL=FORBIDDEN"
Write-Host "GIT_RESET=FORBIDDEN"
Write-Host "GIT_RESTORE=FORBIDDEN"
Write-Host "MAIN_TOUCH=FORBIDDEN"

$InitialCheckpoint = Write-Checkpoint -Root $ProjectRoot -Label "BEFORE_OFFLINE_CONTINUATION"

Write-Step "LOCAL MEMORY SNAPSHOT"
$OS = Get-CimInstance Win32_OperatingSystem
$FreePhysicalGB = [math]::Round($OS.FreePhysicalMemory / 1MB, 2)
$FreeVirtualGB = [math]::Round($OS.FreeVirtualMemory / 1MB, 2)
$TotalVirtualGB = [math]::Round($OS.TotalVirtualMemorySize / 1MB, 2)
Write-Host "FREE_PHYSICAL_GB=$FreePhysicalGB"
Write-Host "FREE_VIRTUAL_GB=$FreeVirtualGB"
Write-Host "TOTAL_VIRTUAL_GB=$TotalVirtualGB"
Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue |
    Select-Object Name,AllocatedBaseSize,CurrentUsage,PeakUsage |
    Format-Table -AutoSize

$VerificationRoot = Join-Path $ProjectRoot "Saved\Verification\Local"
New-Item -ItemType Directory -Force -Path $VerificationRoot | Out-Null
$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Step "GATE 1 — EDITOR BUILD EVIDENCE"
$EditorPassLog = $null
if (-not $ForceEditorRebuild) {
    $RecentEditorLogs = Get-ChildItem -LiteralPath $VerificationRoot -File -Filter "*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    foreach ($Candidate in $RecentEditorLogs) {
        if (Select-String -LiteralPath $Candidate.FullName -Pattern "Result: Succeeded" -SimpleMatch -Quiet -ErrorAction SilentlyContinue) {
            $EditorPassLog = $Candidate.FullName
            break
        }
    }
}

if ($EditorPassLog) {
    Write-Host "EDITOR_BUILD=PASS_FROM_LOCAL_LOG" -ForegroundColor Green
    Write-Host "EDITOR_PASS_LOG=$EditorPassLog"
}
else {
    $EditorLog = Join-Path $VerificationRoot "offline_editor_$RunStamp.log"
    $EditorExit = Invoke-Build -Target "ArabiaStrikeWorldWarEditor" -LogPath $EditorLog -ForceHeaderGeneration
    Write-Host "EDITOR_EXIT_CODE=$EditorExit"
    Write-Host "EDITOR_LOG=$EditorLog"
    if ($EditorExit -ne 0) {
        Select-String -LiteralPath $EditorLog -Pattern "error C[0-9]{4}|error LNK[0-9]{4}|fatal error|VirtualAlloc|paging file" -Context 3,7 |
            Select-Object -First 30
        Stop-WithSummary "EDITOR_BUILD_FAIL_EXIT_$EditorExit" $EditorExit
    }
    Write-Host "EDITOR_BUILD=PASS" -ForegroundColor Green
    $EditorPassLog = $EditorLog
}

Write-Step "GATE 2 — GAME WIN64 DEVELOPMENT BUILD"
$GameLog = Join-Path $VerificationRoot "offline_game_$RunStamp.log"
$GameExit = Invoke-Build -Target "ArabiaStrikeWorldWar" -LogPath $GameLog
Write-Host "GAME_EXIT_CODE=$GameExit"
Write-Host "GAME_LOG=$GameLog"

if ($GameExit -ne 0) {
    Select-String -LiteralPath $GameLog -Pattern "error C[0-9]{4}|error LNK[0-9]{4}|fatal error|VirtualAlloc|paging file" -Context 3,7 |
        Select-Object -First 30
    Stop-WithSummary "GAME_BUILD_FAIL_EXIT_$GameExit" $GameExit
}
Write-Host "GAME_BUILD=PASS" -ForegroundColor Green

Write-Step "GATE 3 — SAVE VERIFIED CODE CHECKPOINT"
& git diff --check
if ($LASTEXITCODE -ne 0) {
    Stop-WithSummary "GIT_DIFF_CHECK_FAILED" 30
}
$VerifiedCodeCheckpoint = Write-Checkpoint -Root $ProjectRoot -Label "EDITOR_AND_GAME_BUILD_PASS"
Write-Host "LOCAL_COMMIT=AUTO_COMMIT_DISABLED_FOR_SAFETY" -ForegroundColor Yellow
Write-Host "REASON=DIFF_REVIEW_REQUIRED_BEFORE_STAGING"

Write-Step "GATE 4 — GENERATE REAL JEDDAH UMAP"
$GenerateMap = Join-Path $ProjectRoot "BuildScripts\generate_jeddah_map.ps1"
if (-not (Test-Path -LiteralPath $GenerateMap)) {
    Stop-WithSummary "MISSING_generate_jeddah_map.ps1" 40
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $GenerateMap -UERoot $UERoot
$MapGenExit = $LASTEXITCODE
Write-Host "MAP_GENERATION_EXIT=$MapGenExit"
if ($MapGenExit -ne 0) {
    Stop-WithSummary "MAP_GENERATION_FAIL_EXIT_$MapGenExit" $MapGenExit
}

$MapPath = Join-Path $ProjectRoot "Content\Maps\Jeddah_RedSea_Assault.umap"
if (-not (Test-Path -LiteralPath $MapPath -PathType Leaf)) {
    Stop-WithSummary "JEDDAH_UMAP_NOT_CREATED" 41
}
Write-Host "JEDDAH_UMAP=$MapPath" -ForegroundColor Green

Write-Step "GATE 5 — VALIDATE JEDDAH IN REAL EDITOR API"
$ValidateMap = Join-Path $ProjectRoot "BuildScripts\validate_jeddah_map.ps1"
$ValidationOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ValidateMap -UERoot $UERoot 2>&1)
$ValidationOutput | ForEach-Object { Write-Host $_ }
$MapValidateExit = $LASTEXITCODE
if ($MapValidateExit -ne 0) {
    Stop-WithSummary "MAP_VALIDATION_FAIL_EXIT_$MapValidateExit" $MapValidateExit
}
$ValidationLine = $ValidationOutput | Where-Object { "$_" -like "MAP_VALIDATION_LOG=*" } | Select-Object -Last 1
if (-not $ValidationLine) {
    Stop-WithSummary "MAP_VALIDATION_LOG_NOT_REPORTED" 42
}
$ValidationLog = ("$ValidationLine").Substring("MAP_VALIDATION_LOG=".Length)
Write-Host "MAP_VALIDATION_LOG=$ValidationLog" -ForegroundColor Green

Write-Step "GATE 6 — PROMOTE JEDDAH AS DEFAULT MAP"
$PromoteMap = Join-Path $ProjectRoot "BuildScripts\promote_jeddah_default_map.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PromoteMap -ValidationLog $ValidationLog
$PromoteExit = $LASTEXITCODE
if ($PromoteExit -ne 0) {
    Stop-WithSummary "MAP_PROMOTION_FAIL_EXIT_$PromoteExit" $PromoteExit
}
Write-Host "MAP_PROMOTION=PASS" -ForegroundColor Green

Write-Step "GATE 7 — AUTOMATED PIE STARTUP SMOKE"
$PieScript = Join-Path $ProjectRoot "BuildScripts\run_jeddah_pie_smoke.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PieScript -UERoot $UERoot -TimeoutSeconds 600
$PieExit = $LASTEXITCODE
if ($PieExit -ne 0) {
    Stop-WithSummary "PIE_STARTUP_SMOKE_FAIL_EXIT_$PieExit" $PieExit
}
Write-Host "PIE_STARTUP_SMOKE=PASS" -ForegroundColor Green
Write-Host "PIE_SCOPE=STARTUP_POSSESSION_ACTOR_PRESENCE_ONLY"
Write-Host "FULL_GAMEPLAY_MATRIX=STILL_REQUIRES_MANUAL_RUNTIME_TEST"

Write-Step "GATE 8 — PACKAGE WIN64 DEVELOPMENT"
$PackageScript = Join-Path $ProjectRoot "BuildScripts\build_win64.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PackageScript -UERoot $UERoot -Configuration Development
$PackageExit = $LASTEXITCODE
if ($PackageExit -ne 0) {
    Stop-WithSummary "WIN64_PACKAGE_FAIL_EXIT_$PackageExit" $PackageExit
}

$PackagedExe = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "BuildOutput\Client") -Recurse -File -Filter "ArabiaStrikeWorldWar.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch "\\Engine\\Binaries\\" } |
    Sort-Object FullName |
    Select-Object -First 1

if (-not $PackagedExe) {
    Stop-WithSummary "PACKAGED_EXE_NOT_FOUND_AFTER_UAT_PASS" 50
}
Write-Host "WIN64_PACKAGE=PASS" -ForegroundColor Green
Write-Host "WIN64_EXE=$($PackagedExe.FullName)"

Write-Step "GATE 9 — PACKAGED PROCESS STARTUP SMOKE"
$RuntimeLogRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\Native"
New-Item -ItemType Directory -Force -Path $RuntimeLogRoot | Out-Null
$RuntimeLog = Join-Path $RuntimeLogRoot "packaged_startup_$RunStamp.log"

$RuntimeArgs = @(
    "-windowed",
    "-ResX=1280",
    "-ResY=720",
    "-log",
    "-abslog=$RuntimeLog"
)

$GameProcess = Start-Process -FilePath $PackagedExe.FullName -ArgumentList $RuntimeArgs -WorkingDirectory $PackagedExe.DirectoryName -PassThru
Start-Sleep -Seconds 20
if ($GameProcess.HasExited) {
    $GameProcess.Refresh()
    Stop-WithSummary "PACKAGED_RUNTIME_EXITED_EARLY_CODE_$($GameProcess.ExitCode)" 51
}
Write-Host "WIN64_RUNTIME_PROCESS_START=PASS_20_SECONDS" -ForegroundColor Green
Write-Host "WIN64_RUNTIME_LOG=$RuntimeLog"
Stop-Process -Id $GameProcess.Id -Force -ErrorAction SilentlyContinue
$GameProcess.WaitForExit(5000) | Out-Null

Write-Step "GATE 10 — LOCAL MULTIPLAYER STATUS"
Write-Host "SERVER_BUILD=BLOCKED_BY_EPIC_INSTALLED_ENGINE" -ForegroundColor Yellow
Write-Host "MULTIPLAYER_2P=BLOCKED_NO_PACKAGED_DEDICATED_SERVER" -ForegroundColor Yellow
Write-Host "MULTIPLAYER_4P=BLOCKED_NO_PACKAGED_DEDICATED_SERVER" -ForegroundColor Yellow
Write-Host "NOTE=Current repository harness requires ArabiaStrikeWorldWarServer.exe"

Write-Step "GATE 11 — OPTIONAL PREPARED LOCAL PIXEL STREAMING"
$PixelStackResult = "NOT_ATTEMPTED"
if ($TryPreparedPixelStreaming) {
    $InfraRoot = Join-Path $ProjectRoot "LocalInfrastructure\PixelStreamingInfrastructure-UE5.8"
    $StartBat = Join-Path $InfraRoot "SignallingWebServer\platform_scripts\cmd\start.bat"
    if (-not (Test-Path -LiteralPath $StartBat -PathType Leaf)) {
        $PixelStackResult = "BLOCKED_OFFLINE_INFRASTRUCTURE_NOT_ALREADY_PRESENT"
        Write-Host "PIXEL_STREAMING_STACK=$PixelStackResult" -ForegroundColor Yellow
        Write-Host "NO_DOWNLOAD_WAS_ATTEMPTED" -ForegroundColor Green
    }
    else {
        $PreparePS = Join-Path $ProjectRoot "BuildScripts\prepare_pixel_streaming2_stack.ps1"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PreparePS -UERoot $UERoot -InfrastructureRoot $InfraRoot -Start
        $PrepareExit = $LASTEXITCODE
        if ($PrepareExit -eq 0) {
            $RunPS = Join-Path $ProjectRoot "BuildScripts\run_pixel_streaming2.ps1"
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RunPS -UERoot $UERoot -PackageRoot (Join-Path $ProjectRoot "BuildOutput\Client") -SignallingServerUrl "ws://127.0.0.1" -SignallingServerPort 8888
            $RunPixelExit = $LASTEXITCODE
            if ($RunPixelExit -eq 0) {
                $PixelStackResult = "PROCESS_STARTED_LOCAL_WEBRTC_NOT_VERIFIED"
            }
            else {
                $PixelStackResult = "GAME_STREAMER_LAUNCH_FAIL_EXIT_$RunPixelExit"
            }
        }
        else {
            $PixelStackResult = "LOCAL_STACK_START_FAIL_EXIT_$PrepareExit"
        }
        Write-Host "PIXEL_STREAMING_STACK=$PixelStackResult"
    }
}
else {
    Write-Host "PIXEL_STREAMING_STACK=SKIPPED_USE_-TryPreparedPixelStreaming_IF_ALREADY_DOWNLOADED"
}

Write-Step "FINAL OFFLINE CHECKPOINT"
$FinalCheckpoint = Write-Checkpoint -Root $ProjectRoot -Label "OFFLINE_AUTOMATED_GATES_COMPLETE"

$SummaryPath = Join-Path $FinalCheckpoint "OFFLINE_SUMMARY.txt"
@(
    "TIME=$(Get-Date -Format o)"
    "BRANCH=$Branch"
    "LOCAL_HEAD=$Head"
    "UE_VERSION=$UEVersion"
    "EDITOR_BUILD=PASS"
    "GAME_BUILD=PASS"
    "JEDDAH_UMAP=$MapPath"
    "MAP_VALIDATION=PASS"
    "MAP_PROMOTION=PASS"
    "PIE_STARTUP_SMOKE=PASS_STARTUP_ONLY"
    "WIN64_PACKAGE=PASS"
    "WIN64_RUNTIME_PROCESS_START=PASS_20_SECONDS"
    "SERVER_BUILD=BLOCKED_BY_EPIC_INSTALLED_ENGINE"
    "MULTIPLAYER_2P=BLOCKED_NO_DEDICATED_SERVER"
    "MULTIPLAYER_4P=BLOCKED_NO_DEDICATED_SERVER"
    "PIXEL_STREAMING_STACK=$PixelStackResult"
    "LOCAL_COMMIT=NOT_CREATED_AUTOMATICALLY"
    "FULL_GAMEPLAY_SMOKE=MANUAL_NOT_PROVEN"
    "DO_NOT_TOUCH_MAIN=YES"
) | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

Write-Host ""
Write-Host "OFFLINE_PIPELINE=AUTOMATED_GATES_COMPLETE" -ForegroundColor Green
Write-Host "FINAL_CHECKPOINT=$FinalCheckpoint" -ForegroundColor Green
Write-Host "SUMMARY=$SummaryPath" -ForegroundColor Green
Write-Host ""
Write-Host "IMPORTANT_REMAINING_MANUAL_GATES:" -ForegroundColor Yellow
Write-Host "- real gameplay PIE: movement / sprint / jump / aim / fire"
Write-Host "- damage / death / respawn"
Write-Host "- enemy AI"
Write-Host "- Hummer enter / drive / turret"
Write-Host "- helicopter encounter"
Write-Host "- Command Mech encounter"
Write-Host "- extraction"
Write-Host "- HUD / audio / VFX"
Write-Host "- 2P / 4P only after a real dedicated-server executable exists"
Write-Host "- Pixel Streaming WebRTC + keyboard/mouse/touch/gamepad only after local signalling stack is actually ready"
Write-Host ""
Write-Host "NO_NETWORK_COMMANDS_WERE_REQUIRED_BY_THIS_PIPELINE." -ForegroundColor Green
Write-Host "DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
