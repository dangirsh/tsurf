---
phase: 65-open-source-cleanup-v2-minimal-forkable-skeleton
plan: "02"
subsystem: infra
tags: [nix, secrets, networking, impermanence, eval-checks]

requires:
  - phase: "65-01"
    provides: personal modules removed from public repo
provides:
  - Core modules contain no personal service references
  - Private overlay has impermanence-private.nix for moved persist paths
  - Private overlay secrets-contabo.nix has all moved secret declarations
  - nix flake check passes (19 checks)
affects: [65-03, deploy, private-overlay]

key-files:
  created:
    - /data/projects/private-neurosys/modules/impermanence-private.nix
  modified:
    - hosts/services/default.nix
    - hosts/dev/default.nix
    - modules/impermanence.nix
    - modules/networking.nix
    - modules/secrets.nix
    - flake.nix
    - tests/eval/config-checks.nix
    - /data/projects/private-neurosys/modules/secrets-contabo.nix
    - /data/projects/private-neurosys/modules/secrets-ovh-overrides.nix

key-decisions:
  - "65-02-A: Host imports trimmed to core modules only"
  - "65-02-B: Impermanence personal paths moved to private overlay impermanence-private.nix"
  - "65-02-C: internalOnlyPorts reduced to 4 core entries (from 16)"
  - "65-02-D: 10 personal secrets removed from public secrets.nix; full declarations added to private secrets-contabo.nix"
  - "65-02-E: openclaw and neurosys-mcp package exports removed from flake.nix"
  - "65-02-F: openclaw eval check removed; dashboard threshold lowered to >= 5"

duration: ~15min
completed: 2026-03-04
---

# Phase 65 Plan 02: Clean Core Modules — Remove Personal Service References Summary

**Stripped 13 personal service ports, 10 secrets, 13 impermanence paths, and 2 package exports from public repo**

## Performance

- **Duration:** ~15 min
- **Tasks:** 9
- **Files modified:** 14

## Accomplishments
- Host import lists contain only core modules (no personal services)
- internalOnlyPorts has 4 entries (from 16) — core services only
- secrets.nix has only infrastructure secrets (tailscale, restic, API keys, github-pat)
- Impermanence paths contain only OS/infrastructure state
- Flake packages export only deploy-rs and test-live
- Eval checks pass without openclaw service check
- Private overlay has complete secret declarations and impermanence paths

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] dashboard.nix comment referenced dm-guide.nix**
- **Found during:** Grep verification
- **Issue:** @rationale comment mentioned dm-guide.nix pattern
- **Fix:** Updated to reference only restic-status-server
- **Files modified:** modules/dashboard.nix

---

**Total deviations:** 1 auto-fixed
**Impact on plan:** Trivial comment fix.

## Issues Encountered
None

## Next Phase Readiness
Ready for Plan 65-03 (README update)

---
*Phase: 65-open-source-cleanup-v2-minimal-forkable-skeleton*
*Completed: 2026-03-04*
