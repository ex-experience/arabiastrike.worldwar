# PRE-VERTICAL ASPlayerCharacterV2 Analysis

Snapshot branch: `backup/asww-local-aaa-runtime-pre-vertical-20260829`
Snapshot base: `b4185e92a33e2a27b86dcd1d3272d3d2537b242a`

## Purpose

`AASPlayerCharacterV2` is the current experimental player pawn selected by
`AASGameMode::DefaultPawnClass`. It extends the established `AASCharacter`
combat/life-cycle implementation with a tactical movement state machine,
third-person camera tuning, a visible template rifle, a temporary rifle data
asset loadout, and QA telemetry used by the Phase 01-03 recovery scripts.

## Input behavior

- It deliberately bypasses `AASCharacter::SetupPlayerInputComponent` and calls
  `ACharacter::SetupPlayerInputComponent` to avoid duplicate base bindings.
- It still uses legacy `BindAxis`/`BindAction`, not Enhanced Input.
- Bound axes: forward/right movement, yaw and pitch.
- Bound actions: jump/mantle, sprint, crouch/slide, prone, aim, free look,
  combat stance, fire, reload, interact, vehicle interaction, grenade, melee,
  fire mode and weapon slots 1-4.
- Melee and fire-mode handlers are placeholders. Vehicle interaction currently
  delegates to the generic interaction trace.

## Locomotion behavior

- Defines local `Standing`, `Crouched`, `Prone` and `Sliding` states plus
  `Relaxed`, `LowReady`, `HighReady` and `ADS` readiness states.
- Implements movement-speed profiles, sprint, crouch toggle, timed slide,
  free-look yaw behavior and FOV-based ADS.
- Mantle is a two-trace prototype followed by `SetActorLocation`; it is not a
  production traversal component and has no Motion Warping/animation contract.
- Prone is currently a safe crouch-based approximation. It does not provide a
  true prone capsule, crawl animation or replicated stance contract.
- Tick contains an uncrouch recovery guard for the standing state.

## Rifle integration

- Creates `ASWW_TacticalRifleMesh` and attaches the Epic template
  `/Game/Weapons/Rifle/Meshes/SKM_Rifle` to `HandGrip_R`.
- On server authority, `BeginPlay` loads
  `/Game/Weapons/Definitions/DA_ASWW_Rifle_01` and adds/equips it through the
  replicated `UASWeaponInventoryComponent`.
- Fire, reload, grenade and slot switching delegate to the existing
  `AASCharacter`/weapon/inventory framework.
- The current weapon component performs server-side fire validation, ammo
  mutation, reload timing, hit/projectile handling and replication.

## Animation integration

- The full-body mesh uses the Epic template
  `/Game/Characters/Mannequins/Anims/Unarmed/ABP_Unarmed` locomotion AnimBP.
- Rifle animations and `ABP_TP_Rifle` exist in the local snapshot, but V2 does
  not currently install a production upper-body rifle layer.
- No final hero animation, true prone, reload presentation, left-hand IK or
  production motion-matching integration is proven here.

## Camera

- Uses inherited `CameraBoom` and `FollowCamera` components.
- Configures third-person boom length/offset and camera/rotation lag.
- Interpolates between 88-degree default FOV and 68-degree ADS FOV.
- Camera behavior is local presentation state and is not replicated.

## Replication and authority

- V2 declares no replicated properties or RPCs of its own.
- Character movement and the inherited health/downed/elimination framework are
  supplied by `ACharacter`/`AASCharacter`.
- Rifle loadout creation is gated by `HasAuthority()`.
- Weapon fire, reload and inventory slot changes delegate to server-authoritative
  components.
- V2 stance/readiness/aim/sprint state is not replicated, and its direct mantle
  relocation is not yet an acceptable authoritative multiplayer traversal path.

## Dependencies

- `AASCharacter`, `AASGameMode`, `AASPlayerController`.
- `UASWeaponComponent`, `UASWeaponInventoryComponent`,
  `UASWeaponDefinition`, health/life-state and interaction systems.
- Epic UE 5.8 template Manny, Unarmed AnimBP and rifle assets.
- Local original `DA_ASWW_Rifle_01` data asset.
- Legacy action/axis mappings in `Config/DefaultInput.ini`.

## Known QA status at preservation time

- Real UE 5.8 editor loading of `Jeddah_RedSea_Assault` passes separately.
- Phase 03 fire/reload diagnostics are installed in current source.
- Rifle definition load/equip had previously been observed, but the latest
  available runtime QA before this snapshot did not prove visible fire/reload.
- True prone and clean visual stance transitions are not implemented.
- Melee, fire-mode switching and dedicated vehicle entry are not implemented.
- Current snapshot must be rebuilt and runtime-tested before any stronger
  gameplay PASS claim.

## Preservation decision

Preserve V2 intact in the safety snapshot. Treat it as a recovery/reference
implementation to cherry-pick selectively after build and runtime evidence,
not as the final vertical-slice player architecture.
