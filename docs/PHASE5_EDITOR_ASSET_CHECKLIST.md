# Phase 5 Editor Asset Checklist

1. Open the UE5.8 Open World Jeddah map with World Partition enabled.
2. Create runtime Data Layer Assets: DL_Calm, DL_Combat, DL_PortLockdown, DL_Evacuation, DL_DestroyedState and district-specific layers.
3. Implement BP_ASDataLayerOrchestrator and map layer-name requests to DataLayerManager runtime state changes.
4. Enable/configure Water and place Red Sea Water Body assets.
5. Create BP_ASBoatPawn visual/physics presentation.
6. Create the production Hummer using Chaos Vehicles: skeletal mesh, physics asset, wheel blueprints, torque curve, vehicle anim BP and a Blueprint derived from ASChaosHummerPawn.
7. Create Level Sequences for Hummer entry, helicopter arrival, Command Mech reveal, port lockdown and extraction.
8. Bind ASCinematicEncounterDirector cues to those Level Sequences on clients.
9. Create destruction presentation Blueprints derived from ASDestructibleStateActor. Use authored fracture/Chaos assets only where budget allows.
10. Populate SecurityResponseDirector reinforcement anchors outside direct player sight lines.
11. Configure civilian/traffic budgets by district and profile 8/16/32-player servers.
12. Build HLOD and validate Data Layer transitions before production acceptance.
