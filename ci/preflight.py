from pathlib import Path
import json, re, sys
ROOT=Path(__file__).resolve().parents[1]
required=[
 'ArabiaStrikeWorldWar.uproject',
 'Source/ArabiaStrikeWorldWar.Target.cs',
 'Source/ArabiaStrikeWorldWarServer.Target.cs',
 'Source/ArabiaStrikeWorldWar/ArabiaStrikeWorldWar.Build.cs',
 'Source/ArabiaStrikeWorldWar/Public/Player/ASCharacter.h',
 'Source/ArabiaStrikeWorldWar/Private/Player/ASCharacter.cpp',
 'Source/ArabiaStrikeWorldWar/Public/Combat/ASHealthComponent.h',
 'Source/ArabiaStrikeWorldWar/Public/Combat/ASWeaponComponent.h',
 'BuildScripts/verify_unreal_local.ps1',
 'BuildScripts/verify_delivery_tracks.ps1',
 'BuildScripts/build_android.ps1',
 'BuildScripts/build_ios.ps1',
 'ci/preflight_web_delivery.py',
 'ci/preflight_native_delivery.py',
 'Web/index.html', 'Web/app.css', 'Web/app.js',
 'Config/DefaultEngine.ini', 'Config/DefaultInput.ini'
]
errors=[]
for item in required:
    if not (ROOT/item).exists(): errors.append(f'missing: {item}')
try:
    data=json.loads((ROOT/'ArabiaStrikeWorldWar.uproject').read_text(encoding='utf-8'))
    if data.get('EngineAssociation')!='5.8': errors.append('EngineAssociation must be 5.8')
    mods={m.get('Name') for m in data.get('Modules',[])}
    if 'ArabiaStrikeWorldWar' not in mods: errors.append('runtime module missing')
except Exception as e: errors.append(f'uproject invalid: {e}')

verifier_path=ROOT/'BuildScripts/verify_unreal_local.ps1'
if verifier_path.exists():
    verifier=verifier_path.read_text(encoding='utf-8',errors='ignore')
    verifier_markers=[
        'ci/preflight.py', 'ci/preflight_phase2.py', 'ci/preflight_phase3.py',
        'ci/preflight_phase4.py', 'ci/preflight_phase5.py', 'ci/static_cpp_sanity.py',
        'ArabiaStrikeWorldWarEditor', 'ArabiaStrikeWorldWar', 'ArabiaStrikeWorldWarServer',
        'UnrealEditor.exe', 'Build.bat', 'RunUAT.bat', 'UnrealBuildTool'
    ]
    for marker in verifier_markers:
        if marker not in verifier: errors.append(f'local Unreal verifier marker missing: {marker}')

secret_patterns=[re.compile(r'(?i)(clientsecret|secretkey|privatekey)\s*[=:]\s*[^;\s]+')]
for p in ROOT.rglob('*'):
    if p.is_file() and p.suffix.lower() in {'.ini','.json','.yml','.yaml','.cs','.cpp','.h','.md'}:
        try: txt=p.read_text(encoding='utf-8')
        except: continue
        if 'EOS.example.ini' not in str(p):
            for pat in secret_patterns:
                if pat.search(txt): errors.append(f'possible secret in {p.relative_to(ROOT)}')

if errors:
    print('ASWW PRE-FLIGHT: FAIL')
    for e in errors: print(' -',e)
    sys.exit(1)
print('ASWW PRE-FLIGHT: PASS')
print('engine=5.8 runtime=C++ networking=server-authoritative target=dedicated-server')
