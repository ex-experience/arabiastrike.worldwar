# 12 — ASSET PIPELINE, NAMING & PRODUCTION BUDGETS

## Naming convention
- SK_ Skeletal Mesh
- SM_ Static Mesh
- M_ Material
- MI_ Material Instance
- T_ Texture
- A_ Animation
- AM_ Animation Montage
- ABP_ Animation Blueprint
- CR_ Control Rig
- IK_ IK Rig
- RTG_ IK Retargeter
- PS_ Pose Search
- CH_ Chooser
- DA_ Data Asset
- WBP_ UI Widget
- NS_ Niagara System
- MS_ MetaSound
- LS_ Level Sequence
- BP_ Blueprint

Examples:
SK_Hussam_Body
M_Hussam_Skin
MI_Hussam_Skin_Combat
ABP_Hussam_Master
PS_Hussam_Locomotion
NS_Rifle_Muzzle
WBP_HUD_Infantry
LS_M01_Intro

## Recommended content tree
```
Content/
  Characters/
    Hero/
    Squad/
    Enemy/
    Civilians/
  Weapons/
    Rifles/
    SMG/
    Shotguns/
    LMG/
    Snipers/
    Pistols/
    Launchers/
    Melee/
    Attachments/
  Vehicles/
    Civilian/
    Military/
    Air/
    Sea/
  World/
    Jeddah/
      Corniche/
      AlBalad/
      Downtown/
      Highway/
      Port/
      Industrial/
      Interiors/
      Rooftops/
      Props/
  FX/
  UI/
  Audio/
  Cinematics/
  Missions/
  Data/
```

## Vertical-slice art target
Approximate planning target, not final budget:
- 1 hero
- 4–6 named squad characters
- 5–6 enemy archetypes
- 20–30 civilian visual variants
- 5 primary weapons
- 2 pistols
- 1 heavy weapon
- 2 melee items
- ~6 equipment devices
- 3 military vehicles
- ~8 civilian vehicles
- 2 helicopters
- 80–120 modular building/environment pieces
- 150–250 props
- 50–80 VFX systems
- 250–400 hero animation clips/poses plus procedural layers
- 20–30 UI widget families

## Full-game direction
Planning envelope:
- 5–7 named squad members
- 15–20 enemy archetypes
- 100+ civilian base variations
- 25–35 firearms
- 8–12 melee options
- 15+ devices
- 30–50 vehicles
- 4–6 helicopters/drones
- 4–8 boats
- 600–1000 environment modules
- 1000+ props
- 150–250 Niagara systems
- 800–1500 animation clips/poses across databases

These are scope-planning figures and must be validated against schedule, team and performance.

## LOD/scalability
Every asset family needs explicit:
LOD policy, texture budget, material complexity budget, collision strategy, streaming policy, platform scalability and performance test.
