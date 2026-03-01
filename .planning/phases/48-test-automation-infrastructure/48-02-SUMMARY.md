---
phase: 48-test-automation-infrastructure
plan: 02
subsystem: testing
tags: [bats, nix-checks, nixos, ssh, test-automation]
requires:
  - phase: 40-agentd-integration
    provides: agentd module for testing
provides:
  - 20 Nix eval checks in flake.nix checks output
  - BATS live test harness with 64 total tests (25 new deep tests)
  - nix run .#test-live entry point
  - scripts/run-tests.sh wrapper with --json output mode
affects: [48-02, phase-47]
tech-stack:
  added: [github-actions]
  patterns: [TAP output, SSH-over-BATS, nix-native eval checks, NDJSON test summaries]
key-files:
  created: [tests/live/agentd.bats, tests/live/monitoring.bats, tests/live/impermanence.bats, tests/live/sandbox.bats, tests/live/networking.bats, .github/workflows/test.yml]
  modified: [tests/lib/common.bash, scripts/run-tests.sh, flake.nix, tests/eval/config-checks.nix, CLAUDE.md, .planning/STATE.md]
key-decisions:
  - "Deep runtime checks are split into dedicated files to keep debugging localized"
  - "run-tests.sh --json emits one object per TAP test (name/status/error) for agent consumption"
  - "CI runs eval checks/build only; live tests stay SSH-only outside GitHub Actions"
duration: 82min
completed: 2026-03-01
---

# Phase 48 Plan 02: Deep Validation + Agent Integration Polish Summary

Extended the Phase 48 test stack with 5 deep live suites, machine-parseable JSON output, CI eval checks, and private-overlay testing guidance.

## Performance
- **Duration:** 82 min
- **Tasks:** 11
- **Files modified:** 12

## Accomplishments
- Added deep live suites for agentd, monitoring, impermanence, sandbox isolation, and networking.
- Increased live BATS coverage from 39 to 64 tests (25 additional tests).
- Added `--json` mode to `scripts/run-tests.sh` with TAP parsing into one JSON object per test (`name`, `status`, `error`).
- Added GitHub Actions workflow `.github/workflows/test.yml` to run `nix flake check` and `nix build .#test-live` on push/PR.
- Expanded flake shellcheck coverage to include `scripts/run-tests.sh` and live BATS files (BATS warnings non-blocking).
- Updated `CLAUDE.md` with test run conventions, failure triage flow, and private overlay extension notes.
- Documented private overlay eval extension pattern in `tests/eval/config-checks.nix` comments.
- Verified `nix flake check` passes and `nix build .#test-live --no-link` succeeds.

## Task Commits
- 48-02-A: `18c2712` — deep agentd live validation tests
- 48-02-B: `858b170` — deep monitoring live validation tests
- 48-02-C: `f24e6c3` — impermanence live validation tests
- 48-02-D: `6e19cc8` — sandbox isolation live tests
- 48-02-E: `1f35483` — deep networking live tests
- 48-02-F: `dcc241e` — JSON output mode + retry diagnostics
- 48-02-G: `bcb753d` — GitHub Actions eval-check workflow
- 48-02-H: `a246ceb` — CLAUDE testing conventions update
- 48-02-I: `e2a5d42` — private overlay extension documentation
- [Rule 1 - Bug] `f973930` — fixed JSON escaping/name parsing for TAP failures
- `3a2104d` — expanded shellcheck checks in flake

## Deviations from Plan
- [Rule 1 - Bug] JSON output initially emitted invalid JSON for multiline failure text; fixed by escaping newlines and correcting TAP name stripping.
- [Rule 3 - Blocking] `shellcheck` binary was not directly available in shell; verification executed via `nix shell nixpkgs#shellcheck`.

## Issues Encountered
- Existing Home Manager deprecation warnings still appear during `nix flake check` (SSH/Git option rename warnings); checks remain passing.

## Next Phase Readiness
Phase 48 is complete. Next phase can consume JSON test output and CI checks for tighter agent-driven remediation loops.
