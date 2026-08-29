# Epic Template Distribution Review

Reviewed: 2026-08-29 (Asia/Riyadh)

Remote: `https://github.com/ex-experience/arabiastrike.worldwar`

GitHub visibility: **public** (verified with the official GitHub REST API).

## Provenance result

`PRE_VERTICAL_TEMPLATE_PROVENANCE.txt` compares the preserved binary packages with the locally installed Unreal Engine 5.8 template resources. It records exact SHA-256 matches for the copied Mannequins, Variant Shooter, First Person, Level Prototyping, XR Framework, Input, and Weapons packages, with the few project-modified or locally original exceptions called out in that manifest.

The source locations used by the local import scripts are under Unreal Engine 5.8 `Templates/TemplateResources` and `FeaturePacks`; they are not Fab/Marketplace downloads or third-party commercial-game content.

## Official Epic terms consulted

Current Unreal Engine EULA: <https://www.unrealengine.com/eula/unreal>

- Section 1 defines **Examples** as code, artwork, or other content supplied in the `Samples` and `Templates` folders of the Unreal Engine installation.
- Section 5(b) states that Examples, including modified Examples, may be distributed in source or object code to any third party.
- Section 7 keeps ownership of Licensed Technology with Epic and requires retention of Epic proprietary notices and disclaimers.
- Section 6(c) prohibits combining Licensed Technology with a license that would force different terms onto it.

## Gate decision

The identified UE 5.8 template/feature-pack packages qualify as Epic **Examples** based on their verified source paths, so the EULA expressly permits their public distribution. A full backup-branch push is therefore allowed for this identified set, subject to the repository owner having accepted and remaining compliant with the applicable Epic agreement.

This repository has no root `LICENSE` file. Nothing in this preservation commit attempts to relicense, sublicense, or claim ownership of Epic content. Epic-owned Example assets remain governed by the Unreal Engine EULA. No Engine Code or Engine Tools are included by this snapshot.

This is a repository distribution-gate record, not legal advice. Any later Fab/Marketplace or separately licensed asset must receive its own provenance and redistribution review before a public push.
