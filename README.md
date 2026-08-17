# ARABIA STRIKE: WORLD WAR — UE5.8 Phase 5 JEDDAH LIVING CITY


Unreal Engine 5.8 C++ production starter for a server-authoritative, 360-degree online action game.

## Vertical Slice 01 — JEDDAH: RED SEA ASSAULT

The first playable target is deliberately narrow:

1. 360-degree third-person locomotion.
2. Sprint, jump, dash and responsive aiming.
3. Server-authoritative hitscan combat and replicated health.
4. 8-player online baseline with global/squad/proximity text chat.
5. Hummer vehicle foundation.
6. World-event director and multi-phase boss foundation.
7. Dedicated Server target.
8. Optional EOS and Pixel Streaming 2 integration gates.

The repository contains no third-party game assets, copied maps, characters, music, or source code. Art/content must be original or properly licensed.

## Engine

- Unreal Engine 5.8
- C++ runtime module
- Standard UE replication for the first performance baseline
- Dedicated server target
- Online Services Null for local/backend-free testing
- EOS plugins present but disabled until credentials/product setup exists
- Pixel Streaming 2 is enabled in the project descriptor, but plugin loading remains unverified until a real UE 5.8 installation is available; no streaming backend is configured

## Start

Open `ArabiaStrikeWorldWar.uproject` in Unreal Engine 5.8, compile, create an Open World level at `/Game/Maps/Jeddah_RedSea_Assault`, set its GameMode to `ASGameMode`, then follow `docs/JEDDAH_VERTICAL_SLICE.md`.

Run repository-only checks with:

```bash
python ci/preflight.py
```

See `docs/BUILD_AND_RUN.md` for client/server build commands.

When a complete UE 5.8 or 5.8.1 installation becomes available, resume the blocked real-build pipeline with:

```powershell
.\BuildScripts\resume_after_ue58.ps1
```

Runtime results must follow `RuntimeEvidence/README.md`; no compile, PIE, multiplayer, package or Pixel Streaming success is inferred from repository checks. Production online prerequisites and the current binary-asset queue are tracked in `docs/ONLINE_PRODUCTION_READINESS.md` and `docs/ASSET_GAP_INVENTORY.md`.


## Phase 2 — Playable Combat Foundation
Adds data-driven weapons, replicated ammo/reload/projectiles, interaction, pilotable vehicle scaffold, AI pressure, and replicated Jeddah mission progression. See `docs/PHASE2_PLAYABLE_COMBAT.md`.


## Phase 3 additions
See `docs/PHASE3_TACTICAL_WARFARE.md`. The repository now includes authoritative interaction, co-op downed/revive, loadout switching, grenades, suppression/flanking AI, Hummer turret combat, helicopter pressure, boss weak points and HUD query hooks.


## Phase 4 — JEDDAH WORLD

This package now includes the first scalable-city runtime layer: World Partition detection, district state, replicated time/weather, traffic, civilians, dynamic encounters and PCG hooks. Binary city assets and the production `.umap` must be authored in Unreal Editor 5.8; see `docs/JEDDAH_WORLD_EDITOR_CHECKLIST.md`.


## Phase 5 — JEDDAH LIVING CITY + CINEMATIC WORLD

Adds replicated factions, security escalation, civilian and traffic reactions, destruction states, Data Layer orchestration hooks, boats/waterfront foundations, Chaos Hummer integration, authoritative living-world events, synchronized cinematic cues and world/network budgets. Binary city, Chaos, Data Layer, Water and Level Sequence assets must be authored in Unreal Engine 5.8. See `docs/PHASE5_JEDDAH_LIVING_CITY.md`.
