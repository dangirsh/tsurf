---
phase: 06-user-services-agent-tooling
plan: 02
subsystem: infra
tags: [cass, systemd-timer, activation-scripts, symlinks, home-manager]

requires:
  - phase: 05-user-environment-dev-tools
    provides: home-manager integration, sops secrets (github-pat)
provides:
  - CASS binary on PATH with 30-minute indexing timer
  - Idempotent repo cloning for parts, claw-swap, global-agent-conf
  - ~/.claude and ~/.codex symlinked to global-agent-conf
affects: [deployment]

tech-stack:
  added: [autoPatchelfHook, systemd.user.timers, system.activationScripts, mkOutOfStoreSymlink]
  patterns: [pre-built binary packaging via fetchurl+autoPatchelfHook, clone-only idempotent repos]

key-files:
  created: [packages/cass.nix, home/cass.nix, home/agent-config.nix, modules/repos.nix]
  modified: [home/default.nix, modules/default.nix]

key-decisions:
  - "CASS binary v0.1.64 fetched from GitHub release, patched with autoPatchelfHook"
  - "Repo cloning is clone-only (never pull/update) to protect dirty working trees"
  - "mkOutOfStoreSymlink for whole-directory symlinks (not recursive home.file)"

duration: 15min
completed: 2026-02-16
---

# Phase 6 Plan 02: CASS + Repos + Agent Config Summary

**CASS binary derivation with 30-min indexer timer, idempotent repo cloning, and ~/.claude + ~/.codex symlinks to global-agent-conf**

## Performance

- **Duration:** 15 min
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments
- CASS v0.1.64 binary packaged via fetchurl + autoPatchelfHook with correct hash
- Systemd user timer fires every 30 minutes (oneshot + Persistent for catchup)
- 3 repos (parts, claw-swap, global-agent-conf) clone idempotently on NixOS activation
- ~/.claude and ~/.codex are whole-directory symlinks to /data/projects/global-agent-conf

## Task Commits

1. **Task 1: CASS binary + timer** - `7242bf8` (feat)
2. **Task 2: Repo cloning + agent config** - `678bc6b` (feat)
3. **Task 3: Wire modules into indexes** - `7e7a2a5` (feat)

## Files Created/Modified
- `packages/cass.nix` - CASS binary Nix derivation (fetchurl + autoPatchelfHook)
- `home/cass.nix` - CASS on PATH + systemd user timer (30-min indexing)
- `home/agent-config.nix` - ~/.claude and ~/.codex symlinks via mkOutOfStoreSymlink
- `modules/repos.nix` - Activation script cloning 3 repos with GH_TOKEN auth
- `home/default.nix` - Now imports cass.nix and agent-config.nix
- `modules/default.nix` - Now imports repos.nix

## Decisions Made
- Used `autoPatchelfHook` + openssl + zlib for CASS binary patching (standard pattern for pre-built binaries)
- Clone-only repos: never pull/update existing repos to protect dirty working trees
- `mkOutOfStoreSymlink` creates whole-directory symlinks (not per-file via lndir)
- Activation script `deps = [ "users" ]` ensures dangirsh exists; `chown` fixes root ownership

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## Next Phase Readiness
- Phase 6 complete — all user services and agent tooling declared
- Ready for Phase 7 (Backups) or deployment verification

---
*Phase: 06-user-services-agent-tooling*
*Completed: 2026-02-16*
