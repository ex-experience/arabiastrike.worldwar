from pathlib import Path
import json, sys
R=Path(__file__).resolve().parents[1]
required=[
'ArabiaStrikeWorldWar.uproject','Source/ArabiaStrikeWorldWar/Public/Combat/ASWeaponDefinition.h','Source/ArabiaStrikeWorldWar/Public/Combat/ASProjectile.h','Source/ArabiaStrikeWorldWar/Public/Interaction/ASInteractable.h','Source/ArabiaStrikeWorldWar/Public/Vehicles/ASPilotableVehiclePawn.h','Source/ArabiaStrikeWorldWar/Public/AI/ASSoldierCharacter.h','Source/ArabiaStrikeWorldWar/Public/Mission/ASMissionDirector.h']
missing=[x for x in required if not (R/x).exists()]
if missing: print('PHASE2 FAIL missing:',*missing,sep='\n- ');sys.exit(2)
up=json.loads((R/'ArabiaStrikeWorldWar.uproject').read_text())
assert str(up.get('EngineAssociation','')).startswith('5.8')
cpp='\n'.join(p.read_text(errors='ignore') for p in (R/'Source').rglob('*.cpp'))
for token in ['ServerFire','DOREPLIFETIME','AASMissionDirector','AASPilotableVehiclePawn']:
    if token not in cpp: print('PHASE2 FAIL token',token);sys.exit(3)
print('ASWW PHASE2 PREFLIGHT: PASS')
print('combat=server-authoritative')
print('mission=replicated')
print('vehicle=pilotable-scaffold')
