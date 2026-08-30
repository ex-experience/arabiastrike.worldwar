# IMPLEMENTATION BACKLOG — STRICT ORDER

## P0 — Repository / build integrity
- Verify current `codex/asww-development`.
- Do not modify `main`.
- Resolve remaining UHT/C++ build blockers.
- Editor target Win64 Development = PASS.
- Game target Win64 Development = PASS.
- Package Win64 and launch executable.

## P0 — Real editor content
- Create and save real World Partition Jeddah slice.
- Save real player skeletal mesh / rig / AnimBP assets.
- Save real weapon Data Assets.
- Save real enemy character/AI assets.
- Save real collision/NavMesh setup.
- Reopen assets after save to prove validity.

## P1 — Player
- Enhanced Input migration.
- Motion Matching locomotion.
- stance / prone / slide / dive.
- traversal / mantle / vault / rappel.
- cover and lean.
- ADS / recoil / handling.
- melee.
- stealth/noise/light.

## P1 — Combat
- attachment pipeline.
- damage zones.
- suppression refinement.
- material impact response.
- game projectile/hitscan hybrid.
- grenade/equipment categories.
- explosion/VFX/audio response.

## P1 — AI / squad
- StateTree.
- cover queries.
- squad role coordination.
- search/investigate.
- revive/support.
- vehicle mount/combat.
- civilian-aware rules.

## P1 — World
- Al-Balad slice.
- Corniche slice.
- port/extraction slice.
- traffic/civilians.
- crisis and security escalation.
- day/night/weather state.

## P2 — Vehicles / maritime
- 4x4 polished.
- civilian traffic vehicles.
- mounted weapons.
- boat/RHIB.
- helicopter.
- convoy mission.
- port/naval encounter.

## P2 — Network / strategic
- tactical command table.
- Network View / The Grid.
- hackable devices.
- world-state consequences.
- strategic map.

## P2 — Presentation
- 3D main menu/HQ.
- loadout bench.
- HUD families.
- motion language.
- MetaSounds / mix.
- cinematic intro.
- Mech reveal tease.

## Shipping rule
Never mark a system complete from documentation or static screenshots alone.
Required proof: compiled, loaded, played, packaged and accepted.
