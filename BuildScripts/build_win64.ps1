param(
  [Parameter(Mandatory=$true)][string]$UERoot,
  [string]$Configuration="Development"
)
$ErrorActionPreference="Stop"
$Project=(Resolve-Path "$PSScriptRoot\..\ArabiaStrikeWorldWar.uproject").Path
$UAT=Join-Path $UERoot "Engine\Build\BatchFiles\RunUAT.bat"
& $UAT BuildCookRun -project="$Project" -noP4 -platform=Win64 -clientconfig=$Configuration -build -cook -stage -pak -archive -archivedirectory="$PSScriptRoot\..\BuildOutput\Client"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
