# Runtime Evidence Protocol

This directory defines how ARABIA STRIKE runtime results are recorded. It is not evidence that any test has run. Generated logs, captures, screenshots, packages and profiling data belong under the ignored `Saved/RuntimeEvidence/` tree or an external artifact store; do not commit them here.

## Allowed result states

- `PASS`: the named behavior was observed in the required real topology and evidence was retained.
- `FAIL`: the test ran and the named behavior did not meet its acceptance criteria.
- `NOT_TESTED`: prerequisites may exist, but no valid execution has been performed.
- `BLOCKED`: a named prerequisite prevents the test from starting.

Never infer runtime success from static checks, compilation, an iframe load or a process remaining alive.

## Evidence record

For every execution, record:

1. UTC and local timestamp, branch and exact commit SHA.
2. Unreal version, host OS/GPU/driver, build configuration and executable hash.
3. Exact command, map package, server topology, player count and network conditions.
4. One result state per acceptance item, with expected and observed behavior.
5. Exact local/log artifact paths, relevant timestamps and issue link for every failure.
6. Cleanup result, including whether every process started by the harness exited.

Do not record credentials, access tokens, player personal data or private service URLs.

## Gameplay and delivery matrix

Current values describe the repository at the time this protocol was added; they must be replaced only by evidence from an actual run.

| Area | Required observation | Current state |
|---|---|---|
| Startup | Packaged client reaches its initial project map without fatal errors | BLOCKED — no UE/package |
| Jeddah map load | Real `Jeddah_RedSea_Assault.umap` loads | BLOCKED — map missing |
| Movement | 360 movement, sprint and jump respond | NOT_TESTED |
| Combat | Aim, fire, replicated ammo, reload and grenade | NOT_TESTED |
| Damage lifecycle | Damage, downed, revive, bleedout, death and authoritative respawn | NOT_TESTED |
| Enemy encounter | Detection, navigation, combat, damage and death | NOT_TESTED |
| Vehicles | Hummer driving/turret, helicopter and vehicle damage | NOT_TESTED |
| Boss/extraction | Command Mech phases and replicated extraction completion | NOT_TESTED |
| 2-player | Join/leave, combat, revive, respawn and replicated mission state | BLOCKED — no package/map |
| 4-player | Same acceptance surface with four clients | BLOCKED — no package/map |
| 8-player | Capacity, relevance and authoritative state with eight clients | BLOCKED — no package/map |
| Disconnect/reconnect | Session interruption and bounded recovery without duplicate pawns | NOT_TESTED |
| Pixel Streaming | Signalling, WebRTC media/input and launcher `CONNECTED` bridge | BLOCKED — no backend/package |
| Desktop input | Keyboard/mouse through a real WebRTC session | NOT_TESTED |
| Touch input | iPhone and Android touch through a real WebRTC session | NOT_TESTED |
| Gamepad input | Browser gamepad through a real WebRTC session | NOT_TESTED |

## Multiplayer harness review

`BuildScripts/run_local_multiplayer.ps1` can prepare 2, 4 or 8 clients against one dedicated server, with isolated logs and bounded cleanup. Its process-lifecycle result is not gameplay proof. During a real run, an operator must evaluate:

- player join and leave;
- authoritative damage and replicated ammo;
- downed, revive, death and respawn;
- vehicle possession and replicated movement;
- boss phase/state replication;
- mission and extraction state replication;
- client disconnect and reconnect behavior.

## Performance and soak plan

Performance capture remains `NOT_TESTED` until a real Win64 build and Jeddah map exist. Capture Unreal Insights and CSV profiler data for:

- client FPS and frame-time percentiles;
- game thread, render thread and GPU frame time;
- VRAM and system RAM peaks;
- map loading duration and World Partition streaming hitches;
- server frame time, actor count, bandwidth and replication pressure at 2, 4 and 8 players;
- browser input latency, decoded frame rate, bitrate and reconnect time for Pixel Streaming.

Run a short controlled capture first, then a sustained soak with a declared duration and workload. A soak passes only when logs show no crash, fatal error, unbounded memory growth, stuck session or orphan process. Current performance and soak results are `NOT_TESTED`.
