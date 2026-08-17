# JEDDAH — RED SEA ASSAULT / Vertical Slice 01

## Playable loop

Spawn at a Red Sea urban checkpoint → street firefight → rescue objective → weapon upgrade → Hummer encounter → helicopter pressure → destructible checkpoint → Command Mech boss → extraction cinematic.

## Level setup

Create `/Game/Maps/Jeddah_RedSea_Assault` using Unreal's Open World level template so World Partition is available from day one. Set World Settings GameMode Override to `ASGameMode`.

Add:

- PlayerStart x 8.
- NavMeshBoundsVolume around the combat district.
- `ASWorldEventDirector` actor.
- A boss Blueprint derived from `ASBossCharacter`.
- A vehicle Blueprint derived from `ASVehiclePawn`.
- Original/licensed environment assets only.

## Art direction gate

The slice is not accepted with grey-box primitives as the final proof. It must establish a unique Red Sea / Arabian visual identity, readable silhouettes, cinematic lighting, weapon feedback and a consistent hero scale.

## Performance gates

- PC high-end target: 60 fps during combat.
- Server: stable simulation under 8 real clients before raising player cap.
- No shipping build may depend on editor-only assets.
- World Partition/HLOD/streaming must be profiled before expanding the city.
