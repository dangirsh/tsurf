---
phase: 57-ovh-neurosys-dev-bootstrap
plan: 01
subsystem: infra
tags: [nixos, hostname, ovh, deploy, tailscale]

requires:
  - phase: 50
    provides: coherent public repo config
provides:
  - Public repo hostname migration from neurosys-prod to neurosys-dev
  - Updated deploy target, bootstrap script, test helpers, and docs
affects: [57-02, private-neurosys]

tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - hosts/ovh/default.nix
    - flake.nix
    - scripts/bootstrap-ovh.sh
    - scripts/deploy.sh
    - tests/lib/common.bash
    - tests/live/service-health.bats
    - CLAUDE.md

key-decisions:
  - "[57-01]: OVH hostname standardized from neurosys-prod to neurosys-dev across public repo"
  - "[57-01]: test-live CLI selector and is_ovh() predicate updated to match new hostname"

duration: 8min
completed: 2026-03-02
---

# Phase 57 Plan 01: Rename OVH Hostname Summary

**Renamed all `neurosys-prod` references to `neurosys-dev` across 7 public repo files; `nix flake check` passes for both configurations**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-02T10:14:00Z
- **Completed:** 2026-03-02T10:22:00Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- All `neurosys-prod` references replaced with `neurosys-dev` in host config, flake deploy node, bootstrap script, deploy script, test helpers, and documentation
- `nix flake check` passes for both `neurosys` and `ovh` NixOS configurations
- Test infrastructure (`is_ovh()`, service-health assertions, test-live CLI selector) aligned with new hostname

## Task Commits

1. **Task 1: Rename neurosys-prod to neurosys-dev** - `58b6c83` (feat)
2. **Task 2: Validate nix flake check** - `cea2b05` (chore)

## Files Created/Modified
- `hosts/ovh/default.nix` - Updated `networking.hostName` to `neurosys-dev`
- `flake.nix` - Updated `deploy.nodes.ovh.hostname` and `test-live` CLI case match
- `scripts/bootstrap-ovh.sh` - Updated `TAILSCALE_HOSTNAME` variable
- `scripts/deploy.sh` - Updated default OVH SSH target
- `tests/lib/common.bash` - Updated `is_ovh()` predicate
- `tests/live/service-health.bats` - Updated tailscale hostname assertion
- `CLAUDE.md` - Updated test-live documentation example

## Decisions Made
- Pure string replacement only — no logic, structure, or formatting changes beyond hostname

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Concurrent sessions modifying main required fresh worktree creation and rebase; resolved cleanly

## Next Phase Readiness
- Public repo ready for OVH re-bootstrap with `neurosys-dev` hostname
- Plan 57-02 (live bootstrap + deploy) is next — requires human-action checkpoints for Tailscale admin, OVH reinstall, and private overlay updates

---
*Phase: 57-ovh-neurosys-dev-bootstrap*
*Completed: 2026-03-02*
