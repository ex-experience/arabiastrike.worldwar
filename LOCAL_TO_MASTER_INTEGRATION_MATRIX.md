# Local-to-Master Integration Matrix

Status: pre-vertical recovery gate, 2026-08-29

Source branch: `backup/asww-local-aaa-runtime-pre-vertical-20260829`

Rule: this matrix records what is preserved and how it relates to the locked Master Production System. It does not authorize a merge to `main` or start vertical-slice implementation.

| Local cluster | Verified local evidence | Locked master target | Integration decision | Required gate before promotion |
|---|---|---|---|---|
| UE 5.8 native project | Editor and Game Development builds pass on UE 5.8.1 | M1, clean reproducible UE 5.8 builds | Keep as the build baseline | Pin/prefer a UE-supported MSVC toolchain; keep both native targets green |
| Jeddah map | Real World Partition map, 19 descriptors, two HLOD layer assets, map check 0/0, cook/package pass | Recognizable Al-Balad/Jeddah vertical-slice cluster with streaming/HLOD budgets | Keep as a technical world foundation, not production art acceptance | Geographic/cultural art review, collision/nav, lighting, data layers, HLOD/performance validation |
| `AASPlayerCharacterV2` | Default pawn, Manny mesh, rifle attachment, packaged startup marker pass | Canonical Hussam hero and modular locomotion/stance/traversal components | Keep as a transitional test pawn | Replace placeholder hero presentation; split state into target components; visual acceptance |
| Player input | V2 binds legacy axes/actions; template Enhanced Input assets exist | Fully remappable PC-first Enhanced Input contexts | Migrate; legacy binding is not the target architecture | `IMC_OnFoot`, `IMC_Combat`, vehicle/UI contexts, remapping and device-switch tests |
| Stance and locomotion | Walk/sprint/crouch/aim shell; crouch-based fake prone | Standing/crouch/true prone, Motion Matching, Pose Search, Choosers | Preserve prototype behavior; replace fake prone | Dedicated prone state/animation/capsule/network tests and animation acceptance |
| Slide and mantle | Local slide state; mantle prototype moves actor directly with `SetActorLocation` | Contextual traversal with validation, Motion Warping, root motion where appropriate | Rework before multiplayer use | Server validation for range/state/timing; collision and correction tests |
| Combat delegation | V2 delegates fire/reload/inventory to existing authoritative components | Server validates state, timing, resources and outcomes | Keep the authoritative component foundation | Interactive fire/reload/damage proof, two-client/dedicated-server acceptance, remove temporary QA markers |
| Rifle presentation | Epic Example rifle attaches to `HandGrip_R`; packaged mesh/equip markers pass | Production weapon handling, ADS/recoil/ballistics/attachments and polished feedback | Keep only as a licensed placeholder/reference | Original/licensed production weapon art, tactical upper-body AnimBP, muzzle/audio/reload feedback |
| Animation | Epic mannequin and Unarmed AnimBP load; rifle animations/templates are present | Motion Matching plus armed/aim/injured/suppressed layers | Use as a legal technical scaffold | Production animation database, retargeting, turn/pivot/aim/prone and random-frame quality review |
| Epic template assets | Exact provenance to UE 5.8 Templates/TemplateResources and FeaturePacks; EULA Examples distribution reviewed | Original or properly licensed production assets | Safe to preserve publicly under Epic's terms; do not relicense as project-owned art | Keep provenance/notices; separately review every later Fab/Marketplace/third-party asset |
| Variant Shooter / First Person / XR content | Exact or near-exact UE template copies; not all are used by the runtime pawn | Minimal, intentional production dependency graph | Retain in backup; selectively integrate only proven dependencies | Reference audit and unused-content reduction before production branch import |
| AI/mission/world scaffolding | Static preflights pass; PIE sees three enemies | Tactical StateTree AI, squad coordination, living Jeddah systems | Keep code scaffolding; completion claims remain blocked | Played AI/mission/world-event acceptance, networking, budgets and regression tests |
| HLOD/streaming | World Partition initializes and packages; HLOD layer packages exist | Explicit LOD/HLOD/streaming/scalability policy | Keep, status incomplete | Runtime cell streaming, memory/frame-time capture, HLOD visual QA |
| Packaging | Separate Development package and 30-second startup smoke pass | Reproducible packaged PC demo | Keep as the recovery baseline | Explicitly disallow `EOS.example.ini`; Shipping build; install/launch regression |
| Multiplayer | Server target and authority patterns pass static checks only | Server-authoritative multiplayer baseline | Preserve but do not mark accepted | Dedicated server build/package, two or more clients, possession/combat/revive/vehicle validation |
| Pixel Streaming/web | Static delivery gates pass; production endpoint remains empty | Optional verified Pixel Streaming delivery | Keep decoupled from core vertical-slice acceptance | Real backend, WebRTC session, authentication/security, latency and reconnect testing |
| QA/recovery scripts | Full local script history preserved; selected map/PIE/package gates run | Small reproducible canonical QA suite | Archive history; promote only maintained entry points | Parameterize branch/output paths, remove duplicate scripts, document supported commands |
| Temporary QA telemetry | Manny/rifle/equip/fire/reload diagnostic markers are present | Production logging with no temporary gate noise | Retain for recovery evidence only | Remove or guard temporary telemetry after interactive gameplay proof and before acceptance merge |

## Promotion order

1. Preserve the backup branch and evidence; do not merge it wholesale to `main`.
2. Selectively integrate build/map/runtime foundations onto the approved development branch.
3. Complete Enhanced Input migration before expanding Player V2 behavior.
4. Replace local-only stance/traversal shortcuts with modular, server-validated implementations.
5. Prove the infantry loop interactively and in packaged multiplayer.
6. Replace Epic placeholders with the canonical Hussam/production asset set while retaining provenance.
7. Meet performance, cultural-authenticity, visual, and Shipping-package gates.
8. Promote only after explicit acceptance; `main` remains untouched until then.
