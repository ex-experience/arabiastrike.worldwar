# Dual Delivery Tracks

ARABIA STRIKE uses one Unreal Engine 5.8 project and one `ArabiaStrikeWorldWar` runtime module. Web and native delivery are deployment surfaces around that shared authoritative gameplay core, not gameplay forks.

## Track A — Web zero-install

`Web/` is a GitHub Pages launcher. It provides a repository-subpath-safe, responsive entry point, an explicit `OFFLINE → CHECKING → REACHABLE → NEGOTIATING → CONNECTED` session model with bounded reconnect/failure paths, and a single `PIXEL_STREAMING_URL` value that points at the deployed Pixel Streaming frontend. The launcher recognizes touch, keyboard/mouse-capable pointers, and connected gamepads; the Pixel Streaming frontend and Unreal application remain responsible for transporting and consuming gameplay input.

`REACHABLE` means only that the frontend endpoint responded. A generic iframe load is not a gameplay connection. `CONNECTED` requires an origin-, source-, schema- and session-validated `ASWW_PIXEL_STREAMING_STATE` message from the embedded frontend. See `docs/PIXEL_STREAMING.md` for the bridge contract.

Run the web delivery gate:

```powershell
python ci/preflight_web_delivery.py
```

GitHub Pages publishes only `Web/`. A Pages deployment does not host the Unreal executable, signalling server, or Pixel Streaming media stack.

## Track B — Native

Native milestones must be verified in order:

1. Win64 packaged client and dedicated server.
2. Android APK/AAB using UE 5.8's Android toolchain.
3. iOS IPA using macOS/Xcode or Unreal's Windows-to-Mac remote build path.

All packaging scripts target `ArabiaStrikeWorldWar.uproject`:

```powershell
.\BuildScripts\build_win64.ps1 -UERoot "D:\UE_5.8"
.\BuildScripts\build_android.ps1 -UERoot "D:\UE_5.8" -OutputFormat APK
.\BuildScripts\build_android.ps1 -UERoot "D:\UE_5.8" -Configuration Shipping -OutputFormat AAB -ForDistribution
.\BuildScripts\build_ios.ps1 -UERoot "D:\UE_5.8" -Configuration Shipping -ForDistribution
```

The Android path requires the UE 5.8-compatible SDK, NDK, and JDK configured through Turnkey. The iOS path for this C++ project requires a Mac with compatible Xcode plus valid Apple signing and provisioning; Windows builds use Unreal's preconfigured remote Mac settings. The scripts do not collect credentials or claim success unless the expected package artifact exists.

`-OutputFormat` is an artifact assertion, not a hidden project mutation: select APK or Android App Bundle in Unreal's Android project settings before running the matching command. This keeps packaging configuration reviewable in the shared project.

## Independent verification

Run both gates and produce an explicit result for each track:

```powershell
.\BuildScripts\verify_delivery_tracks.ps1 -UERoot "D:\UE_5.8"
```

The command exits non-zero unless Track A passes and Track B has real UE compile evidence plus a packaged Win64 client. Missing engine, map, package, SDK, signing, or runtime evidence is reported as a blocker rather than treated as success.
