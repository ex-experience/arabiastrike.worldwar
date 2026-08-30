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

# Sprint and dash authority checks prove source structure only. Runtime correction,
# prediction, cooldown and remote movement behavior still require real multiplayer PIE.
character_header_path=SRC/'Public/Player/ASCharacter.h'
character_cpp_path=SRC/'Private/Player/ASCharacter.cpp'
character_header=character_header_path.read_text(encoding='utf-8',errors='ignore')
character_cpp=character_cpp_path.read_text(encoding='utf-8',errors='ignore')

movement_markers={
    'fixed walk speed': 'float WalkSpeed = 520.f;',
    'fixed sprint speed': 'float SprintSpeed = 820.f;',
    'boolean sprint server RPC': 'void ServerSetSprinting(bool bWantsToSprint);',
    'parameterless dash server RPC': 'void ServerDash();',
    'custom character movement component': 'class ARABIASTRIKEWORLDWAR_API UASCharacterMovementComponent',
    'compressed sprint flag decode': 'UpdateFromCompressedFlags(uint8 Flags)',
    'server-only dash timestamp': 'LastDashServerTimeSeconds',
}
for label,marker in movement_markers.items():
    if marker not in character_header:
        errors.append(f'movement authority missing {label}: {character_header_path.relative_to(ROOT)}')

prediction_markers={
    'saved move type': 'class FSavedMove_ASCharacter',
    'compressed sprint flag': 'FLAG_Custom_0',
    'move combination boundary': 'bSavedWantsToSprint != NewCharacterMove->bSavedWantsToSprint',
    'saved sprint intent': 'bSavedWantsToSprint = Movement && Movement->HasSprintIntent()',
    'custom prediction allocation': 'new FSavedMove_ASCharacter()',
    'custom movement installation': 'SetDefaultSubobjectClass<UASCharacterMovementComponent>',
}
for label,marker in prediction_markers.items():
    if marker not in character_cpp:
        errors.append(f'movement prediction missing {label}: {character_cpp_path.relative_to(ROOT)}')

sprint_rpc_match=re.search(
    r'UFUNCTION\(Server,\s*Reliable\)\s*void\s+ServerSetSprinting\s*\(([^)]*)\)',
    character_header,
    re.S,
)
if not sprint_rpc_match:
    errors.append('sprint intent must have exactly one Reliable server declaration')
else:
    sprint_parameters=sprint_rpc_match.group(1).strip()
    if sprint_parameters != 'bool bWantsToSprint':
        errors.append('sprint RPC may accept only a boolean intent')
    if re.search(r'(?i)speed|velocity|time|timestamp', sprint_parameters):
        errors.append('sprint RPC accepts a client-controlled speed, velocity or timestamp')

server_sprint_start=character_cpp.find('void AASCharacter::ServerSetSprinting_Implementation')
server_sprint_end=character_cpp.find('void AASCharacter::Dash()', server_sprint_start)
server_sprint_block=character_cpp[server_sprint_start:server_sprint_end] if server_sprint_start >= 0 and server_sprint_end > server_sprint_start else ''
for marker in ('HasAuthority()', '!bDowned', '!bEliminated', 'SetSprintIntent('):
    if marker not in server_sprint_block:
        errors.append(f'server sprint validation missing: {marker}')

dash_input_start=character_cpp.find('void AASCharacter::Dash()')
dash_server_start=character_cpp.find('void AASCharacter::ServerDash_Implementation()', dash_input_start)
dash_input_block=character_cpp[dash_input_start:dash_server_start] if dash_input_start >= 0 and dash_server_start > dash_input_start else ''
dash_server_end=character_cpp.find('void AASCharacter::FirePressed()', dash_server_start)
dash_server_block=character_cpp[dash_server_start:dash_server_end] if dash_server_start >= 0 and dash_server_end > dash_server_start else ''
if 'LaunchCharacter(' in dash_input_block:
    errors.append('dash input performs a client-local LaunchCharacter')
for label,marker in {
    'authority check': 'HasAuthority()',
    'downed rejection': 'bDowned',
    'eliminated rejection': 'bEliminated',
    'world monotonic clock': 'World->GetTimeSeconds()',
    'server cooldown timestamp': 'LastDashServerTimeSeconds',
    'server-owned cooldown': 'DashCooldown',
    'authoritative orientation': 'GetActorForwardVector()',
    'authoritative launch': 'LaunchCharacter(',
}.items():
    if marker not in dash_server_block:
        errors.append(f'server dash missing {label}: {marker}')

for function_name in ('EnterDownedState', 'FinalizeBleedout', 'InitializeForRespawn'):
    start=character_cpp.find(f'void AASCharacter::{function_name}')
    next_function=character_cpp.find('\nvoid AASCharacter::', start + 1)
    block=character_cpp[start:next_function if next_function >= 0 else None] if start >= 0 else ''
    if 'ForceSprintOff();' not in block:
        errors.append(f'{function_name} does not force sprint off')
if 'LastDashServerTimeSeconds = -1000.0;' not in character_cpp[character_cpp.find('void AASCharacter::InitializeForRespawn'):]:
    errors.append('respawn does not reset the server dash cooldown state')
if errors:
    print('ASWW STATIC C++ SANITY: FAIL')
    for e in errors: print(' -',e)
    sys.exit(1)
print('ASWW STATIC C++ SANITY: PASS')
print(f'headers={len(list(SRC.rglob("*.h")))} cpp={len(list(SRC.rglob("*.cpp")))}')
print('chat_rate_limit=STATIC_POLICY_CHECK_PASS_RUNTIME_NOT_VERIFIED')
print('movement_authority=STATIC_SAVED_MOVE_AND_SERVER_RPC_CHECK_PASS_RUNTIME_NOT_VERIFIED')
