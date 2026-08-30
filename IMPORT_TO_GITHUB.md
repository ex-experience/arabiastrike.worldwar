# IMPORT TO GITHUB

Target repository:
`ex-experience/arabiastrike.worldwar`

Preferred target branch:
`codex/asww-master-production-system` based on `codex/asww-development`.

If branch creation is unavailable, import only into `codex/asww-development`; never `main`.

## Current automated-write status
During package creation, the connected GitHub integration returned:
`403 Resource not accessible by integration`
for both branch creation and file creation.

Therefore this package is prepared locally and is not represented as already committed.

## Manual import
Copy the package contents into the repository root, preserving paths, then:

```bash
git switch codex/asww-development
git pull
git switch -c codex/asww-master-production-system
git add AGENTS.md README_MASTER_PRODUCTION_SYSTEM.md docs/MASTER_PRODUCTION_SYSTEM Config/Design Reference
git commit -m "docs: lock ASWW master production system and visual references"
git push -u origin codex/asww-master-production-system
```

Do not merge to `main` until implementation acceptance.
