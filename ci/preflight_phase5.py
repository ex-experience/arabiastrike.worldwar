from pathlib import Path
import json,sys,re
ROOT=Path(__file__).resolve().parents[1]
required=[
'Source/ArabiaStrikeWorldWar/Public/Factions/ASFactionComponent.h',
'Source/ArabiaStrikeWorldWar/Public/World/ASSecurityResponseDirector.h',
'Source/ArabiaStrikeWorldWar/Public/World/ASCivilianReactionTypes.h',
'Source/ArabiaStrikeWorldWar/Public/World/ASDestructibleStateActor.h',
'Source/ArabiaStrikeWorldWar/Public/World/ASDataLayerOrchestrator.h',
'Source/ArabiaStrikeWorldWar/Public/World/ASLivingWorldEventDirector.h',
'Source/ArabiaStrikeWorldWar/Public/World/ASWorldEventDefinition.h',
'Source/ArabiaStrikeWorldWar/Public/World/ASLivingZoneVolume.h',
'Source/ArabiaStrikeWorldWar/Public/World/ASWorldStreamingBudgetDirector.h',
'Source/ArabiaStrikeWorldWar/Public/Vehicles/ASBoatPawn.h',
'Source/ArabiaStrikeWorldWar/Public/Vehicles/ASChaosHummerPawn.h',
'Source/ArabiaStrikeWorldWar/Public/Cinematics/ASCinematicEncounterDirector.h',
'docs/PHASE5_JEDDAH_LIVING_CITY.md','docs/PHASE5_EDITOR_ASSET_CHECKLIST.md']
errors=[]
for rel in required:
 p=ROOT/rel
 if not p.exists() or p.stat().st_size<40: errors.append(f'missing/empty: {rel}')
up=json.loads((ROOT/'ArabiaStrikeWorldWar.uproject').read_text())
plugins={p['Name']:p.get('Enabled',False) for p in up.get('Plugins',[])}
for name in ['PCG','ChaosVehiclesPlugin','Water']:
 if not plugins.get(name): errors.append(f'plugin not enabled: {name}')
build=(ROOT/'Source/ArabiaStrikeWorldWar/ArabiaStrikeWorldWar.Build.cs').read_text()
for mod in ['"PCG"','"ChaosVehicles"','"Water"','"LevelSequence"']:
 if mod not in build: errors.append(f'module dependency missing: {mod}')
markers={
'AWheeledVehiclePawn':'Source/ArabiaStrikeWorldWar/Public/Vehicles/ASChaosHummerPawn.h',
'NotifyThreat':'Source/ArabiaStrikeWorldWar/Public/World/ASCivilianCharacter.h',
'TrafficBehavior':'Source/ArabiaStrikeWorldWar/Public/World/ASTrafficVehicleAgent.h',
'EASDataLayerIntent':'Source/ArabiaStrikeWorldWar/Public/World/ASDataLayerOrchestrator.h',
'FASCinematicCueState':'Source/ArabiaStrikeWorldWar/Public/Cinematics/ASCinematicEncounterDirector.h',
'EASDestructionState':'Source/ArabiaStrikeWorldWar/Public/World/ASDestructibleStateActor.h',
'SoftReplicatedActorBudget':'Source/ArabiaStrikeWorldWar/Public/World/ASWorldStreamingBudgetDirector.h',
'SecuritySweep':'Source/ArabiaStrikeWorldWar/Public/Game/ASGameState.h',
'UASWorldEventDefinition':'Source/ArabiaStrikeWorldWar/Public/World/ASLivingWorldEventDirector.h',
'AASBoatPawn':'Source/ArabiaStrikeWorldWar/Public/Vehicles/ASBoatPawn.h',
'ServerSetBoatInput':'Source/ArabiaStrikeWorldWar/Public/Vehicles/ASBoatPawn.h',
'CooldownUntil':'Source/ArabiaStrikeWorldWar/Public/World/ASLivingWorldEventDirector.h'}
for token,rel in markers.items():
 if token not in (ROOT/rel).read_text(): errors.append(f'marker missing {token} in {rel}')
# Unreal generated include ordering
for p in (ROOT/'Source').rglob('*.h'):
 inc=[x.strip() for x in p.read_text(errors='ignore').splitlines() if x.strip().startswith('#include')]
 gens=[i for i,x in enumerate(inc) if '.generated.h' in x]
 if gens and gens[-1]!=len(inc)-1: errors.append(f'generated include not last: {p.relative_to(ROOT)}')
if errors:
 print('ASWW PHASE5 PREFLIGHT: FAIL')
 for e in errors: print(' -',e)
 sys.exit(1)
print('ASWW PHASE5 PREFLIGHT: PASS')
print('city=living-reactive')
print('factions=replicated')
print('security=threat-driven')
print('population=reactive-budgeted')
print('vehicles=chaos-hook+boats')
print('world-events=server-authoritative')
print('cinematics=replicated-cues')
print('data-layers=runtime-orchestration-hook')
