---
phase: 30-claw-swap-native-nixos-service
plan: 01
subsystem: infra
tags: [nixos, claw-swap, postgresql, systemd, sops-nix]
key-decisions:
  - "Run claw-swap as native NixOS services instead of oci-containers"
  - "Use local trust auth for OS user claw-swap -> DB role claw over Unix socket"
  - "Add missing API key entries to both host secret files so flake checks can validate manifests"
duration: 120min
completed: 2026-02-25
---

# Phase 30 Plan 01: Claw-Swap Native NixOS Service Summary

**Claw-swap now runs as native NixOS services, and flake checks pass in both claw-swap and neurosys after synchronizing inputs and fixing secret manifest blockers.**

## Performance
- **Duration:** 120 min
- **Tasks:** 9 completed
- **Files modified:** 7

## Accomplishments
- Replaced claw-swap Docker runtime wiring with `services.postgresql` + `systemd.services.claw-swap-app` in the claw-swap module.
- Refactored `nix/claw-swap-app.nix` to return the `buildNpmPackage` derivation directly.
- Verified `/data/projects/claw-swap` with `nix build .#claw-swap-app` and `nix flake check`.
- Synced neurosys `claw-swap` input to latest pushed commit and verified `nix flake check` passes.
- Confirmed neurosys support-module targets are in desired state (`impermanence`, `restic`, `homepage`, `docker` annotations).
- Updated state tracking and recorded this execution in planning docs.

## Task Commits
1. **claw-swap native service migration** - `1f7fb2e` (feat)
2. **ensureDBOwnership assertion blocker fix** - `03996a5` (fix)

## Files Created/Modified
- `.planning/phases/30-claw-swap-native-nixos-service/30-01-SUMMARY.md` - execution summary for plan 30-01.
- `.planning/STATE.md` - current position/decisions/session continuity updated for phase 30 execution.
- `secrets/neurosys.yaml` - added encrypted `google-api-key` and `xai-api-key` placeholders for manifest validation.
- `secrets/ovh.yaml` - added encrypted `google-api-key` and `xai-api-key` placeholders for manifest validation.
- `nix/claw-swap-app.nix` (claw-swap repo) - now returns package derivation directly.
- `nix/module.nix` (claw-swap repo) - native postgres + systemd app service and Docker removal.

## Decisions Made
- Kept claw-swap in native service mode with Unix socket auth and no DB password in `DATABASE_URL`.
- Accepted a blocker fix in claw-swap module: removed `ensureDBOwnership = true` for role `claw` because NixOS asserts same-name DB ownership only.
- Added placeholder API key entries in encrypted host secrets to restore `sops-install-secrets` manifest validity for flake checks.

## Deviations from Plan
- **[Rule 1 - Bug]**
  - **Found during:** neurosys flake check after updating claw-swap input
  - **Issue:** `ensureDBOwnership = true` with user `claw` and database `claw_swap` violates NixOS postgresql assertion (same-name DB required)
  - **Fix:** removed `ensureDBOwnership` from `services.postgresql.ensureUsers`
  - **Files:** `claw-swap/nix/module.nix`
  - **Verification:** `nix flake check` in `/data/projects/claw-swap` passed
  - **Commit:** `03996a5`
- **[Rule 3 - Blocking]**
  - **Found during:** neurosys flake check
  - **Issue:** `sops-install-secrets` manifest validation failed because `google-api-key`/`xai-api-key` were declared but missing from encrypted host secret files
  - **Fix:** added encrypted placeholder keys to both `secrets/neurosys.yaml` and `secrets/ovh.yaml`
  - **Files:** `secrets/neurosys.yaml`, `secrets/ovh.yaml`
  - **Verification:** `nix flake check` in `/data/projects/neurosys` passed
  - **Commit:** included in neurosys phase-30 commit

## Issues Encountered
- Push race on `claw-swap/main` required rebase because origin advanced during execution.
- Rebase conflict in `claw-swap/nix/module.nix` resolved by keeping the native-service config plus existing Caddy/firewall sections.

## Next Phase Readiness
- Plan 30-01 code and validation gates are complete.
- Ready for Plan 30-02 human deployment checkpoint.

---
*Phase: 30-claw-swap-native-nixos-service*
*Completed: 2026-02-25*
