# Build and Run

## Editor

Use Unreal Engine 5.8. Open the `.uproject`, let Unreal generate project files, then compile the Editor target.

## Local multiplayer

PIE recommendation for the first test:

- Number of Players: 2–4.
- Net Mode: Play As Client.
- Run Dedicated Server: enabled.

## Packaged client

```powershell
.\BuildScripts\build_win64.ps1 -UERoot "D:\\UE_5.8"
```

## Dedicated server

```powershell
.\BuildScripts\build_server_win64.ps1 -UERoot "D:\\UE_5.8"
```

A dedicated server build may require an Unreal Engine source build/toolchain appropriate to your environment and target.

## GitHub Actions

`repository-preflight` runs on GitHub-hosted runners and does not pretend to compile Unreal.

`unreal-5-8-self-hosted-build` requires a Windows self-hosted runner labelled `Unreal-5.8`, with `UE_ROOT` configured and Unreal installed/licensed in your environment.
