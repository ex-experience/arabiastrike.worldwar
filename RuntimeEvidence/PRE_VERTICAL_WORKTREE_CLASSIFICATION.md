# Pre-Vertical Worktree Classification

Captured: 2026-08-29 (Asia/Riyadh)

Branch: `backup/asww-local-aaa-runtime-pre-vertical-20260829`

Baseline HEAD: `b4185e92a33e2a27b86dcd1d3272d3d2537b242a`

## Snapshot totals

- Tracked files modified: 32.
- Non-ignored untracked files: 329.
- Non-ignored untracked bytes: 129,951,785.
- Largest untracked file: `Content/Characters/Mannequins/Textures/Manny/T_Manny_02_BN.uasset` (20,999,487 bytes).
- Generated Unreal folders (`Binaries`, `DerivedDataCache`, `Intermediate`, `Saved`, packaged/staged outputs) remain on disk and are intentionally excluded by `.gitignore`.

## Classification

### Production source and configuration

- `Source/`: 23 tracked modifications plus the new `ASPlayerCharacterV2` source/header pair.
- `Config/`: three tracked runtime/default-map/input changes.
- `ArabiaStrikeWorldWar.uproject`: unchanged at this gate.

### Production Unreal content

- Jeddah World Partition map, its two HLOD layer assets, and 19 External Actor packages.
- Player mannequin, animation, input, weapon, first-person, prototyping, and XR packages.
- The critical-content manifest fingerprints 194 map/player/input/weapon packages totaling 128,268,860 bytes.

### Build, validation, and recovery tooling

- `BuildScripts/`: four tracked modifications.
- `ci/static_cpp_sanity.py`: one tracked modification.
- Root `ASWW_*.ps1` scripts and the current AAA implementation sequence: preservation-worthy QA/recovery history and reproducible runtime procedures.
- `Samples/PixelStreaming2/WebServers`: two project-support scripts, not build output.

### Preservation evidence

- Status, tracked/staged diff inventories, log excerpt, critical SHA-256 manifest, template provenance, Jeddah inspection, Player V2 analysis, and distribution review under `RuntimeEvidence/`.
- These named evidence files are intentionally force-added despite the directory's default evidence-ignore rule.

### Excluded generated/local state

- No ignored build output, editor cache, package, transient logs, local credentials, or IDE state will be staged.
- No delete, reset, clean, broad restore, or stash operation is part of this preservation gate.

## Preservation decision

All 32 tracked modifications and all 329 non-ignored untracked files belong to the recoverable local AAA runtime snapshot. They are staged explicitly by scoped paths on the backup branch; ignored generated/local state remains on disk but outside Git.
