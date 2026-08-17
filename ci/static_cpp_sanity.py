from pathlib import Path
import re, sys
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'Source/ArabiaStrikeWorldWar'
errors=[]
headers=list((SRC/'Public').rglob('*.h'))+list((SRC/'Private').rglob('*.h'))
local={p.name for p in headers}
local_rel={str(p.relative_to(SRC/'Public')).replace('\\','/') for p in (SRC/'Public').rglob('*.h')}
local_rel|={str(p.relative_to(SRC/'Private')).replace('\\','/') for p in (SRC/'Private').rglob('*.h')}
local_prefixes={'AI','Combat','Game','Interaction','Mission','Online','Player','Vehicles','World','Factions','Cinematics'}
for p in list(SRC.rglob('*.h'))+list(SRC.rglob('*.cpp')):
    txt=p.read_text(encoding='utf-8',errors='ignore')
    if txt.count('{')!=txt.count('}'):
        errors.append(f'brace mismatch: {p.relative_to(ROOT)}')
    if p.suffix=='.h':
        incs=re.findall(r'^#include\s+"([^"]+)"',txt,re.M)
        gen=[i for i,x in enumerate(incs) if x.endswith('.generated.h')]
        if gen and gen[-1]!=len(incs)-1:
            errors.append(f'generated include must be final include: {p.relative_to(ROOT)}')
    for inc in re.findall(r'^#include\s+"([^"]+)"',txt,re.M):
        if inc.endswith('.generated.h'): continue
        first=inc.split('/')[0]
        if first in local_prefixes and inc not in local_rel:
            errors.append(f'local include not found: {inc} referenced by {p.relative_to(ROOT)}')
# Ensure new server-owned world systems never use client RPC authority shortcuts.
world_private=SRC/'Private/World'
for p in world_private.glob('*.cpp'):
    txt=p.read_text(encoding='utf-8',errors='ignore')
    if 'Server' in p.name: continue
    if 'GetFirstPlayerController()->' in txt:
        errors.append(f'unsafe first-player assumption: {p.relative_to(ROOT)}')
if errors:
    print('ASWW STATIC C++ SANITY: FAIL')
    for e in errors: print(' -',e)
    sys.exit(1)
print('ASWW STATIC C++ SANITY: PASS')
print(f'headers={len(list(SRC.rglob("*.h")))} cpp={len(list(SRC.rglob("*.cpp")))}')
