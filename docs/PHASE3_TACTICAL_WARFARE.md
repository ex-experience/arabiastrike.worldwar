# Phase 3 — Tactical Warfare

This phase turns the Phase 2 combat scaffold into a network-aware co-op combat slice.

## Runtime systems added
- Server-validated interaction tracing (vehicle entry, pickups, revive targets).
- Replicated weapon inventory and server-owned slot switching.
- Weapon pickup actor.
- Grenade actor with fuse, bounce, radial damage and replicated movement.
- Downed / bleedout / revive flow with same-team gate.
- AI squad roles, tactical states and suppression meter.
- Near-miss suppression emitted by authoritative hitscan fire.
- Tactical AI offsets for advance / hold / flank / suppressed fallback.
- Hummer turret component with authoritative fire and replicated aim.
- Vehicle damage-state component (critical and engine-disabled thresholds).
- Driver exit restores the original pawn rather than leaving a possession dead-end.
- Helicopter combat pawn scaffold with orbit pressure and nose-gun attack.
- Command Mech weak-point actor and boss phase escalation hooks.
- PlayerController HUD query hooks for health, ammo, downed state, mission phase and hostage rescue progress.
- Replicated hostage NPC rescue flow tied to the Rescue mission phase.

## Asset work still required in Unreal Editor
C++ supplies gameplay rules; production assets must supply skeletal meshes, AnimBPs, Niagara systems, sounds, materials, Chaos vehicle setup, Behavior Tree/Blackboard assets, UMG widgets, boss attack montages and Jeddah environment content.

## Networking rule
Clients request. The server validates range/state/ownership and applies authoritative gameplay outcomes. Cosmetic FX may multicast unreliably.
