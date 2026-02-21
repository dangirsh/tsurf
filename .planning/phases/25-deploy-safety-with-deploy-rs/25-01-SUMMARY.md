---
phase: 25-deploy-safety-with-deploy-rs
plan: 01
subsystem: deployment-safety
tags: [deploy-rs, nixos, rollback, tailscale, deploy-script]

requires:
  - phase: 10-parts-deployment-pipeline
    provides: existing deploy.sh flow with locking + container health verification
provides:
  - deploy-rs flake input and top-level deploy node for neurosys
  - pinned deploy-rs CLI passthrough (`nix run .#deploy-rs`)
  - deploy schema validation in `nix flake check` via deployChecks
  - deploy.sh flags for first migration and intentional no-rollback deploys
  - recovery runbook appendix for magic rollback behavior and procedures
affects: [deployment, recovery, operations, phase-26]

tech-stack:
  added: [deploy-rs]
  patterns: [magic rollback, version-pinned CLI passthrough, deploy checks at flake-check time]

key-files:
  created:
    - .planning/phases/25-deploy-safety-with-deploy-rs/25-01-SUMMARY.md
  modified:
    - flake.nix
    - flake.lock
    - scripts/deploy.sh
    - docs/recovery-runbook.md

key-decisions:
  - "Use deploy-rs with `confirmTimeout = 120` and magic rollback enabled by default."
  - "Expose deploy-rs CLI through `packages.x86_64-linux.deploy-rs` so script and activation library share the same pinned lock entry."
  - "Keep existing local+remote deploy locks and container health checks as defense in depth around deploy-rs activation."

duration: 32min
completed: 2026-02-21
---

# Phase 25 Plan 01: Deploy Safety with deploy-rs Summary

**Integrated deploy-rs magic rollback (120s confirm timeout) into neurosys deploy flow while preserving lock protection and post-deploy container health verification.**

## Performance

- **Duration:** 32min
- **Started:** 2026-02-21T10:05:00Z
- **Completed:** 2026-02-21T10:37:19Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Added top-level `deploy.nodes.neurosys` config in `flake.nix` with `magicRollback = true`, `autoRollback = true`, `confirmTimeout = 120`, and `activate.nixos` path wiring to `self.nixosConfigurations.neurosys`.
- Added `packages.x86_64-linux.deploy-rs` passthrough and `checks = mapAttrs ... deployChecks self.deploy`, then validated with `nix flake check`.
- Replaced `nixos-rebuild switch` calls in `scripts/deploy.sh` with `nix run "$FLAKE_DIR#deploy-rs" -- "$FLAKE_DIR#neurosys" ...`, including `--remote-build` mode.
- Added `--first-deploy` and `--no-magic-rollback` flags in `scripts/deploy.sh`, plus explicit warning that `--target` only affects SSH lock/health-check commands.
- Added Appendix 11 to `docs/recovery-runbook.md` documenting deploy-rs magic rollback behavior, first deploy migration procedure, manual rollback, and intentional rollback disable use-cases.

## Task Commits

1. **Task 1: Add deploy-rs flake input and deploy node/checks wiring** - `1da38a5` (feat)
2. **Task 2: Migrate deploy.sh to deploy-rs and update runbook** - `b41223c` (feat)

## Files Created/Modified
- `flake.nix` - deploy-rs input, deploy node, package passthrough, deploy checks.
- `flake.lock` - lock entries for deploy-rs and transitive inputs.
- `scripts/deploy.sh` - deploy-rs invocation + new rollback control flags.
- `docs/recovery-runbook.md` - Appendix 11 for rollback behavior and procedures.

## Decisions Made
- Deploy target for activation is canonicalized in flake (`deploy.nodes.neurosys.hostname = "neurosys"`), while `--target` remains for SSH lock/check operations.
- Magic rollback is default-on for safety, with explicit operator escape hatches: `--first-deploy` and `--no-magic-rollback`.
- Recovery docs now treat deploy-rs auto-rollback as first-line protection and manual `nixos-rebuild switch --rollback` as fallback for non-connectivity failures.

## Deviations from Plan
- `nix flake show` renders the top-level `deploy` output as `unknown` (normal for non-standard flake outputs); verification used `nix eval .#deploy.nodes.neurosys` to confirm concrete node values.

## Issues Encountered
- Initial command typo (`nix -C ... flake check`) was corrected to run from repo working directory.

## Next Phase Readiness
- Deploy pipeline is now rollback-safe for SSH connectivity regressions.
- Operator has documented first-deploy migration procedure and intentional rollback-disable guidance for networking changes.
- Phase 26 (Telegram notifications) can build on the updated deploy lifecycle hooks if needed.
