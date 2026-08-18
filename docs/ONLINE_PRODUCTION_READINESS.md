# Online Production Readiness Checklist

The project currently uses `OnlineServicesNull` for local, backend-free development. `OnlineServicesEOS` and `OnlineServicesEOSGS` remain disabled. This is not production identity, matchmaking or service readiness.

No EOS product configuration or credentials are stored in the repository. Do not enable EOS plugins until an owned Epic Online Services product, environments, policies and secret-delivery path exist.

## Required gates

| Capability | Production evidence required | Current state |
|---|---|---|
| Identity and authentication | Account flow, token refresh/revocation, age/region policy and failure recovery | BLOCKED — provider not configured |
| Sessions and lobbies | Create/join/leave, invites, ownership migration and stale-session cleanup | BLOCKED |
| Server discovery | Authenticated allocation and healthy dedicated-server registration | BLOCKED |
| Matchmaking | Queue policy, party constraints, cancellation, timeout and regional placement | BLOCKED |
| Reconnect | Expiring reconnect grants, authoritative state restoration and duplicate-session rejection | NOT_TESTED |
| Rate limiting | Per-account/IP/service budgets and abuse response | PARTIAL — per-controller server chat cooldown/burst limiter implemented; account/IP/service limits remain pending |
| Chat spam protection | Server-side message rate/size limits and flood escalation | IMPLEMENTED_NOT_RUNTIME_VERIFIED — length, whitespace, channel, cooldown and bounded-burst policy is enforced before broadcast; multiplayer evidence pending |
| Mute and block | Persistent user controls enforced across text/voice surfaces | NOT_IMPLEMENTED |
| Reports and moderation | Evidence-safe report flow, case status and operator audit log | NOT_IMPLEMENTED |
| Profanity/abuse controls | Language-aware policy, appeals and false-positive review | NOT_IMPLEMENTED |
| Privacy and retention | Data inventory, purpose, consent, retention/deletion and access controls | NOT_REVIEWED |
| Regional review | Data residency, sanctions, age rating and applicable legal review | NOT_REVIEWED |
| Server health | Readiness/liveness, crash capture, deploy rollback and incident alerts | NOT_IMPLEMENTED |
| Server capacity | Measured concurrency, queue thresholds, autoscaling and cost guardrails | NOT_TESTED |

## Credential and deployment rules

- Keep real values out of `Config/EOS.example.ini`; it is comments-only guidance.
- Store environment-specific credentials in an approved secret manager and inject them at deployment.
- Never put bearer tokens, client secrets or private service URLs in source, Web assets, command output or committed runtime evidence.
- Separate development, staging and production products and permissions.
- Restrict Pixel Streaming origins, require short-lived session authorization, isolate GPU sessions and cap session duration/cost.
- Keep `PIXEL_STREAMING_URL` empty until the authenticated production frontend and rollback plan are ready.

## Release acceptance

Production readiness requires real service test evidence for every gate above, security/privacy review, load and failure testing, moderation operations, capacity alarms and a rehearsed rollback. Static source checks cannot mark this checklist complete.
