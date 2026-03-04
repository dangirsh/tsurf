---
phase: 65-open-source-cleanup-v2-minimal-forkable-skeleton
plan: "01"
subsystem: infra
tags: [nix, modules, private-overlay, open-source]

requires:
  - phase: "64"
    provides: repo layout simplification
provides:
  - Personal modules and packages moved to private overlay
  - Public repo contains no personal service code
affects: [65-02, 65-03, private-overlay]

key-files:
  created:
    - /data/projects/private-neurosys/modules/automaton.nix
    - /data/projects/private-neurosys/modules/matrix.nix
    - /data/projects/private-neurosys/modules/openclaw.nix
    - /data/projects/private-neurosys/modules/dm-guide.nix
    - /data/projects/private-neurosys/packages/automaton.nix
    - /data/projects/private-neurosys/packages/openclaw.nix
  modified:
    - /data/projects/private-neurosys/flake.nix
    - home/default.nix

key-decisions:
  - "65-01-A: Copy 4 modules (automaton, matrix, openclaw, dm-guide) to private overlay"
  - "65-01-B: Copy 4 package files (automaton, openclaw + lockfiles) to private overlay"
  - "65-01-C: Update private overlay flake.nix to use local ./modules/ paths instead of ${inputs.neurosys}/modules/"
  - "65-01-E: Remove agentic-dev-base.nix import from public home/default.nix"

duration: ~12min
completed: 2026-03-04
---

# Phase 65 Plan 01: Move Personal Modules and Packages to Private Overlay Summary

**Moved 4 personal modules and 4 package files from public to private overlay with path rewriting**

## Performance

- **Duration:** ~12 min
- **Tasks:** 6
- **Files modified:** 16

## Accomplishments
- All personal service modules (automaton, matrix, openclaw, dm-guide, home-assistant) removed from public repo
- All personal packages (automaton, openclaw + lockfiles, neurosys-mcp) removed from public repo
- Private overlay imports rewritten from `${inputs.neurosys}/modules/...` to local `./modules/...`
- Private overlay committed with all moved files

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] openclaw-auto-approve.nix does not exist**
- **Found during:** Task 65-01-C
- **Issue:** Plan referenced `./modules/openclaw-auto-approve.nix` which doesn't exist in the private overlay
- **Fix:** Skipped this sub-task — no file to update
- **Verification:** No references to `inputs.neurosys` remain for automaton/matrix/dm-guide/openclaw in private overlay

**2. [Rule 2 - Missing Critical] Stale comment in matrix-overrides.nix**
- **Found during:** Grep verification
- **Issue:** Comment referenced old import path `"${inputs.neurosys}/modules/matrix.nix"`
- **Fix:** Updated comment to reflect new local path
- **Verification:** grep clean

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 missing critical)
**Impact on plan:** Minimal. openclaw-auto-approve.nix skip was harmless.

## Issues Encountered
None

## Next Phase Readiness
Ready for Plan 65-02 (clean core module references)

---
*Phase: 65-open-source-cleanup-v2-minimal-forkable-skeleton*
*Completed: 2026-03-04*
