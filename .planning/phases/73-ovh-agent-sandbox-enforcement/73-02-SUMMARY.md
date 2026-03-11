---
phase: 73-ovh-agent-sandbox-enforcement
plan: 02
subsystem: infra
tags: [nixos, bubblewrap, sandbox, agent-security]

requires: []
provides:
  - OVH live BATS coverage for sandbox wrapper behavior and isolation guarantees
  - Eval-time guard that enforces declaration of the agent audit tmpfiles directory
affects: [private-neurosys, deployment]

tech-stack:
  added: []
  patterns: [bubblewrap sandbox wrapper, audit logging]

key-files:
  created: [tests/live/agent-sandbox.bats]
  modified: [tests/eval/config-checks.nix, .test-status, .planning/STATE.md, .planning/ROADMAP.md]

key-decisions:
  - "73-02 tests are OVH-only with `is_ovh` guards to keep non-OVH live runs deterministic."
  - "Wrapper isolation checks are source-level (script content) plus runtime `--no-sandbox` rejection messaging."
  - "`agent-audit-dir` check prevents silent removal of `.agent-audit` tmpfiles declaration."

duration: 21min
completed: 2026-03-11
---

# Phase 73 Plan 02: OVH Agent Sandbox Live Validation Summary

**Added OVH-targeted live wrapper tests and eval checks that lock in sandbox isolation, guard behavior, and audit-dir declaration.**

## Performance
- **Duration:** 21min
- **Tasks:** 4
- **Files modified:** 5

## Accomplishments
- Added `tests/live/agent-sandbox.bats` with 6 OVH-only `${HOST}:` tests.
- Verified wrapper discovery in PATH (`claude` and `codex`) and bwrap invocation references.
- Added source-level assertions that wrappers do not mount `/run/secrets` or `~/.ssh`.
- Added runtime check that `claude --no-sandbox` requires `AGENT_ALLOW_NOSANDBOX=1`.
- Added eval check `agent-audit-dir` for OVH tmpfiles declaration.
- Ran `nix flake check` successfully and updated `.test-status`.

## Task Commits
1. **Task 73-02-A: Create live BATS tests** - `21f2285` (test)
2. **Task 73-02-B: Add eval audit-dir check** - `155edd7` (test)
3. **Task 73-02-C: Validate flake and set test status** - `8aa9559` (chore)

## Files Created/Modified
- `tests/live/agent-sandbox.bats` - OVH-only wrapper and sandbox behavior validation.
- `tests/eval/config-checks.nix` - Added `agent-audit-dir` eval check.
- `.test-status` - Updated after successful `nix flake check`.
- `.planning/STATE.md` - Marked Plan 73-02 and Phase 73 complete; recorded decisions.
- `.planning/ROADMAP.md` - Marked Phase 73 complete and listed plans 73-01/73-02.

## Decisions Made
- Keep live tests host-gated (`is_ovh`) and avoid real API execution by validating wrapper script content.
- Keep one runtime behavior assertion for `--no-sandbox` rejection path to verify guard enforcement.

## Deviations from Plan
- [Rule 3 - Blocking] `node ... gsd-tools.js state advance-plan` failed with parser error (`Cannot parse Current Plan or Total Plans in Phase from STATE.md`); state was updated manually.

## Issues Encountered
- Existing GSD parser incompatibility with current `STATE.md` format prevented automated plan advancement.

## Next Phase Readiness
Phase 73 is complete with live and eval coverage for OVH wrapper enforcement; Phase 72.1 or 74 can proceed next.

---
*Phase: 73-ovh-agent-sandbox-enforcement*
*Completed: 2026-03-11*
