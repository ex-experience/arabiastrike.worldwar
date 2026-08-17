# Pixel Streaming 2 Gateway

Pixel Streaming is an optional browser-access path, not the source repository hosting model.

Production topology:

Browser → authenticated web portal → signalling/SFU layer → GPU Unreal instance → game/backend services.

For UE 5.8, use Pixel Streaming 2 when the cloud-play milestone starts. Keep it disabled during the first native multiplayer slice to reduce moving parts.

Security gates include authentication, allowed origins, session lifecycle, GPU isolation, rate limits and cost controls.
