[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ClientExe)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Requires PixelStreaming2 plugin enabled and a signalling server deployment.
# Do not expose signalling infrastructure without authentication/origin controls.
if (-not [IO.File]::Exists($ClientExe)) {
    throw "Packaged client executable was not found: '$ClientExe'."
}
& $ClientExe -AudioMixer -RenderOffscreen -PixelStreamingURL=ws://127.0.0.1:8888
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
exit 0
