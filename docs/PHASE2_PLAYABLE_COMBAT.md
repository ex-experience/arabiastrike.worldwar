# Phase 2 — Playable Combat Slice

This increment converts the architecture starter into a gameplay-bearing C++ slice.

## Runtime systems now present
- server-authoritative hitscan and projectile fire
- replicated ammo, magazine and reload state
- weapon definitions as Primary Data Assets
- 360 character movement, sprint, dash, fire, reload and interact
- interactable contract for vehicles/world objects
- pilotable vehicle scaffold with replicated seat reservation
- server AI target acquisition + navigation pressure
- mission director with replicated Jeddah phase progression
- objective trigger volumes

## Editor assembly required
Create Blueprint children and assign meshes/animations/audio/VFX. Create WeaponDefinition Data Assets and assign one to the player/AI WeaponComponent. Place ASMissionDirector and objective volumes in the World Partition map.

## Acceptance gate
Phase 2 is not called “AAA complete.” It passes only when a packaged client + dedicated server can complete Insertion → Street Combat → Rescue → Hummer Assault → Command Mech → Extraction with two remote clients.
