# Phase 5 — JEDDAH LIVING CITY + CINEMATIC WORLD

This phase turns the Phase 4 city scaffold into a reactive online-world foundation. It deliberately separates runtime C++ systems from binary Unreal Editor assets that must be authored in UE5.8.

## Runtime systems added
- Faction identity and hostility component.
- Security response director driven by server world-threat state.
- Civilian reactions: observe, cower, flee and evacuate.
- Traffic emergency behavior: yield, evacuate and stop.
- Stateful destruction with replicated structural health/state.
- Living-world event definitions, cooldowns and authoritative event scheduling.
- Data Layer orchestration hook for runtime/editor Data Layer assets.
- Interior, rooftop, underground and waterfront zone metadata.
- Server-authoritative boat movement foundation.
- Chaos Hummer pawn integration point using AWheeledVehiclePawn.
- Cinematic encounter cue replication for synchronized Level Sequence presentation.
- World/network soft-budget sampling.

## Required UE5.8 editor assets
Create real Data Layer Assets, Level Sequences, Water Bodies, Chaos wheel blueprints, Hummer skeletal mesh + physics asset + vehicle animation blueprint, destruction geometry/Chaos assets, traffic meshes and city art. Do not commit invented `.uasset` placeholders.

## Target living-world loop
Player action -> world threat -> security escalation -> civilian/traffic response -> district event -> destruction/cinematic state -> recovery/cooldown.
