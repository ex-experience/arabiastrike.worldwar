[CmdletBinding()]
param(
    [ValidateSet(2, 4, 8)][int]$PlayerCount = 2,
    [string]$ServerExecutable,
    [string]$ClientExecutable,
    [string]$MapPackage = "/Game/Maps/Jeddah_RedSea_Assault",
    [ValidateRange(1, 65535)][int]$ServerPort = 7777,
    [ValidateRange(10, 3600)][int]$RunDurationSeconds = 120,
    [ValidateRange(1, 60)][int]$ServerStartupSeconds = 3,
    [switch]$HeadlessClients,
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$StartedProcesses = [System.Collections.Generic.List[Diagnostics.Process]]::new()
$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$LogRoot = Join-Path $ProjectRoot "Saved\RuntimeEvidence\Multiplayer\$RunId"

function Find-PackagedExecutable {
    param(
        [string]$RequestedPath,
        [string]$SearchRoot,
        [string]$FileName
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (-not [IO.File]::Exists($RequestedPath)) {
            throw "Requested executable was not found: '$RequestedPath'."
        }
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }
    if (-not [IO.Directory]::Exists($SearchRoot)) {
        return $null
    }
    $Artifact = Get-ChildItem -LiteralPath $SearchRoot -Recurse -File -Filter $FileName -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\Engine\\Binaries\\' } |
        Sort-Object FullName |
        Select-Object -First 1
    if ($Artifact) {
        return $Artifact.FullName
    }
    return $null
}

if (-not $MapPackage.StartsWith("/Game/", [StringComparison]::Ordinal) -or $MapPackage.Contains("..")) {
    throw "MapPackage must be a safe /Game/... package path."
}
$MapRelativePath = $MapPackage.Substring(6).Replace('/', [IO.Path]::DirectorySeparatorChar) + ".umap"
$MapAssetPath = Join-Path (Join-Path $ProjectRoot "Content") $MapRelativePath

$ServerExecutable = Find-PackagedExecutable $ServerExecutable (Join-Path $ProjectRoot "BuildOutput\Server") "ArabiaStrikeWorldWarServer.exe"
$ClientExecutable = Find-PackagedExecutable $ClientExecutable (Join-Path $ProjectRoot "BuildOutput\Client") "ArabiaStrikeWorldWar.exe"

$MissingPrerequisites = [System.Collections.Generic.List[string]]::new()
if (-not [IO.File]::Exists($MapAssetPath)) {
    $MissingPrerequisites.Add("real map asset '$MapAssetPath'")
}
if ([string]::IsNullOrWhiteSpace($ServerExecutable) -or -not [IO.File]::Exists($ServerExecutable)) {
    $MissingPrerequisites.Add("packaged dedicated server executable")
}
if ([string]::IsNullOrWhiteSpace($ClientExecutable) -or -not [IO.File]::Exists($ClientExecutable)) {
    $MissingPrerequisites.Add("packaged Win64 client executable")
}

Write-Output "PLAYER_COUNT=$PlayerCount"
Write-Output "SERVER_PORT=$ServerPort"
Write-Output "MAP_PACKAGE=$MapPackage"
Write-Output "MAP_ASSET=$(if ([IO.File]::Exists($MapAssetPath)) { $MapAssetPath } else { 'NOT_FOUND' })"
Write-Output "SERVER_EXECUTABLE=$(if ($ServerExecutable) { $ServerExecutable } else { 'NOT_FOUND' })"
Write-Output "CLIENT_EXECUTABLE=$(if ($ClientExecutable) { $ClientExecutable } else { 'NOT_FOUND' })"
Write-Output "VALIDATION_SCOPE=PREREQUISITES_AND_PROCESS_LIFECYCLE_ONLY"
Write-Output "GAMEPLAY_RESULT=NOT_TESTED_BY_HARNESS"

if ($MissingPrerequisites.Count -gt 0) {
    foreach ($Missing in $MissingPrerequisites) {
        Write-Output "BLOCKER=$Missing"
    }
    Write-Output "MULTIPLAYER_HARNESS_RESULT=BLOCKED_MISSING_PREREQUISITES"
    exit 2
}
if ($ValidateOnly) {
    Write-Output "MULTIPLAYER_HARNESS_RESULT=PASS_PREREQUISITES_ONLY"
    exit 0
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$ServerLog = Join-Path $LogRoot "server.log"
$ServerArguments = @(
    "${MapPackage}?listen",
    "-port=$ServerPort",
    "-log",
    "-abslog=$ServerLog",
    "-unattended",
    "-stdout",
    "-FullStdOutLogOutput"
)

try {
    Write-Output "SERVER_LOG=$ServerLog"
    Write-Output "SERVER_COMMAND=`"$ServerExecutable`" $($ServerArguments -join ' ')"
    $ServerProcess = Start-Process -FilePath $ServerExecutable -ArgumentList $ServerArguments -WorkingDirectory ([IO.Path]::GetDirectoryName($ServerExecutable)) -WindowStyle Hidden -PassThru
    $StartedProcesses.Add($ServerProcess)
    if ($ServerProcess.WaitForExit($ServerStartupSeconds * 1000)) {
        $ServerProcess.Refresh()
        throw "Dedicated server exited during startup with code $($ServerProcess.ExitCode). See '$ServerLog'."
    }

    for ($ClientIndex = 1; $ClientIndex -le $PlayerCount; $ClientIndex += 1) {
        $ClientLog = Join-Path $LogRoot ("client_{0:D2}.log" -f $ClientIndex)
        $ClientArguments = @(
            "127.0.0.1:$ServerPort",
            "-windowed",
            "-ResX=1280",
            "-ResY=720",
            "-WinX=$((($ClientIndex - 1) % 2) * 640)",
            "-WinY=$([Math]::Floor(($ClientIndex - 1) / 2) * 360)",
            "-log",
            "-abslog=$ClientLog"
        )
        if ($HeadlessClients) {
            $ClientArguments += @("-RenderOffscreen", "-Unattended")
        }

        Write-Output "CLIENT_${ClientIndex}_LOG=$ClientLog"
        Write-Output "CLIENT_${ClientIndex}_COMMAND=`"$ClientExecutable`" $($ClientArguments -join ' ')"
        $ClientProcessParameters = @{
            FilePath = $ClientExecutable
            ArgumentList = $ClientArguments
            WorkingDirectory = [IO.Path]::GetDirectoryName($ClientExecutable)
            PassThru = $true
        }
        if ($HeadlessClients) {
            $ClientProcessParameters.WindowStyle = "Hidden"
        }
        $ClientProcess = Start-Process @ClientProcessParameters
        $StartedProcesses.Add($ClientProcess)
    }

    Write-Output "PROCESS_LIFECYCLE=RUNNING_FOR_${RunDurationSeconds}_SECONDS"
    $Deadline = [DateTime]::UtcNow.AddSeconds($RunDurationSeconds)
    while ([DateTime]::UtcNow -lt $Deadline) {
        foreach ($StartedProcess in $StartedProcesses) {
            if ($StartedProcess.HasExited) {
                $StartedProcess.Refresh()
                throw "Process $($StartedProcess.Id) exited before the harness timeout with code $($StartedProcess.ExitCode). Review the separated logs under '$LogRoot'."
            }
        }
        Start-Sleep -Milliseconds 500
    }

    Write-Output "MULTIPLAYER_HARNESS_RESULT=COMPLETED_PROCESS_WINDOW_NOT_GAMEPLAY_VERIFIED"
    Write-Output "EVIDENCE_LOG_ROOT=$LogRoot"
}
finally {
    foreach ($StartedProcess in $StartedProcesses) {
        if (-not $StartedProcess.HasExited) {
            Stop-Process -Id $StartedProcess.Id -Force -ErrorAction SilentlyContinue
            $StartedProcess.WaitForExit(5000) | Out-Null
        }
    }
    Write-Output "PROCESS_CLEANUP=COMPLETE"
}

exit 0
