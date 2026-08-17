# Web and Unreal Verification Receipt

Verification date: 2026-08-17 (Asia/Riyadh)

Branch: `codex/asww-development`

Source revision before this receipt: `bf2ba3ac86ae01a67b170a137a0e19651a53aef8`

## Track A — Web

- Entry point: `Web/index.html`
- Stylesheet: `Web/app.css`
- Launcher logic: `Web/app.js`
- GitHub Pages workflow: `.github/workflows/deploy-pages.yml`
- Pages artifact scope: `Web` only
- Repository base path: `/arabiastrike.worldwar/`
- Pixel Streaming configuration: `PIXEL_STREAMING_URL` exists as one empty deployment value and must be set to the production frontend URL.
- Offline behavior: the launcher presents `GAME SERVER OFFLINE` when no backend is configured or reachable.

The Web delivery preflight and local repository-subpath HTTP checks passed. No external CDN or localhost production endpoint is present.

## Track B — Unreal Engine

Executed command:

```powershell
powershell -ExecutionPolicy Bypass -File .\BuildScripts\verify_unreal_local.ps1
```

Exact result:

```text
UE_VERSION=NOT_FOUND
UE_ROOT=NOT_FOUND
UNREAL_EDITOR=NOT_FOUND
BUILD_BAT=NOT_FOUND
RUN_UAT=NOT_FOUND
UNREAL_BUILD_TOOL=NOT_FOUND
PREFLIGHT_RESULTS=BASE=PASS,PHASE2=PASS,PHASE3=PASS,PHASE4=PASS,PHASE5=PASS,STATIC_CPP_SANITY=PASS
UBT_RESULT=NOT_RUN_NO_VALID_UE58
UHT_RESULT=NOT_RUN_NO_VALID_UE58
EDITOR_BUILD_RESULT=NOT_RUN_NO_VALID_UE58
CLIENT_BUILD_RESULT=NOT_RUN_NO_VALID_UE58
SERVER_BUILD_RESULT=NOT_RUN_NO_VALID_UE58
OVERALL_RESULT=FAIL
```

The verifier exited with code `1`, as designed when UE 5.8 is unavailable. No UHT/UBT build failure logs were generated because none of the three build targets could start. Local diagnostic output is under `Saved/Verification/Local/`, including `verification_summary.txt` and the six preflight logs; `Saved/` is intentionally not committed.

No Unreal compile, editor, PIE, packaging, multiplayer, or runtime success is claimed by this receipt.
