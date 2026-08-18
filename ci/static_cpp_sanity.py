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

# Chat flood protection is security-sensitive. These checks prove policy structure only;
# they are not runtime, network, UHT or UBT evidence.
chat_header_path=SRC/'Public/Player/ASPlayerController.h'
chat_cpp_path=SRC/'Private/Player/ASPlayerController.cpp'
chat_header=chat_header_path.read_text(encoding='utf-8',errors='ignore')
chat_cpp=chat_cpp_path.read_text(encoding='utf-8',errors='ignore')
chat_markers={
    'reliable server chat RPC': 'UFUNCTION(Server,Reliable) void ServerSendChat',
    '180 character server cap': 'MaxChatMessageLength = 180',
    'per-controller cooldown': 'ChatMinimumIntervalSeconds',
    'bounded burst window': 'ChatBurstWindowSeconds',
    'bounded burst count': 'ChatBurstMessageLimit',
    'bounded violation tracking': 'TotalChatPolicyViolations',
    'controller teardown reset': 'virtual void EndPlay',
    'future moderation hook': 'HandleChatPolicyViolation',
}
for label,marker in chat_markers.items():
    if marker not in chat_header:
        errors.append(f'chat limiter missing {label}: {chat_header_path.relative_to(ROOT)}')

server_chat_start=chat_cpp.find('void AASPlayerController::ServerSendChat_Implementation')
server_chat_end=chat_cpp.find('void AASPlayerController::ClientReceiveChat_Implementation', server_chat_start)
server_chat_block=chat_cpp[server_chat_start:server_chat_end] if server_chat_start >= 0 and server_chat_end > server_chat_start else ''
server_chat_markers={
    'server authority check': 'HasAuthority()',
    'server/world monotonic clock': 'World->GetRealTimeSeconds()',
    'channel validation': 'IsValidChatChannel(Channel)',
    'server-side whitespace rejection': 'CleanMessage.IsEmpty()',
    'cooldown and burst gate': 'CanAcceptChatMessage(ServerTime, ViolationReason)',
    'broadcast': 'GameMode->BroadcastChat',
}
for label,marker in server_chat_markers.items():
    if marker not in server_chat_block:
        errors.append(f'chat limiter missing {label}: {chat_cpp_path.relative_to(ROOT)}')
if server_chat_block:
    broadcast_position=server_chat_block.find('GameMode->BroadcastChat')
    for gate in ('IsValidChatChannel(Channel)', 'CleanMessage.IsEmpty()', 'CanAcceptChatMessage(ServerTime, ViolationReason)'):
        gate_position=server_chat_block.find(gate)
        if broadcast_position >= 0 and gate_position >= 0 and gate_position > broadcast_position:
            errors.append(f'chat broadcast occurs before rejection gate: {gate}')
    for channel_case in ('case EASChatChannel::Global:', 'case EASChatChannel::Squad:', 'case EASChatChannel::Proximity:', 'default:'):
        if channel_case not in server_chat_block:
            errors.append(f'chat channel validation is incomplete: {channel_case}')
chat_rpc_declarations=re.findall(r'UFUNCTION\(Server,Reliable\)\s+void\s+ServerSendChat\s*\(([^)]*)\)', chat_header)
if len(chat_rpc_declarations) != 1:
    errors.append('chat RPC must have exactly one Reliable server declaration')
elif re.search(r'(?i)time|timestamp', chat_rpc_declarations[0]):
    errors.append('chat RPC must not accept a client-controlled timestamp')
chat_state_start=chat_header.find('MaxChatMessageLength')
chat_state=chat_header[chat_state_start:] if chat_state_start >= 0 else ''
if 'TArray<' in chat_state or 'TMap<' in chat_state:
    errors.append('chat limiter state must not use dynamically growing containers')
if errors:
    print('ASWW STATIC C++ SANITY: FAIL')
    for e in errors: print(' -',e)
    sys.exit(1)
print('ASWW STATIC C++ SANITY: PASS')
print(f'headers={len(list(SRC.rglob("*.h")))} cpp={len(list(SRC.rglob("*.cpp")))}')
print('chat_rate_limit=STATIC_POLICY_CHECK_PASS_RUNTIME_NOT_VERIFIED')
