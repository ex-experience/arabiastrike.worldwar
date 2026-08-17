# ARABIA STRIKE: WORLD WAR

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
- Pixel Streaming 2 present but disabled until cloud-streaming deployment

## Start

Open `ArabiaStrikeWorldWar.uproject` in Unreal Engine 5.8, compile, create an Open World level at `/Game/Maps/Jeddah_RedSea_Assault`, set its GameMode to `ASGameMode`, then follow `docs/JEDDAH_VERTICAL_SLICE.md`.

Run repository-only checks with:

```bash
python ci/preflight.py
```

See `docs/BUILD_AND_RUN.md` for client/server build commands.


## Phase 2 — Playable Combat Foundation
Adds data-driven weapons, replicated ammo/reload/projectiles, interaction, pilotable vehicle scaffold, AI pressure, and replicated Jeddah mission progression. See `docs/PHASE2_PLAYABLE_COMBAT.md`.
