# Pre-Vertical Packaged Baseline

Validated: 2026-08-29 (Asia/Riyadh)

Preservation branch: `backup/asww-local-aaa-runtime-pre-vertical-20260829`

Safety snapshot commit: `1cd7abaabcd00de5ac74bb895052813e308dd886`

The only tracked change made after that safety snapshot was a minimal quoting fix in `BuildScripts/run_jeddah_pie_smoke.ps1`. It changes test-process argument handling only; no gameplay source, configuration, map, External Actor, or content package was changed.

## Host and native builds

- Unreal Engine: 5.8.1.
- Visual Studio: 2026 Community; MSVC 14.51.36256.
- Windows SDK: 10.0.26100.0.
- Host prerequisite gate: PASS.
- `ArabiaStrikeWorldWarEditor Win64 Development`: PASS, real compile/link, exit 0.
- `ArabiaStrikeWorldWar Win64 Development`: PASS, real compile/link, exit 0.
- Compiler caution: MSVC 14.51 is newer than UE 5.8's preferred 14.50 toolchain.
- Engine/PCG deprecation warnings were emitted; no project compile errors were emitted.

## Map and PIE

- `Jeddah_RedSea_Assault.umap`: real UE package and real Editor load PASS.
- World Partition: PASS.
- Actor descriptors: 19 found, none missing.
- Map check: 0 errors, 0 warnings.
- Critical asset post-load integrity: 194/194 SHA-256 fingerprints unchanged.
- PIE automation: PASS.
- PIE evidence: `ASWW_PIE_POSSESSED_PLAYERS=1`, `ASWW_PIE_ENEMY_COUNT=3`, `ASWW_PIE_SMOKE=PASS`, automation result Success.
- PIE scope is deliberately limited to startup, possession, and actor presence; it does not prove the complete gameplay feature matrix.

## New Win64 package

Archive: `BuildOutput/PreVertical_20260829_1cd7aba/Windows`

Staging: `D:/ASWW_PRE_VERTICAL_STAGE_20260829_1cd7aba/Windows`

- BuildCookRun: PASS, exit 0, 5m17s.
- Cook: 542 packages saved, 0 errors, 4 warnings (two repeated project QA markers for Manny/rifle proof).
- Jeddah World Partition cook generation: PASS.
- Pak and IoStore: PASS; compression enabled; encryption/signing disabled for this Development baseline.
- Archive: 52 files, 1,012,864,597 bytes.
- The previous `BuildOutput/Client` and `D:/ASWW_STAGE` outputs were not deleted or replaced.
- Packaging warning: comment-only `Config/EOS.example.ini` is staged because it is not explicitly allowed or denied. The security audit confirms it contains no credential values, but the production packaging configuration should explicitly disallow it.

### Artifact fingerprints

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `ArabiaStrikeWorldWar.exe` | 171,520 | `4C436AC6B66FAE305ACB0FA7EBD21458E520F9D70B17801DB94E3E4BA095D720` |
| `ArabiaStrikeWorldWar/Binaries/Win64/ArabiaStrikeWorldWar.exe` | 358,425,088 | `0F2750FDCBE51759F0BDE87B18CED4FD5E8691D33EAFD3B9222259C8040C16B6` |
| `ArabiaStrikeWorldWar/Content/Paks/ArabiaStrikeWorldWar-Windows.pak` | 10,711,446 | `1884192E4D61C889799D356C64FC2A40AE7815EAC5173B60A40BED5064CF8A2A` |
| `ArabiaStrikeWorldWar/Content/Paks/ArabiaStrikeWorldWar-Windows.ucas` | 131,267,120 | `D76C713B94EDD75DCE91680F2763646784E13A530E71ED4313356819FBD22F21` |
| `ArabiaStrikeWorldWar/Content/Paks/ArabiaStrikeWorldWar-Windows.utoc` | 140,941 | `6B9C5AB1B01896280F16462951E9175B6D7CBEA4FA240190FA464402EC6BCFDA` |
| `ArabiaStrikeWorldWar/Content/Paks/global.ucas` | 3,347,840 | `99237F1D50962CB6CE1851FB9A03D2662F07656EE7CEB43A9833CAECC30DC12D` |
| `ArabiaStrikeWorldWar/Content/Paks/global.utoc` | 818 | `3445125FA947D19154C16B62E009C09E5A50C248A57B58E907091DCA719F791D` |

## Packaged startup smoke

- Direct packaged game binary survived the 30-second NullRHI smoke window.
- Jeddah Browse, LoadMap, and World-Up markers: PASS.
- `ASGameMode`, World Partition, Manny, non-empty rifle mesh, and accepted rifle-definition equip markers: PASS.
- Fatal, crash, and missing-content markers: none.
- Result: `PACKAGED_STARTUP_SMOKE=PASS`.

## Repository gates

All nine current preflight scripts passed: repository phases 1–5, static C++ sanity, web delivery, native delivery, and security audit.

Security audit: 243 text files scanned; EOS providers disabled; Pixel Streaming URL empty; no recognized credential material.

## Not proven by this gate

- Human-visible/interactive fire, reload, ADS, stance, slide, mantle, damage, death, respawn, or vehicle behavior.
- True prone (the current Player V2 implementation uses a crouch-based approximation).
- Packaged multiplayer or dedicated-server acceptance.
- Performance, scalability, HLOD visual quality, streaming budgets, or Shipping configuration.
- Canonical Hussam hero quality, production rifle animation layer, or vertical-slice art acceptance.

The preserved snapshot is therefore a valid buildable/packageable pre-vertical baseline, not an accepted vertical slice.
