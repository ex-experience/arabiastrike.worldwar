# Phase 4 — JEDDAH WORLD

Phase 4 moves ARABIA STRIKE: WORLD WAR from a combat sandbox into a scalable city-world foundation.

## Runtime systems added

- Replicated time-of-day and weather state with Blueprint presentation hooks.
- District volumes: Corniche, Al-Balad, Port, Industrial, Airport, Desert Outskirts.
- Replicated per-player current district for HUD, matchmaking telemetry, encounters and missions.
- Spline-driven server-authoritative ambient traffic scaffold.
- NavMesh-driven civilian population scaffold.
- Weighted dynamic encounter director keyed by district and world threat.
- PCG component hook for designer-authored procedural graphs.
- World bootstrap that detects whether the loaded level actually uses World Partition.

## Required Unreal Editor assembly

The repository cannot contain a useful hand-written `.umap`. Create `L_Jeddah_RedSeaAssault` using **File → New Level → Open World**. The Open World template supplies World Partition, One File Per Actor, Data Layers and HLOD foundations. Then place `ASWorldBootstrap` and configure Blueprint subclasses for the three director classes.

## District plan

1. Corniche — seaside combat, traffic, hotels, fast traversal.
2. Al-Balad — dense alleys, rooftops, infantry pressure.
3. Port — containers, cranes, convoy events, heavy vehicles.
4. Industrial — destructible combat arenas and Command Mech staging.
5. Airport — future expansion / aircraft operations.
6. Desert Outskirts — long-range vehicle warfare and sandstorms.

## PCG strategy

Use PCG graphs for repeated non-authoritative world decoration and authored city patterns: curb props, lights, parked vehicles, clutter, facade variants, vegetation and selected building lots. Critical replicated gameplay actors are spawned by server-owned directors instead of trusting procedural client state.

## Performance baseline

World Partition + HLOD must be validated before increasing district size. Keep ambient traffic and civilians server-budgeted. Use Data Layers to separate mission variants, destruction states, seasonal dressing and cinematic-only content.

## Multi-city foundation

`UASCityDefinition` is a Primary Data Asset used to describe a city without hard-coding it into gameplay. Jeddah is the first definition; Riyadh, Casablanca and later cities can point at their own World Partition maps, district profiles, default climate and player budgets while reusing the same combat/online runtime.
