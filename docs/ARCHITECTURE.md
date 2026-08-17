# Architecture Baseline

## Runtime authority

The dedicated server owns authoritative health, weapon fire rate, damage, chat routing, mission state and world events. Clients request actions; they do not decide final combat results.

## First scaling baseline

Use standard Unreal replication for Slice 01 and measure:

- 8 players: required pass.
- 16 players: target pass.
- 32 players: profiling gate.

Do not enable Iris and Replication Graph simultaneously. Choose one later based on profiling and feature maturity.

## Modules

- Player: locomotion / camera / controller / player state.
- Combat: health, hitscan weapon foundation, later inventory/abilities.
- Online: chat and backend readiness.
- Vehicles: replicated seat reservation foundation.
- World: server-controlled world events.
- AI: boss phase foundation.

## Future production services

Authentication, lobbies, sessions, social, stats and leaderboards can move to EOS after a product is registered and secrets are provisioned. Dedicated game servers should be orchestrated outside the client build.
