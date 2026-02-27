---
phase: 38-dual-host-role-separation-contabo-as-services-host-ovh-as-dev-agent-host
plan: 01
subsystem: infra
tags: [nixos, modules, deploy]

requires:
  - phase: prior phases
    provides: existing module structure
provides:
  - Dual-host module allocation (shared 11 modules + per-host extras)
  - Node-conditional deploy.sh health checks
affects: [phase-38-02, deploy, all-future-phases]

tech-stack:
  added: []
  patterns: [per-host module imports, node-conditional health checks]

key-files:
  created: []
  modified: [modules/default.nix, hosts/neurosys/default.nix, hosts/ovh/default.nix, scripts/deploy.sh, modules/secrets.nix, .planning/STATE.md]

key-decisions:
  - "Keep flake public API unchanged: nixosModules.default = import ./modules (shared-only set)."
  - "Move homepage/restic to Contabo host import list and repos to OVH host import list."
  - "Deploy health checks and parts/cachix reporting must be node-aware to avoid OVH false failures."

duration: 12min
completed: 2026-02-27
---

# Phase 38 Plan 01: Dual-Host Role Separation Summary

**Implemented shared-vs-host-specific module separation and made deploy validation logic node-aware, with flake checks passing for both hosts.**

## Performance

- **Duration:** ~12min
- **Started:** 2026-02-27T18:24:00+01:00
- **Completed:** 2026-02-27T18:35:35+01:00
- **Tasks:** 6 completed
- **Files modified:** 7

## Accomplishments
- Reduced `modules/default.nix` to the 11 shared modules and moved host-specific imports to host defaults.
- Updated `scripts/deploy.sh` to select health-check services by node and skip parts/cachix paths for OVH.
- Verified both hosts evaluate/build via `nix flake check`; validated module allocation with targeted `nix eval` checks.

## Task Commits

1. **Task 1: Shared module set in `modules/default.nix`** - `4050e0e` (refactor)
2. **Task 2: Contabo host imports** - `42dd691` (feat)
3. **Task 3: OVH host imports** - `aae7ea5` (feat)
4. **Task 4: Node-aware deploy health checks** - `e0e91d0` (fix)
5. **Task 5: Secrets blocker fix during audit** - `9ad4c6d` (fix)

## Files Created/Modified
- `modules/default.nix` - Added shared-module header and removed `homepage.nix`/`restic.nix` imports.
- `hosts/neurosys/default.nix` - Added Contabo-only imports for `homepage.nix` and `restic.nix`.
- `hosts/ovh/default.nix` - Added OVH-only import for `repos.nix`.
- `scripts/deploy.sh` - Made `SYSTEMD_SERVICES` conditional on node; guarded parts update/revision and cachix push for neurosys.
- `modules/secrets.nix` - Removed stale `openclaw-jordan-claw-gateway-token` declaration blocking flake checks.
- `.planning/STATE.md` - Updated current position and decisions for Phase 38 completion.
- `.planning/phases/38-dual-host-role-separation-contabo-as-services-host-ovh-as-dev-agent-host/38-01-SUMMARY.md` - Added this summary.

## Decisions Made
- Keep shared module exports in `modules/default.nix`; host-specific behavior belongs in host `imports`.
- Health checks must reflect actual services on target node to prevent deploy false negatives.
- Fix stale shared secret declarations proactively when they block evaluation (`[Rule 3 - Blocking]`).

## Deviations from Plan
- **[Rule 3 - Blocking]** `nix flake check` initially failed on a pre-existing missing secret key (`openclaw-jordan-claw-gateway-token`). Resolved by removing the stale shared declaration from `modules/secrets.nix`.

## Issues Encountered
- `nix flake check` failed before host/module split completion due stale secret declaration mismatch with `secrets/neurosys.yaml`.
- Resolved in tracked code without editing encrypted secret data.

## Next Phase Readiness
- Ready for 38-02 deploy execution: both host configs evaluate and build, and deploy checks now align with per-node service reality.

---
*Phase: 38-dual-host-role-separation-contabo-as-services-host-ovh-as-dev-agent-host*
*Completed: 2026-02-27*
