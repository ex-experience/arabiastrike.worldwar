# Pixel Streaming 2 Gateway

Pixel Streaming is an optional browser-access path, not the source repository hosting model.

Production topology:

Browser → authenticated web portal → signalling/SFU layer → GPU Unreal instance → game/backend services.

`PixelStreaming2` is enabled in `ArabiaStrikeWorldWar.uproject`. This is project configuration only: plugin loading, Unreal compilation, packaging, signalling, media transport and browser gameplay are not verified while UE 5.8 and a real backend are unavailable. Keep `PIXEL_STREAMING_URL` empty until the production frontend is live.

The launcher distinguishes endpoint reachability from an active game session. A no-CORS response can move the UI only to `REACHABLE`. The launcher may enter `CONNECTED` and display 100% only after the embedded frontend sends a validated `postMessage`:

```text
type: ASWW_PIXEL_STREAMING_STATE
state: connected
sessionId: value from the aswwLauncherSession query parameter
```

The message must come from the iframe window and the configured frontend origin. Supported lifecycle states are `negotiating`, `connected`, `disconnected`, `reconnecting` and `failed`. The frontend integration must echo the per-launch session identifier so messages from replaced sessions are rejected.

Security gates include authentication, strict allowed origins, short-lived session authorization, session lifecycle, GPU isolation, rate limits and cost controls. Never put credentials or bearer tokens in `Web/app.js` or the repository.
