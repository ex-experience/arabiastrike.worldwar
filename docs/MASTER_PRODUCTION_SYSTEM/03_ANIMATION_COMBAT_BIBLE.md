# 03 — ANIMATION, LOCOMOTION, TRAVERSAL, COVER, STEALTH & MELEE

## Animation architecture

Target:
- Motion Matching
- Pose Search
- Choosers
- Motion Warping
- Control Rig
- IK Rig / Retargeter
- additive procedural layers
- root motion where appropriate

Use Epic Game Animation Sample as a legal technical reference and starting point where license permits.

## Locomotion states
- Idle / relaxed / armed
- Walk F/B/L/R
- Jog F/B/L/R
- Run
- Sprint
- Tactical Sprint
- acceleration / deceleration
- starts / stops / pivots
- turn-in-place 45/90/135/180
- aim walk
- injured locomotion
- suppressed locomotion
- heavy-gear locomotion

## Stances
- Standing
- Crouched
- Prone

Combat posture:
- Relaxed
- Low Ready
- High Ready
- Aiming
- Suppressed
- Injured

## Traversal
- jump
- falling
- light/heavy landing
- low/medium/high vault
- low/high mantle
- ledge climb/drop
- window/fence vault
- slide
- dive-to-prone
- roll/dodge
- ladder
- rappel
- zipline
- rooftop jump
- contextual drop-down
- water locomotion at knee/waist depth
- vehicle/boat entry and exit

`Space` should be contextual:
Jump / Vault / Mantle / Climb / Window Vault / Cover Vault.

## Cover
Functions:
- detect cover
- enter/leave
- move along cover
- left/right/over peek
- aim from cover
- blind fire where balanced
- cover-to-cover
- corner transition

Detection should combine environment traces, navigation links and contextual animation rather than rely only on manually placed cover points.

## Stealth
Player variables:
- Visibility
- Noise
- LightExposure
- MovementNoise
- WeaponNoise
- DetectionMultiplier

AI states:
`Unaware → Suspicious → Investigating → Searching → Alert → Combat → LostTarget`

Detection factors:
movement speed, stance, surface, lighting, distance, suppressed weapon state, line of sight, cover, weather and enemy alertness.

## Melee
- light/heavy punches
- kick / heavy kick
- elbow
- knee
- block
- parry
- dodge
- counter
- push
- grab
- weapon butt
- knife attacks
- stealth takedown
- environmental takedown

Melee requires:
hit windows, trace windows, stamina, poise, interrupts, root motion, target correction, Motion Warping.

## Hit reactions
Directional and body-zone-aware:
front/back/left/right; head/chest/abdomen/arms/legs.
Reaction classes:
light hit, heavy hit, projectile hit, explosive impulse, vehicle impact, melee.

## Tactical AI
States:
Patrol, Observe, Suspicious, Investigate, Alert, SeekCover, Advance, Suppress, Flank, Grenade, Breach, Retreat, Heal, Revive, CallBackup, Search, Defend, VehicleMount, VehicleCombat, Surrender, Panic.

Squad roles:
Leader, Rifleman, Support, Marksman, Breacher, Medic, Anti-Vehicle.

Coordination target:
one element suppresses while others flank, hold, grenade, breach or support instead of all agents rushing the player.
