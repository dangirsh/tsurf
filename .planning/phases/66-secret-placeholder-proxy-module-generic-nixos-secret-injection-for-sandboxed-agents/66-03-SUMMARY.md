---
phase: 66-secret-placeholder-proxy-module-generic-nixos-secret-injection-for-sandboxed-agents
plan: "03"
subsystem: infra
tags: [nixos, secret-proxy, sops, eval-checks, live-tests]

requires:
  - phase: "66-02"
    provides: Generic `services.secretProxy.services` module schema and service materialization
provides:
  - Private overlay declaration for `services.secretProxy.services.claw-swap` on port 9091
  - Secret permission model allowing `secret-proxy-claw-swap` group access to `anthropic-api-key`
  - Public + private eval checks aligned with generic secret-proxy module usage
affects: [phase-67, private-overlay, deploy-validation, secret-injection]

tech-stack:
  added: []
  patterns: [private overlay service declaration via public module option, owner+group secret sharing for service users]

key-files:
  created: []
  modified:
    - tests/eval/config-checks.nix
    - tests/live/api-endpoints.bats
    - .test-status
    - /data/projects/private-neurosys/flake.nix
    - /data/projects/private-neurosys/modules/secrets.nix
    - /data/projects/private-neurosys/tests/eval/private-checks.nix

key-decisions:
  - "Declare claw-swap proxy in private overlay contaboModules using services.secretProxy.services.claw-swap."
  - "Keep anthropic-api-key owner as dangirsh but add group secret-proxy and mode 0440 for proxy user access."
  - "Use schema-level public eval check (`has-secret-proxy-option`) and private service-level eval check (`secret-proxy-claw-swap-service`)."

patterns-established:
  - "Private-only consumers of generic public modules should be verified in private overlay eval checks, not public service assertions."
  - "Secret-sharing between human user and system service should use owner+group 0440 rather than owner reassignment."

duration: 8 min
completed: 2026-03-07
---

# Phase 66 Plan 03: Migration, Eval Checks, and Live Tests Summary

**Private claw-swap now consumes the generic secret-proxy module on port 9091 with proper sops file permissions, while public and private eval/live checks were updated to the new service schema and naming.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-07T19:22:49Z
- **Completed:** 2026-03-07T19:31:32Z
- **Tasks:** 10
- **Files modified:** 8

## Accomplishments
- Added `services.secretProxy.services.claw-swap` in private overlay with `anthropic-api-key` file-backed secret injection.
- Updated private secret ownership model so both `dangirsh` and `secret-proxy-claw-swap` can read the Anthropic key safely (`0440`, `secret-proxy` group).
- Added private eval assertion `secret-proxy-claw-swap-service` and public eval assertion `has-secret-proxy-option`.
- Updated public live test debug guidance to `secret-proxy-claw-swap` and refreshed `.test-status` after successful `nix flake check`.

## Task Commits

Each task was committed atomically:

1. **Task 66-03 (public repo updates + flake check status):** `435f4c5` (feat)
2. **Task 66-03 (private overlay migration + private eval checks):** `6b4842d` (feat)

**Plan metadata:** `(this docs commit)`

## Files Created/Modified
- `tests/eval/config-checks.nix` - Added `has-secret-proxy-option` schema check.
- `tests/live/api-endpoints.bats` - Updated secret proxy debug unit name to `secret-proxy-claw-swap`.
- `.test-status` - Updated to `pass|0|<timestamp>` after successful check run.
- `/data/projects/private-neurosys/flake.nix` - Declared `services.secretProxy.services.claw-swap` inline in `contaboModules`.
- `/data/projects/private-neurosys/modules/secrets.nix` - Set `anthropic-api-key` owner/group/mode for shared access.
- `/data/projects/private-neurosys/tests/eval/private-checks.nix` - Added `secret-proxy-claw-swap-service` assertion.
- `/data/projects/private-neurosys/modules/automaton.nix` - Migrated dependency from `anthropic-secret-proxy.service` to `secret-proxy-claw-swap.service`.
- `/data/projects/private-neurosys/packages/automaton.nix` - Updated rationale comment to reflect new service name.

## Decisions Made
- Wired private consumer config in `flake.nix` (contabo-only scope) instead of global/common modules to avoid impacting OVH.
- Preserved existing proxy port (`9091`) and base URL env var (`ANTHROPIC_BASE_URL`) to avoid consumer/runtime behavior changes.
- Kept public service-health checks generic; private-only service existence is enforced in private eval checks.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Legacy private references still used `anthropic-secret-proxy`**
- **Found during:** Task 66-03-B (private overlay reference verification)
- **Issue:** `modules/automaton.nix` still depended on `anthropic-secret-proxy.service`; package rationale comment also referenced old unit.
- **Fix:** Switched dependency/comment to `secret-proxy-claw-swap` naming.
- **Files modified:** `/data/projects/private-neurosys/modules/automaton.nix`, `/data/projects/private-neurosys/packages/automaton.nix`
- **Verification:** `rg -n "anthropic-secret-proxy|secret-proxy-env" /data/projects/private-neurosys` returns no matches.
- **Committed in:** `6b4842d`

**2. [Rule 3 - Blocking] Private flake pin does not include Phase 66 public module changes**
- **Found during:** Task 66-03-A verification (`nix eval` in private overlay)
- **Issue:** Private overlay input pin `github:dangirsh/neurosys@af29add` lacks `services.secretProxy` option.
- **Fix:** Verified private eval using local override input (`--override-input neurosys /data/projects/neurosys`) without mutating lockfile.
- **Files modified:** none
- **Verification:** `nix eval --override-input neurosys /data/projects/neurosys .#nixosConfigurations.neurosys.config.system.build.toplevel` succeeds.
- **Committed in:** N/A (verification-path adjustment)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking)
**Impact on plan:** Migration completed with no scope creep; one verification caveat remains until private input pin is advanced to a public revision containing Phase 66 commits.

## Issues Encountered
- `nix eval` on this machine does not accept `--no-build`; equivalent verification used plain `nix eval`.
- Private overlay pinned input (`af29add`) predates Phase 66 public changes; pin advancement is required for un-overridden private eval.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 66 is complete (all three plans done).
- Public checks are green and private consumer wiring is in place.
- Before deploy workflows that do not use input overrides, advance private `neurosys` flake pin to a revision containing Phase 66 commits.

---
*Phase: 66-secret-placeholder-proxy-module-generic-nixos-secret-injection-for-sandboxed-agents*
*Completed: 2026-03-07*
