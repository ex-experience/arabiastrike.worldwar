# Build and Run

## Editor

Use Unreal Engine 5.8. The host must also have Visual Studio 2022 (or Build Tools) with the MSVC x64 C++ toolchain and Windows SDK 10.0.19041.0 or newer. Check the complete host before invoking Unreal:

```powershell
.\BuildScripts\check_ue58_host.ps1 -UERoot "D:\\UE_5.8"
```

Run the full gated recovery pipeline after the host check passes:

```powershell
.\BuildScripts\run_ue58_pipeline.ps1 -UERoot "D:\\UE_5.8"
```

This sequence performs static gates, real Editor/client/server builds, real Editor-authored Jeddah map generation and validation, a bounded PIE startup smoke, packaging and multiplayer prerequisite checks. Each later stage is skipped if an earlier real gate fails.

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

## Dual delivery validation

Web zero-install and native delivery share the same Unreal gameplay project and are gated independently. See `docs/DELIVERY_TRACKS.md` for Win64, Android, iOS, and Pixel Streaming prerequisites.

```powershell
.\BuildScripts\verify_delivery_tracks.ps1 -UERoot "D:\\UE_5.8"
```

## Pixel Streaming 2 local infrastructure

The engine plugin ships an infrastructure fetch helper, not a running signalling/frontend stack. Audit readiness without downloading:

```powershell
.\BuildScripts\prepare_pixel_streaming2_stack.ps1 -UERoot "D:\\UE_5.8"
```

When network bandwidth is available, fetch Epic's official UE5.8 branch into the ignored `LocalInfrastructure/` directory. Starting the stack is a separate explicit action:

```powershell
.\BuildScripts\prepare_pixel_streaming2_stack.ps1 -UERoot "D:\\UE_5.8" -DownloadOfficialUE58
.\BuildScripts\prepare_pixel_streaming2_stack.ps1 -UERoot "D:\\UE_5.8" -Start -VisibleWindow
```

The default local frontend is `http://127.0.0.1:8080/` and the streamer endpoint is `ws://127.0.0.1:8888`. A successful process/TCP check is not WebRTC gameplay evidence.

## GitHub Actions

`repository-preflight` runs on GitHub-hosted runners and does not pretend to compile Unreal.

`unreal-5-8-self-hosted-build` requires a Windows self-hosted runner labelled `Unreal-5.8`, with `UE_ROOT` configured and Unreal installed/licensed in your environment.
