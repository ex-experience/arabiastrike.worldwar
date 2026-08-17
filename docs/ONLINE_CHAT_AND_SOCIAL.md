# Online, Chat and Social

## Implemented foundation

`ASPlayerController` provides server-routed text chat with:

- Global channel.
- Squad channel via replicated `SquadId`.
- Proximity channel with a 30m game-space radius baseline.
- 180-character server-side message cap.

This is a gameplay transport foundation, not a complete moderation product.

## Required before public launch

- Authenticated identity.
- Rate limits / spam throttling.
- Mute and block lists.
- Report flow.
- Moderation logging and retention policy.
- Regional/legal review.
- Profanity/abuse tooling appropriate to target markets.
- Voice chat moderation controls if voice is enabled.

## EOS gate

The `.uproject` contains EOS plugin entries disabled by default. Enable only after EOS Developer Portal product configuration exists. Never commit secrets.
