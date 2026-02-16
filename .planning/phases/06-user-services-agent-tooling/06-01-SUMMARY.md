---
phase: 06-user-services-agent-tooling
plan: 01
subsystem: infra
tags: [syncthing, nixos, file-sync, tailscale]

requires:
  - phase: 03-networking-secrets-docker
    provides: Tailscale VPN + trustedInterfaces firewall
provides:
  - Declarative Syncthing service with 4 devices and 1 bidirectional folder
affects: [deployment]

tech-stack:
  added: [services.syncthing]
  patterns: [Tailscale-only GUI via firewall trust, staggered versioning]

key-files:
  created: [modules/syncthing.nix]
  modified: [modules/default.nix, modules/base.nix]

key-decisions:
  - "GUI binds 0.0.0.0:8384, restricted to Tailscale via trustedInterfaces (not IP binding)"
  - "allowUnfreePredicate added for claude-code (pre-existing issue from Phase 5)"

duration: 25min
completed: 2026-02-16
---

# Phase 6 Plan 01: Syncthing Declarative Module Summary

**Declarative Syncthing NixOS module with 4 devices, staggered versioning, and Tailscale-only GUI access**

## Performance

- **Duration:** 25 min
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Syncthing service declared with 4 devices (placeholder IDs) and single "Sync" folder
- Staggered versioning with 90-day retention and hourly cleanup
- GUI restricted to Tailscale-only via existing firewall trustedInterfaces
- STNODEFAULTFOLDER suppresses unwanted default folder creation

## Task Commits

1. **Task 1: Create Syncthing NixOS module** - `ec7f412` (feat, by Codex)
2. **Task 2: Wire module + fix unfree** - `34728bf` (fix), `7e7a2a5` (feat, partial — default.nix wiring combined with 06-02)

## Files Created/Modified
- `modules/syncthing.nix` - Declarative Syncthing service config (4 devices, 1 folder, staggered versioning)
- `modules/default.nix` - Module index now imports syncthing.nix
- `modules/base.nix` - Added allowUnfreePredicate for claude-code

## Decisions Made
- GUI binds to 0.0.0.0:8384 (not Tailscale IP) to avoid startup ordering issues — port 8384 is not in public firewall, only accessible via tailscale0 trusted interface
- Added `allowUnfreePredicate` for `claude-code` package — pre-existing issue from Phase 5 that surfaced when `nix flake check` fully evaluated

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] allowUnfree needed for claude-code**
- **Found during:** Task 2 (nix flake check validation)
- **Issue:** `claude-code` from llm-agents overlay has unfree license, causing flake check to fail
- **Fix:** Added `nixpkgs.config.allowUnfreePredicate` in `modules/base.nix`
- **Files modified:** modules/base.nix
- **Verification:** nix flake check passes
- **Committed in:** 34728bf

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Essential fix for flake evaluation. Pre-existing issue from Phase 5, not scope creep.

## Issues Encountered
- `nix flake check` takes 10+ minutes on this flake due to heavy dependency tree (llm-agents, parts, claw-swap inputs)
- Codex timed out waiting for flake check; orchestrator took over for commits

## Next Phase Readiness
- Syncthing module complete; device IDs are placeholders (user must replace before deploy)
- Ready for Plan 06-02 (CASS + repos + agent config)

---
*Phase: 06-user-services-agent-tooling*
*Completed: 2026-02-16*
