---
phase: 21-impermanence-ephemeral-root
plan: 01
subsystem: infra
tags: [btrfs, impermanence, disko, initrd, restic, backup, ephemeral-root]

# Dependency graph
requires:
  - phase: 16-disaster-recovery
    provides: restic backup config and recovery runbook
  - phase: 25-deploy-safety
    provides: deploy-rs integration and rollback runbook appendix
provides:
  - BTRFS 5-subvolume disko layout replacing ext4
  - Impermanence module with 17 directories + 2 files persisted under /persist
  - Initrd rollback script wiping root subvolume on every boot
  - Restic backup targeting /persist instead of /
  - Recovery runbook with impermanence architecture appendix
affects: [21-02-deploy, restic, recovery, disko, boot]

# Tech tracking
tech-stack:
  added: [nix-community/impermanence, btrfs]
  patterns: [ephemeral-root-with-persist-subvolume, initrd-btrfs-rollback, impermanence-bind-mounts]

key-files:
  created:
    - modules/impermanence.nix
  modified:
    - hosts/neurosys/disko-config.nix
    - hosts/neurosys/hardware.nix
    - flake.nix
    - flake.lock
    - modules/boot.nix
    - modules/default.nix
    - modules/restic.nix
    - docs/recovery-runbook.md

key-decisions:
  - "IMP-01: BTRFS subvolume rollback (not tmpfs) -- server workloads need disk-backed root"
  - "IMP-02: Docker on own @docker subvolume (not impermanence bind-mount) -- avoids overlay2 nested mount conflicts"
  - "IMP-03: Persist whole /home/dangirsh (not per-file) -- simpler for server, covers Syncthing data + config"
  - "IMP-04: /var/lib/private covers DynamicUser services (ESPHome, future services)"
  - "RESTIC-05: Back up /persist subvolume (all stateful data). Ephemeral root, /nix, Docker subvolume excluded by design."

patterns-established:
  - "Ephemeral root: all state under /persist, root wiped on boot via initrd BTRFS rollback"
  - "New stateful paths: add to modules/impermanence.nix directories list, deploy"
  - "Backup targets /persist: simplified excludes, no --one-file-system needed"

# Metrics
duration: 10min
completed: 2026-02-22
---

# Phase 21 Plan 01: Impermanence Configuration Summary

**BTRFS 5-subvolume disko layout with nix-community/impermanence bind-mounts, initrd root rollback, and /persist-targeted restic backups**

## Performance

- **Duration:** 10 min
- **Started:** 2026-02-22T12:54:51Z
- **Completed:** 2026-02-22T13:04:24Z
- **Tasks:** 2
- **Files modified:** 9 (1 created, 8 modified)

## Accomplishments
- Replaced ext4 single-partition disko config with BTRFS 5-subvolume layout (@root, @nix, @persist, @log, @docker)
- Created impermanence module declaring 17 persistent directories and 2 persistent files covering all stateful paths from research audit
- Added initrd rollback script that wipes and recreates root subvolume on every boot (30-day old_roots retention)
- Migrated restic backup from blanket `/` with `--one-file-system` to targeted `/persist` with simplified excludes
- Updated recovery runbook with impermanence-aware restore procedures and new Appendix 12 (architecture, debugging, adding paths)

## Task Commits

Each task was committed atomically:

1. **Task 1: BTRFS disko config + impermanence flake input + initrd rollback + boot BTRFS support** - `779d432` (feat)
2. **Task 2: Impermanence persistence module + restic backup path migration + recovery runbook update** - `a03d7b7` (feat)

## Files Created/Modified
- `hosts/neurosys/disko-config.nix` - BTRFS 5-subvolume layout replacing ext4
- `hosts/neurosys/hardware.nix` - Added btrfs to boot.initrd.supportedFilesystems
- `flake.nix` - Added impermanence input, wired nixosModule into outputs
- `flake.lock` - Locked impermanence at 7b1d382
- `modules/boot.nix` - Initrd postResumeCommands with BTRFS rollback script
- `modules/impermanence.nix` - 17 directories + 2 files under environment.persistence."/persist"
- `modules/default.nix` - Added impermanence.nix to imports
- `modules/restic.nix` - paths=["/persist"], removed --one-file-system and stale excludes
- `docs/recovery-runbook.md` - Updated Sections 3/5/Appendix 9, added Appendix 12

## Decisions Made
- IMP-01: BTRFS subvolume rollback over tmpfs -- server with Docker builds and Nix builds could exhaust tmpfs
- IMP-02: Docker on own @docker subvolume -- overlay2 nested mount conflicts with impermanence bind-mounts
- IMP-03: Whole /home/dangirsh persisted -- simpler for server use case, covers Syncthing 7GB data + config
- IMP-04: /var/lib/private covers ESPHome and future DynamicUser services
- RESTIC-05 updated: /persist backup replaces blanket / with --one-file-system

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. The configuration is ready for the human operator to execute nixos-anywhere redeploy in Plan 02.

## Next Phase Readiness
- All NixOS config changes validated with `nix flake check` (41 checks passed)
- Recovery runbook updated with impermanence-aware procedures
- Ready for Plan 21-02: nixos-anywhere redeploy with BTRFS + impermanence

## Self-Check: PASSED

- All 9 files verified present on disk
- Commit 779d432 (Task 1) verified in git log
- Commit a03d7b7 (Task 2) verified in git log
- `nix flake check` passed (41 checks)

---
*Phase: 21-impermanence-ephemeral-root*
*Completed: 2026-02-22*
