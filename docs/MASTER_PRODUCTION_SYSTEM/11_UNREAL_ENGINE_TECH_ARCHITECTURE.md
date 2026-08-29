# 11 — UNREAL ENGINE 5.8 TECHNICAL ARCHITECTURE

## Core technology target
- Unreal Engine 5.8
- Lumen
- Nanite where appropriate
- Virtual Shadow Maps
- World Partition
- HLOD
- PCG
- Niagara
- Chaos / Chaos Vehicles
- Water
- MetaSounds
- Motion Matching
- Pose Search
- Choosers
- Control Rig
- IK Rig / Retargeter
- Mass Entity
- StateTree
- Smart Objects
- Enhanced Input
- Level Sequence / MovieScene
- Gameplay Tags / Gameplay Tasks
- UMG / Slate

## Legal sample references
Use Epic samples as technical references and building blocks where their license permits:
- Lyra Starter Game
- Game Animation Sample
- City Sample

Do not copy protected content from unrelated commercial games.

## Input migration
The project already includes Enhanced Input as a dependency, while historical character code used legacy BindAxis/BindAction.
Required refactor:
`Legacy Input → Enhanced Input`

Input contexts:
IMC_OnFoot
IMC_Combat
IMC_Vehicle
IMC_Hacking
IMC_UI

## Proposed gameplay modules/components

Player:
ASLocomotionComponent
ASStanceComponent
ASTraversalComponent
ASCoverComponent
ASStealthComponent
ASMeleeComponent
ASInteractionScannerComponent

Combat:
ASAimComponent
ASRecoilComponent
ASBallisticsSubsystem
ASWeaponHandlingComponent
ASWeaponAttachmentComponent
ASEquipmentComponent
ASExplosionComponent

AI:
ASCombatStateTree
ASPerception/awareness extensions
ASCoverQueryComponent
ASSearchBehaviorComponent
ASCombatDirector

Vehicles:
ASVehicleAccessComponent
ASVehicleSeatComponent
ASVehicleDoorComponent
ASVehicleInteractionComponent

World:
ASWantedSubsystem
ASCrimeSubsystem
ASWitnessComponent
ASDispatchSubsystem
ASCitizenRoutineComponent
ASPopulationSubsystem
ASEconomySubsystem
ASShopSystem

Hacking/Strategic:
ASHackableComponent
ASHackingComponent
ASNetworkNode
ASDeviceNetworkSubsystem
ASGlobalConflictSubsystem
ASTheaterStateSubsystem
ASCommandNetworkSubsystem
ASStrategicMapActor

## Networking rule
Clients request.
Server validates:
range, state, ownership, timing, resources and authoritative outcomes.
Cosmetic FX may multicast according to reliability/performance requirements.

## Build and QA gate
1. clean repo state
2. diff check
3. UE 5.8 Editor compile
4. UE 5.8 Game compile
5. real map load/save/reopen
6. PIE smoke
7. gameplay loop
8. package Win64
9. packaged EXE launch
10. multiplayer acceptance
11. performance/scalability
12. only then promotion/merge
