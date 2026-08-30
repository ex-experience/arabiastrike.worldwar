# 04 — WEAPONS, EQUIPMENT & GAME BALLISTICS

All weapons and accessories must use original or properly licensed art and naming.

## Weapon categories
- Assault Rifles
- Battle Rifles
- SMGs
- Shotguns
- LMGs
- DMRs
- Sniper Rifles
- Pistols
- Machine Pistols
- Launchers
- Melee
- Special Weapons

## Data model per weapon
Game parameters:
- Damage
- RoundsPerMinute
- MagazineSize
- ReserveAmmo
- ReloadTime
- TacticalReloadTime
- game muzzle velocity
- projectile mass abstraction where simulated
- HipSpread
- ADSSpread
- HorizontalRecoil
- VerticalRecoil
- RecoilRecovery
- ADS time
- SprintToFire time
- RaiseWeapon time
- WeaponSway
- MovementAccuracyPenalty
- stance accuracy multipliers
- damage falloff
- game penetration power
- game ricochet chance
- suppression value
- heat
- fire mode

These are gameplay abstractions only, not real-world weapon construction instructions.

## Weapon handling layers
- Aim component
- Recoil component
- Ballistics component/subsystem
- Handling component
- Attachment component
- Equipment component

## ADS
Hip → raise → ADS transition → sight alignment → ADS.
Layers:
camera FOV interpolation, weapon alignment, sway, breathing, weapon recoil, camera recoil, animation additive recoil, inertia.

Do not merge all recoil into one camera shake.

## Hybrid ballistics
Use hitscan or simulated projectile based on gameplay needs.
Heavy projectiles/rockets/grenade-launcher style systems should use projectile actors.

## Hit zones
Head, neck, upper/lower torso, pelvis, upper/lower arms, hands, thighs, calves, feet.
Damage multipliers are balance values and must be tuned through testing.

Injury feedback can affect:
- gait;
- sway;
- speed;
- knockdown likelihood;
- recovery state.

## Attachments
Optic, muzzle, barrel, underbarrel, magazine, stock, grip, laser, flashlight, ammunition type.

## Equipment
Frag-type game grenade, smoke, flash, incendiary, EMP-style device, breaching charge, deployable explosive game device, recon drone, combat drone, med kit, armor kit, night vision, thermal optic, binoculars, range finder.

## Weapon art
Hero prop decomposition:
receiver, barrel, handguard, stock, grip, magazine, moving controls, sights.
Materials must support:
clean metal, oil, fingerprints, dust, scratches, carbon residue, heat discoloration, wetness and battle grime.

## Weapon animation
Equip, unequip, raise/lower, hip fire, ADS enter/idle/fire/exit, empty/tactical reload, inspect, malfunction/clear (fictional animation), sprint/run/walk/crouch/prone.
