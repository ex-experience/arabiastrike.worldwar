# CODEX HANDOFF — ARABIA STRIKE WORLD WAR

Use this instruction in Codex Desktop on the local clone of:

`ex-experience/arabiastrike.worldwar`

## Strict task

1. Verify repository:
   - `git remote -v`
   - `git branch --show-current`
   - `git status --short`

2. Require baseline branch:
   - `codex/asww-development`
   - DO NOT TOUCH `main`.

3. Create:
   - `codex/asww-master-production-system`

4. Import the contents of the folder:
   - `ASWW_MASTER_PRODUCTION_SYSTEM_2026/`
   into the repository root, preserving paths.

5. Required paths after import:
   - `AGENTS.md`
   - `README_MASTER_PRODUCTION_SYSTEM.md`
   - `docs/MASTER_PRODUCTION_SYSTEM/**`
   - `Config/Design/**`
   - `Reference/Visuals/**`
   - `Reference/ContactSheets/**`

6. Verify all 40 visual references exist and compare against:
   - `Reference/Visuals/visual_manifest.csv`
   - `Reference/Visuals/visual_manifest.json`

7. Do not fabricate `.uasset` or `.umap` files.
   Do not delete current code.
   Do not overwrite current project content unless a path intentionally conflicts and the new master directive explicitly requires it.

8. Validate:
   - `git diff --check`
   - `git status --short`
   - inspect all staged files
   - ensure `main` is unchanged

9. Commit:
   `docs: lock ASWW master production system and visual references`

10. Push:
   `git push -u origin codex/asww-master-production-system`

11. Report:
   - branch
   - commit SHA
   - total files added
   - visual files count
   - any conflicts/errors
   - exact GitHub branch URL

## Production rule after import

Read and obey:
`docs/MASTER_PRODUCTION_SYSTEM/00_MASTER_DIRECTIVE.md`
and root `AGENTS.md`.

Do not begin feature implementation until the import commit is safely pushed.
