# Jeddah Vertical-Slice Asset Gap Inventory

Repository audit on 2026-08-17 found zero `.umap` files and zero `.uasset` files. `Content/` contains directory placeholders only. This inventory is a production queue, not a substitute for binary assets authored and saved by Unreal Editor 5.8.

Do not change `GameDefaultMap` or `ServerDefaultMap` away from `/Engine/Maps/Entry` until the real map loads successfully in Unreal.

| Priority | Missing binary/editor work | Intended project location or dependency | Required verification |
|---|---|---|---|
| P0 | Jeddah World Partition map | `Content/Maps/Jeddah_RedSea_Assault.umap` | Editor map load, World Partition enabled, save/reopen |
| P0 | PlayerStart and respawn-safe area | Jeddah map actors | Dedicated-server spawn and repeated authoritative respawn |
| P0 | Ground/collision and combat test space | Jeddah map/static meshes | Movement, traces, projectiles and navigation collision |
| P0 | Player skeletal mesh | `Content/Characters/` | Correct skeleton, collision, LODs and multiplayer visibility |
| P0 | Player locomotion/combat animations | `Content/Characters/` | 360 movement, sprint, jump, aim, fire, reload, downed/revive/death |
| P0 | Weapons and weapon Data Assets | `Content/Weapons/` | Ammo/reload/projectile configuration and replication |
| P0 | Enemy soldier assets | `Content/AI/` | AI controller possession, detection, navigation, damage/death |
| P0 | NavMesh/World Partition navigation setup | Jeddah map | Dynamic/partitioned navigation in server runtime |
| P1 | Command Mech/boss mesh, weak points and animations | `Content/AI/` | Phase replication, weak-point damage and death |
| P1 | Hummer mesh/Chaos setup/turret | `Content/Vehicles/` | Enter/exit, possession, movement, turret and damage replication |
| P1 | Helicopter mesh/flight setup | `Content/Vehicles/` | Possession/AI flight, weapons and replicated damage |
| P1 | Boat/Water assets | `Content/World/Jeddah/Boats/`, `Sea/` | Water interaction, possession and network movement |
| P1 | Mission actors and extraction zone | Jeddah map/mission assets | Objective and extraction state replication |
| P1 | UI widgets/HUD | `Content/UI/` | Health, downed, respawn, ammo, objective and connection states |
| P2 | Materials and textures | Content feature folders | Licensing, quality tiers, streaming and memory budgets |
| P2 | Niagara/VFX | `Content/VFX/` | Weapons, impacts, destruction and replicated cue timing |
| P2 | Audio | `Content/Audio/` | Spatial mix, combat, vehicles, UI and platform output |
| P2 | World Data Assets and Data Layers | `Content/World/Jeddah/DataLayers/` | Runtime layer transitions and replicated orchestration cues |
| P2 | PCG assets | `Content/World/Jeddah/PCG/` | Deterministic placement, partition generation and performance |
| P2 | Water assets | `Content/World/Jeddah/Sea/` | Rendering, collision, buoyancy and platform scalability |
| P2 | Destruction assets | `Content/World/Jeddah/Destruction/` | Authoritative state, persistence policy and performance |
| P2 | Level Sequences | `Content/Cinematics/Jeddah/` | Synchronized cues, skip/rejoin behavior and gameplay handoff |

The first editor batch should create only the P0 playable loop, reopen the real map, compile, run PIE and retain logs before defaults are changed.
