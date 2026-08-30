from pathlib import Path
import re, sys
ROOT=Path(__file__).resolve().parents[1]
required=[
 'Source/ArabiaStrikeWorldWar/Public/AI/ASSquadComponent.h',
 'Source/ArabiaStrikeWorldWar/Private/AI/ASSquadComponent.cpp',
 'Source/ArabiaStrikeWorldWar/Public/Combat/ASWeaponInventoryComponent.h',
 'Source/ArabiaStrikeWorldWar/Private/Combat/ASWeaponInventoryComponent.cpp',
 'Source/ArabiaStrikeWorldWar/Public/Combat/ASGrenade.h',
 'Source/ArabiaStrikeWorldWar/Private/Combat/ASGrenade.cpp',
 'Source/ArabiaStrikeWorldWar/Public/Vehicles/ASVehicleTurretComponent.h',
 'Source/ArabiaStrikeWorldWar/Public/Vehicles/ASHelicopterPawn.h',
 'Source/ArabiaStrikeWorldWar/Public/AI/ASBossWeakPoint.h',
 'docs/PHASE3_TACTICAL_WARFARE.md'
]
errors=[]
for rel in required:
 p=ROOT/rel
 if not p.exists() or p.stat().st_size<40: errors.append(f'missing/empty: {rel}')
markers={
 'ServerInteract':'Source/ArabiaStrikeWorldWar/Public/Player/ASCharacter.h',
 'ServerThrowGrenade':'Source/ArabiaStrikeWorldWar/Public/Player/ASCharacter.h',
 'bDowned':'Source/ArabiaStrikeWorldWar/Public/Player/ASCharacter.h',
 'ReplicatedUsing=OnRep_Eliminated':'Source/ArabiaStrikeWorldWar/Public/Player/ASCharacter.h',
 'ClearTimer(BleedoutTimer)':'Source/ArabiaStrikeWorldWar/Private/Player/ASCharacter.cpp',
 'HandlePlayerEliminated':'Source/ArabiaStrikeWorldWar/Private/Player/ASCharacter.cpp',
 'RespawnDelay':'Source/ArabiaStrikeWorldWar/Public/Game/ASGameMode.h',
 'PendingRespawnTimers':'Source/ArabiaStrikeWorldWar/Public/Game/ASGameMode.h',
 'RestartPlayer(PlayerController)':'Source/ArabiaStrikeWorldWar/Private/Game/ASGameMode.cpp',
 'SetRespawnState':'Source/ArabiaStrikeWorldWar/Public/Player/ASPlayerController.h',
 'ServerEquipSlot':'Source/ArabiaStrikeWorldWar/Public/Combat/ASWeaponInventoryComponent.h',
 'ApplyNearMissSuppression':'Source/ArabiaStrikeWorldWar/Private/Combat/ASWeaponComponent.cpp',
 'EASTacticalState::Flank':'Source/ArabiaStrikeWorldWar/Private/AI/ASSoldierAIController.cpp',
 'ServerFire':'Source/ArabiaStrikeWorldWar/Public/Vehicles/ASVehicleTurretComponent.h',
 'RegisterWeakPoint':'Source/ArabiaStrikeWorldWar/Public/AI/ASBossCharacter.h'
}
for token,rel in markers.items():
 if token not in (ROOT/rel).read_text(encoding='utf-8'): errors.append(f'marker missing {token} in {rel}')
# simple delimiter sanity, excluding generated macros/strings semantics.
for p in (ROOT/'Source').rglob('*'):
 if p.suffix not in {'.h','.cpp','.cs'}: continue
 t=p.read_text(encoding='utf-8',errors='ignore')
 if t.count('{')!=t.count('}'): errors.append(f'brace mismatch: {p.relative_to(ROOT)}')
# accidental secrets baseline
secret_re=re.compile(r'(?i)(client_secret|private_key|password)\s*[=:]\s*["\']?[^\s"\']{8,}')
for p in ROOT.rglob('*'):
 if p.is_file() and p.suffix.lower() in {'.ini','.yml','.yaml','.json','.md','.cpp','.h','.cs'}:
  txt=p.read_text(encoding='utf-8',errors='ignore')
  if secret_re.search(txt) and 'example' not in p.name.lower(): errors.append(f'possible secret: {p.relative_to(ROOT)}')
if errors:
 print('ASWW PHASE3 PREFLIGHT: FAIL')
 for e in errors: print(' -',e)
 sys.exit(1)
print('ASWW PHASE3 PREFLIGHT: PASS')
print('interaction=server-validated')
print('coop=downed-revive')
print('ai=suppression-flank')
print('vehicles=hummer-turret-helicopter')
print('boss=weakpoints-phases')
