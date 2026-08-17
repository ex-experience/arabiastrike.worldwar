# Phase 3 Unreal Editor Asset Checklist

1. Create BP_AS_Character from AASCharacter and assign skeletal mesh + AnimBP.
2. Create rifle/shotgun/RPG UASWeaponDefinition data assets and add them to StartingLoadout.
3. Create BP_AS_Grenade from AASGrenade and assign mesh / Niagara / sound hooks.
4. Create BP_AS_WeaponPickup and assign weapon definitions.
5. Create BP_AS_Hostage from AASHostageNPC and link it to the placed AASMissionDirector.
6. Create BP_AS_Soldier variants and set squad roles (Rifleman, Heavy, Flanker, Grenadier, Marksman).
7. Add NavMeshBoundsVolume to the combat district.
8. Create BP_AS_Hummer from AASPilotableVehiclePawn; production handling should migrate to Chaos Vehicles in the vehicle pass.
9. Create BP_AS_Helicopter from AASHelicopterPawn and provide mesh / rotor animation / attack VFX.
10. Create BP_CommandMech from AASBossCharacter and child/attached AASBossWeakPoint actors.
11. Bind UMG HUD to AASPlayerController BlueprintPure HUD query functions and combat delegates.
12. Add Niagara effects to Multicast shot/explosion hooks in Blueprint subclasses.
13. Run two-client PIE and dedicated-server smoke tests before tuning visuals.
