param([Parameter(Mandatory=$true)][string]$ClientExe)
# Requires PixelStreaming2 plugin enabled and a signalling server deployment.
# Do not expose signalling infrastructure without authentication/origin controls.
& $ClientExe -AudioMixer -RenderOffscreen -PixelStreamingURL=ws://127.0.0.1:8888
