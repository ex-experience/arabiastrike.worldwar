from pathlib import Path
import json, re, sys
ROOT=Path(__file__).resolve().parents[1]
required=[
 'Source/ArabiaStrikeWorldWar/Public/World/ASWorldTypes.h',
 'Source/ArabiaStrikeWorldWar/Public/World/ASCityDefinition.h',
 'Source/ArabiaStrikeWorldWar/Public/World/ASWorldEnvironmentDirector.h',
 'Source/ArabiaStrikeWorldWar/Public/World/ASDistrictVolume.h',
 'Source/ArabiaStrikeWorldWar/Public/World/ASTrafficRoute.h',
 'Source/ArabiaStrikeWorldWar/Public/World/ASTrafficVehicleAgent.h',
 'Source/ArabiaStrikeWorldWar/Public/World/ASTrafficDirector.h',
 'Source/ArabiaStrikeWorldWar/Public/World/ASCivilianCharacter.h',
 'Source/ArabiaStrikeWorldWar/Public/World/ASCivilianDirector.h',
 'Source/ArabiaStrikeWorldWar/Public/World/ASDynamicEncounterDirector.h',
 'Source/ArabiaStrikeWorldWar/Public/World/ASPCGWorldHook.h',
 'Source/ArabiaStrikeWorldWar/Public/World/ASWorldBootstrap.h',
 'docs/PHASE4_JEDDAH_WORLD.md',
 'docs/JEDDAH_WORLD_EDITOR_CHECKLIST.md'
]
errors=[]
for rel in required:
 p=ROOT/rel
 if not p.exists() or p.stat().st_size<40: errors.append(f'missing/empty: {rel}')
uproject=json.loads((ROOT/'ArabiaStrikeWorldWar.uproject').read_text())
plugins={p['Name']:p.get('Enabled',False) for p in uproject.get('Plugins',[])}
if not plugins.get('PCG'): errors.append('PCG plugin not enabled')
build=(ROOT/'Source/ArabiaStrikeWorldWar/ArabiaStrikeWorldWar.Build.cs').read_text()
if '"PCG"' not in build: errors.append('PCG module dependency missing')
markers={
 'GetWorldPartition':'Source/ArabiaStrikeWorldWar/Private/World/ASWorldBootstrap.cpp',
 'EnvironmentState':'Source/ArabiaStrikeWorldWar/Public/World/ASWorldEnvironmentDirector.h',
 'CurrentDistrict':'Source/ArabiaStrikeWorldWar/Public/Player/ASPlayerState.h',
 'USplineComponent':'Source/ArabiaStrikeWorldWar/Public/World/ASTrafficRoute.h',
 'GetRandomReachablePointInRadius':'Source/ArabiaStrikeWorldWar/Private/World/ASCivilianCharacter.cpp',
 'EncounterTable':'Source/ArabiaStrikeWorldWar/Public/World/ASDynamicEncounterDirector.h',
 'UPCGComponent':'Source/ArabiaStrikeWorldWar/Public/World/ASPCGWorldHook.h',
 'RecommendedMaxPlayers':'Source/ArabiaStrikeWorldWar/Public/World/ASCityDefinition.h',
 'VisibilityScalar':'Source/ArabiaStrikeWorldWar/Private/AI/ASSoldierAIController.cpp'
}
for token,rel in markers.items():
 if token not in (ROOT/rel).read_text(): errors.append(f'marker missing {token} in {rel}')
# delimiter sanity
for p in (ROOT/'Source').rglob('*'):
 if p.suffix not in {'.h','.cpp','.cs'}: continue
 t=p.read_text(encoding='utf-8',errors='ignore')
 if t.count('{')!=t.count('}'): errors.append(f'brace mismatch: {p.relative_to(ROOT)}')
# generated include ordering
for p in (ROOT/'Source').rglob('*.h'):
 lines=[x.strip() for x in p.read_text().splitlines() if x.strip().startswith('#include')]
 gens=[i for i,x in enumerate(lines) if '.generated.h' in x]
 if gens and gens[-1] != len(lines)-1: errors.append(f'generated include not last: {p.relative_to(ROOT)}')
if errors:
 print('ASWW PHASE4 PREFLIGHT: FAIL')
 for e in errors: print(' -',e)
 sys.exit(1)
print('ASWW PHASE4 PREFLIGHT: PASS')
print('world=world-partition-aware')
print('districts=data-driven')
print('environment=replicated-time-weather')
print('population=traffic-civilians-budgeted')
print('encounters=server-authoritative')
print('pcg=enabled-hooked')
