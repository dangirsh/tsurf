---
phase: 16-disaster-recovery-backup-completeness
plan: 01
subsystem: infra
tags: [restic, backup, b2, postgresql, docker, ssh, disaster-recovery]

# Dependency graph
requires:
  - phase: 03-networking-secrets-docker
    provides: "sops-nix secrets, restic base configuration, Docker foundation"
provides:
  - "Complete backup coverage: SSH host keys, Docker bind mounts, Tailscale state"
  - "PostgreSQL consistency via pg_dumpall pre-backup hook"
  - "Backup cleanup post-hook removing temporary dump files"
affects: [16-02-recovery-runbook, disaster-recovery]

# Tech tracking
tech-stack:
  added: []
  patterns: ["restic backupPrepareCommand/backupCleanupCommand for database consistency hooks"]

key-files:
  created: []
  modified: ["modules/restic.nix"]

key-decisions:
  - "RESTIC-04: Back up SSH host key (sops-nix age derivation chain), Docker bind mounts, Tailscale state; pg_dumpall pre-hook for PostgreSQL consistency"
  - "Explicit SSH key file paths (not globs) -- only ed25519 pair needed for sops-nix age chain"
  - "pg_dumpall with || true so backup proceeds even if DB container is stopped"

patterns-established:
  - "Belt-and-suspenders DB backup: raw pgdata directory + logical SQL dump via pre-hook"
  - "Resilient pre-hooks: || true ensures backup never fails due to optional services being down"

# Metrics
duration: 1min
completed: 2026-02-19
---

# Phase 16 Plan 01: Backup Gap Closure Summary

**Restic backup expanded from 3 to 8 paths covering SSH host keys, Docker bind mounts (claw-swap, parts), and Tailscale state, plus pg_dumpall pre-hook for PostgreSQL consistency**

## Performance

- **Duration:** 1 min
- **Started:** 2026-02-19T11:15:13Z
- **Completed:** 2026-02-19T11:16:25Z
- **Tasks:** 1 (of 2 in plan; Task 2 deploy/verify handled by orchestrator)
- **Files modified:** 1

## Accomplishments
- Added 5 new backup paths to restic.nix: SSH host ed25519 key pair, /var/lib/claw-swap/, /var/lib/parts/, /var/lib/tailscale/
- Added backupPrepareCommand with pg_dumpall via docker exec for PostgreSQL consistency
- Added backupCleanupCommand to remove temporary dump file after backup
- Module signature updated to include pkgs for docker binary path reference
- nix flake check passes cleanly

## Task Commits

Each task was committed atomically:

1. **Task 1: Add missing backup paths and pg_dump hook to restic.nix** - `952aea2` (feat)

_Note: Task 2 (deploy, trigger backup, dry-run restore) is handled by the orchestrator separately._

## Files Created/Modified
- `modules/restic.nix` - Added 5 backup paths (SSH host keys, Docker bind mounts, Tailscale state), pg_dumpall pre-hook, cleanup post-hook, @decision RESTIC-04 annotation

## Decisions Made
- **RESTIC-04:** Back up SSH host key (critical for sops-nix age derivation -- without it, catastrophic VPS loss means multi-hour key rotation instead of simple restore), Docker bind mounts (claw-swap PostgreSQL data, parts data), and Tailscale state
- **Explicit file paths for SSH keys:** Only `/etc/ssh/ssh_host_ed25519_key` and `.pub` -- not glob patterns. Only the ed25519 key pair is needed for the sops-nix age derivation chain
- **Resilient pg_dumpall hook:** Uses `|| true` so backup proceeds even when the claw-swap-db container is stopped. Raw pgdata directory is still backed up as a fallback
- **Belt-and-suspenders DB backup:** Both raw pgdata and logical SQL dump are captured, providing two independent recovery paths

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. Task 2 (deploy and verify) will be handled by the orchestrator.

## Next Phase Readiness
- restic.nix is ready for deployment to VPS (Task 2 scope)
- After deployment, a manual backup trigger + dry-run restore will validate the new paths
- Plan 16-02 (recovery runbook) can proceed once backup verification is confirmed

## Self-Check: PASSED

- [x] `modules/restic.nix` exists with all 5 new paths, pre-hook, cleanup-hook, RESTIC-04 annotation
- [x] Commit `952aea2` exists in git history
- [x] `16-01-SUMMARY.md` exists at phase directory

---
*Phase: 16-disaster-recovery-backup-completeness*
*Completed: 2026-02-19*
