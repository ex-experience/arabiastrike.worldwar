# 08 — NETWORK, HACKING & STRATEGIC WARFARE

## Two-layer strategic interface

### GLOBAL COMMAND
Human-readable tactical/strategic command:
units, missions, threats, fleets, aircraft, evacuation, support.

### NETWORK VIEW — “THE GRID”
Cyber-physical infrastructure:
communication nodes, satellites, data paths, drone control, sensors, traffic/security infrastructure, electronic warfare and hostile/friendly network state.

Player can transition conceptually:
`PHYSICAL WORLD ↔ TACTICAL MAP ↔ NETWORK VIEW`

## Hacking system

Core classes:
- ASHackableComponent
- ASHackingComponent
- ASHackDefinition
- ASNetworkNode
- ASDeviceNetworkSubsystem
- ASSatelliteLinkComponent
- ASDroneNetworkComponent
- ASCommandNetworkSubsystem

Hackable devices:
camera, traffic light, door, gate, elevator, vehicle, drone, alarm, power box, billboard, security terminal, turret.

Actions:
Scan, Ping, Disable, Distract, Open, Close, Hijack, Overload, Spoof, Track, Remote Control.

Do not copy another franchise’s UI, iconography, terminology or hacking minigames.

## Strategic consequences

Game-mechanical examples:
- disable a network node → hostile drone tracking degrades;
- compromise security hub → cameras temporarily assist player;
- disrupt uplink → reinforcement precision/cadence changes;
- capture radar → friendly air/support option unlocks;
- damage infrastructure → district services/traffic/security state changes.

## Global conflict systems
Proposed architecture:
- ASGlobalConflictSubsystem
- ASTheaterStateSubsystem
- ASCommandNetworkSubsystem
- ASStrategicMapActor
- ASCrisisDirector
- ASEvacuationDirector
- ASRulesOfEngagementComponent

The strategic layer must affect gameplay, not exist only as visual lore.
