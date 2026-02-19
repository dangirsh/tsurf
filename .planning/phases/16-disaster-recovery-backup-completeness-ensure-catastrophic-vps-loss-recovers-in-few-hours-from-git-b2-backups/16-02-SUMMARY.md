---
phase: 16-disaster-recovery-backup-completeness
plan: 02
subsystem: infra
tags: [restic, disaster-recovery, runbook, nixos-anywhere, sops-nix, backblaze-b2]

# Dependency graph
requires:
  - phase: 16-disaster-recovery-backup-completeness-01
    provides: "Complete backup paths in modules/restic.nix (SSH host key, Docker bind mounts, Tailscale state, pg_dump hook)"
provides:
  - "docs/recovery-runbook.md — complete disaster recovery procedure with exact commands"
  - "Documented RTO < 2 hours, RPO 24 hours"
  - "4-phase recovery flow: deploy, restore, re-auth, verify"
  - "Credential extraction procedure for bootstrap (before sops-nix works)"
affects: [deployment, backup, secrets-management]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Recovery runbook versioned alongside NixOS config in docs/"
    - "Pre-sops credential extraction via admin age key for disaster bootstrap"

key-files:
  created:
    - docs/recovery-runbook.md
  modified: []

key-decisions:
  - "Runbook organized as 4-phase recovery with time estimates per phase"
  - "Credential bootstrap documented: admin age key decrypts secrets/acfs.yaml locally before sops-nix works on server"
  - "SSH host key identified as single most critical file — root of sops-nix trust chain"
  - "Manual re-auth list kept minimal: Tailscale (always if stale), Home Assistant (only if restore fails)"

patterns-established:
  - "Disaster recovery runbook lives in docs/ and is versioned with git"
  - "Every recovery step has a verification command"
  - "Accepted losses are explicitly documented with rationale"

# Metrics
duration: 3min
completed: 2026-02-19
---

# Phase 16 Plan 02: Recovery Runbook Summary

**Complete disaster recovery runbook with 4-phase procedure, 10-point verification checklist, and credential bootstrap for VPS rebuild from git + B2 in < 2 hours**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-19T11:16:43Z
- **Completed:** 2026-02-19T11:19:44Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Complete 506-line runbook covering full VPS recovery from catastrophic loss
- 4-phase recovery flow: deploy NixOS (nixos-anywhere), restore stateful data (restic), manual re-auth, verification
- Pre-sops credential extraction procedure using admin age key (critical bootstrap step)
- 10-point verification checklist with exact commands and expected outputs
- Three appendices: credential locations, accepted losses, testing notes

## Task Commits

Each task was committed atomically:

1. **Task 1+2: Write disaster recovery runbook and commit** - `1597396` (docs)

## Files Created/Modified

- `docs/recovery-runbook.md` — Complete disaster recovery procedure: prerequisites, 4-phase recovery, credential appendix, accepted losses, testing notes

## Decisions Made

- **Runbook structure:** 10 sections covering overview, prerequisites, data location table, 4 recovery phases, and 3 appendices
- **Credential bootstrap:** Documented that admin age key decrypts secrets/acfs.yaml locally, providing restic credentials before sops-nix works on the new server
- **SSH host key as critical path:** Identified and documented as the single most critical file — without it, the entire sops-nix trust chain breaks
- **Manual re-auth scope:** Exactly 2 items: Tailscale (if backup stale) and Home Assistant (only if restore fails completely)
- **Accepted losses documented:** Prometheus metrics, fail2ban history, ESPHome configs, Nix store — all reconstructible or low value

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Recovery runbook is complete and versioned in git
- Runbook references the final backup paths from 16-01 (SSH host key, Docker bind mounts, Tailscale state)
- Dry-run restore testing can be performed on the live VPS using the commands in Section 10

## Self-Check: PASSED

- [x] `docs/recovery-runbook.md` exists (FOUND)
- [x] Commit `1597396` exists (FOUND)
- [x] `16-02-SUMMARY.md` exists (FOUND)

---
*Phase: 16-disaster-recovery-backup-completeness*
*Completed: 2026-02-19*
