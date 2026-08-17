param([Parameter(Mandatory=$true)][string]$ClientExe)
$Server="$PSScriptRoot\..\BuildOutput\Server\WindowsServer\ArabiaStrikeWorldWarServer.exe"
if (!(Test-Path $Server)) { throw "Dedicated server executable not found. Build server first." }
Start-Process $Server -ArgumentList "/Game/Maps/Jeddah_RedSea_Assault?listen -log -port=7777"
Start-Sleep -Seconds 2
Start-Process $ClientExe -ArgumentList "127.0.0.1:7777 -windowed -ResX=1280 -ResY=720"
Start-Process $ClientExe -ArgumentList "127.0.0.1:7777 -windowed -ResX=1280 -ResY=720"
