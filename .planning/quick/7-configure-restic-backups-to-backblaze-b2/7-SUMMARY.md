---
phase: quick-7
plan: 01
subsystem: infra
tags: [restic, backups, b2, sops]

# Dependency graph
requires:
  - phase: 3-networking-secrets-docker
    provides: sops-nix secrets infrastructure
provides:
  - Automated daily encrypted backups to Backblaze B2
  - Retention policy: 7 daily, 5 weekly, 12 monthly
affects: [deploy, secrets]

# Tech tracking
tech-stack:
  added: [restic, backblaze-b2]
  patterns:
    - "sops.templates for multi-secret env file rendering (AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY)"
    - "services.restic.backups with S3-compatible B2 backend"

key-files:
  created:
    - modules/restic.nix
  modified:
    - modules/secrets.nix
    - modules/default.nix
    - secrets/acfs.yaml

key-decisions:
  - "RESTIC-01: S3-compatible B2 backend (not native B2 connector)"
  - "RESTIC-02: Retention policy 7 daily, 5 weekly, 12 monthly"
  - "RESTIC-03: sops.templates renders B2 creds into env file; passwordFile for encryption key"
  - "B2 app key scoped to SyncBkp bucket (not master key)"

patterns-established:
  - "sops.templates for rendering multi-secret environment files"

# Metrics
duration: ~30min (including credential debugging)
completed: 2026-02-19
---

# Quick Task 7: Configure Restic Backups to B2 Summary

**Automated encrypted backups to Backblaze B2 with daily timer and retention policy**

## Performance

- **Duration:** ~30 min (credential debugging took most time)
- **Tasks:** 2 (module creation + deploy/test)
- **Files:** 4 modified, 1 created

## Accomplishments

- `modules/restic.nix` created with `services.restic.backups.b2` configuration
- B2 S3-compatible backend at `s3:s3.eu-central-003.backblazeb2.com/SyncBkp`
- Scoped B2 application key (keyName: `neurosys`) encrypted in sops secrets
- `sops.templates."restic-b2-env"` renders AWS credentials from individual secrets
- Daily timer with `Persistent = true` and 1h randomized delay
- Retention: 7 daily, 5 weekly, 12 monthly snapshots
- First snapshot verified: `2992b35c` (407 files, 16.9 MiB, 5.1 MiB stored)
- Timer active, next run scheduled

## Backup Paths

- `/data/projects/` — code repos and project data
- `/home/dangirsh/` — user home directory
- `/var/lib/hass/` — Home Assistant state

## Exclusions

- `.git/objects`, `node_modules`, `__pycache__`, `.direnv`, `result`

## Issues Encountered

- B2 credentials required multiple iterations:
  - Initial values were account ID (not app key ID) and mismatched secret
  - Previous app keys were invalid/expired
  - Resolved by generating fresh scoped app key from B2 dashboard
- B2 S3 API requires application key ID (not account ID) as AWS_ACCESS_KEY_ID

## Commits

1. `8723f41` — feat(quick-7): add restic backup module with B2 S3 backend and sops integration
2. `98ab86c` — chore(quick-7): update sops secrets with real B2 credentials
3. `01de260` — fix(quick-7): correct B2 application key ID in sops secrets
4. `1536d80` — fix(quick-7): correct B2 application key credentials

---
*Quick Task: 7-configure-restic-backups-to-backblaze-b2*
*Completed: 2026-02-19*
