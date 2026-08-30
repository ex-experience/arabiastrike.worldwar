# ARABIA STRIKE WORLD WAR — AAA Implementation Sequence

Branch lock: `codex/asww-development`
`main`: untouched
Commit policy: no commit until a gated phase is runtime-verified.

## Phase 01 — Player Foundation V1
- Isolated `AASPlayerCharacterV2` derived from the existing proven character.
- Stable WASD/mouse camera.
- Sprint, crouch/slide, prone foundation, jump/mantle.
- ADS FOV, free-look, combat-ready state.
- PC input schema.
- Existing health/weapon/inventory/respawn retained through inheritance.
- Final military animation quality is **not** claimed in this phase.

## Phase 02 — Tactical Animation + Full-Body IK
- Keep proven locomotion base; do not replace the complete AnimBP with a shooter-template ABP.
- Layered upper-body rifle pose.
- Low-ready / high-ready / ADS transitions.
- Right-hand weapon alignment.
- Left-hand fore-end IK.
- Spine/head aim offset.
- Foot IK.
- Armed strafe, crouch, slide, prone, jump/land and mantle presentation.

## Phase 03 — Military Gunplay
- Weapon state machine.
- Hip fire / ADS.
- Semi / burst / auto.
- Recoil, spread, sway, sprint-to-fire, reload state.
- Projectile/ballistic hit path and surface response.
- Muzzle/audio/VFX.
- Runtime enemy damage and kill proof.

## Phase 04 — Melee / Cover / Tactical Equipment
- Punch, kick, block, dodge, takedown.
- Context cover / peek.
- Grenade, flash, smoke, breaching equipment.
- Armor/medical/ammo equipment.

## Phase 05 — Soldier AI + Urban Combat
- StateTree combat AI.
- Cover selection, flanking, suppression, search.
- Civilian/noncombatant behaviors.
- Encounter director integration.
- Street-combat acceptance scenarios.

## Phase 06 — Vehicles
- Civilian + military vehicle enter/exit.
- GTA/Watch Dogs-style PC vehicle context.
- Carjacking/interaction rules.
- Drive, brake, handbrake, camera, lights.
- Hummer first; helicopter and Command Mech after ground vehicle acceptance.

## Phase 07 — Open-World City Life
- World Partition streaming.
- Traffic and pedestrians.
- Police/security/faction response.
- Shops/points of interest and ambient activity.
- Contextual missions and open-world escalation.

## Phase 08 — Destruction / Explosions / Presentation
- Niagara/MetaSounds explosion stack.
- Physics/debris/destructible props where safe.
- Camera shake and impact response.
- Lighting/exposure/environment quality pass.

## Phase 09 — Multiplayer / Delivery
- 2-player then 4-player acceptance.
- Dedicated server remains blocked by installed-engine distribution until a compatible source-built server toolchain exists.
- Pixel Streaming 2 only after native runtime passes.
- Real signalling/WebRTC/browser input proof required before a public PLAY NOW claim.
