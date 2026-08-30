# ARABIA STRIKE — WORLD WAR
## MASTER PRODUCTION DIRECTIVE · LOCKED SYSTEM

Status: **Master production specification**
Engine target: **Unreal Engine 5.8**
Primary repository: `ex-experience/arabiastrike.worldwar`
Development baseline: `codex/asww-development`
Rule: **DO NOT TOUCH `main` until real compile, runtime, package, QA and explicit acceptance pass.**

---

## 1. Product definition

ARABIA STRIKE — WORLD WAR is an original Saudi-origin premium action IP designed as a high-fidelity, near-future military open-world thriller.

The design target is **feature-class parity and responsiveness**, not copying protected code, characters, maps, audio, logos, dialogue, weapon art, level layouts or proprietary content from any commercial title.

Reference categories:
- modern military shooter responsiveness and combat readability;
- dense immersive near-future city interaction;
- open-world vehicles, traffic, civilians and reactive security;
- stealth, traversal and network/hacking interaction;
- cinematic strategic warfare across land, sea, air and network space.

Canonical identity:
> **Photoreal Saudi Near-Future Military Open World**
> 85–90% believable Saudi reality + 10–15% near-future military/network technology.

---

## 2. Non-negotiable production principles

1. Original or properly licensed assets only.
2. One canonical hero model across marketing, gameplay and cinematics.
3. Jeddah must be geographically and culturally recognizable; avoid generic Gulf-city substitution.
4. Gold/black is the franchise/branding layer; gameplay HUD is primarily white/cyan with amber/red semantic states.
5. Every major visual reference must become a production requirement, not remain marketing-only art.
6. Gameplay must be PC-first, fully remappable and Enhanced Input based.
7. Server validates authoritative multiplayer gameplay. Clients request; server checks state/range/ownership and applies outcomes.
8. C++ gameplay systems and binary Unreal assets are both required. Code alone is not a playable AAA slice.
9. Build a 20–30 minute vertical slice before scaling to full open world.
10. Performance budgets, LODs, HLOD, streaming and scalability are production requirements from day one.

---

## 3. Eight locked gameplay pillars

1. Infantry Warfare
2. Open-World Urban Life
3. Vehicle Combat
4. Squad Tactics
5. Stealth & Infiltration
6. Naval / Air Operations
7. Network Warfare / Hacking
8. Cinematic Strategic Warfare

---

## 4. Core player fantasy

The player is not merely a shooter avatar. The player is:
- a Saudi task-force leader operating inside a living city;
- a tactical commander connected to squad, vehicles and support;
- a defender whose actions affect civilians, districts and infrastructure;
- an infiltrator who can use stealth and network systems;
- a participant in a conflict that escalates from Jeddah homefront defense into Red Sea and global strategic warfare.

---

## 5. World escalation

`NORMAL → ALERT → EVACUATION → COMBAT → HEAVY CONFLICT → RECOVERY`

World state must affect:
- civilian behavior;
- traffic;
- emergency response;
- military/security deployment;
- destruction;
- lighting/audio;
- mission opportunities;
- road access;
- district activity;
- network availability.

---

## 6. Current baseline to preserve

Existing project work already established scaffolding for:
- replicated character movement and life state;
- weapons, ammo, reload, grenades, inventory;
- revive/respawn;
- suppression and tactical AI;
- Hummer, helicopter, boat and vehicle damage foundations;
- civilians, traffic, security response, destruction and living-world directors;
- world/mission/cinematic/network hooks.

Before adding scope, verify the actual current branch and real UE 5.8 build state.

The previous repository audit recorded no production `.umap` or `.uasset` content. Treat that as a historical warning and re-audit before claiming editor content exists.

---

## 7. Build gate

No feature is considered production-ready until:
1. code compiles under real UE 5.8;
2. Editor target succeeds;
3. Game target succeeds;
4. map loads in Editor;
5. PIE smoke passes;
6. packaged Win64 build launches;
7. required multiplayer test passes;
8. performance and regression checks pass;
9. visual and gameplay acceptance criteria in this pack are met.
