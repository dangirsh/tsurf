---
phase: 160-harden-core-dependency-trust-boundary-march-27-review-finding-3
plan: 03
subsystem: integration-verification
tags: [security, trust-boundary, cass, eval-checks, regression-guards]
provides:
  - Integration verification that CASS remains outside the default trust path and explicit security anchors are enforced by eval checks
affects: [159, 160]
tech-stack:
  added: []
  patterns: ["Eval-time regression guards", "Doc-to-implementation consistency validation"]
key-files:
  created: [".planning/phases/160-harden-core-dependency-trust-boundary-march-27-review-finding-3/160-03-SUMMARY.md"]
  modified: ["tests/eval/config-checks.nix", "SECURITY.md", ".planning/STATE.md"]
key-decisions:
  - "SEC-160: Add explicit eval guards for firewall, SSH auth/X11, and critical sysctls so trust anchors remain self-backing."
duration: 47min
completed: 2026-04-03
---

# Phase 160 Plan 03: Integration Verification Summary

**Explicit trust-anchor assertions now have eval-time regression guards and final documentation consistency checks across all Phase 160 changes.**

## Accomplishments
- Verified Phase 159 CASS hardening remains intact: `extras/cass.nix` defaults off via `mkEnableOption`, and neither `hosts/dev/default.nix` nor `hosts/services/default.nix` imports `extras/cass.nix`.
- Added seven new eval checks in `tests/eval/config-checks.nix` for explicit firewall/SSH/sysctl security settings (`explicit-firewall-enabled`, `explicit-ssh-password-auth`, `explicit-ssh-kbd-auth`, `explicit-ssh-x11`, `explicit-kexec-disabled`, `explicit-bpf-restricted`, `explicit-io-uring-disabled`).
- Updated `SECURITY.md` supply-chain wording so `nono` is documented as source-built from pinned upstream source and prebuilt-binary risk language applies only to remaining prebuilt artifacts.
- Ran full `nix flake check`; all checks pass.

## Task Commits
1. Task 1: Verify CASS default-path removal and add explicit-settings eval checks - `e7fe3ef` (test)
2. Task 2: Final SECURITY.md consistency check and full verification - `19cd0d2` (docs)

## Files Created/Modified
- `.planning/phases/160-harden-core-dependency-trust-boundary-march-27-review-finding-3/160-03-SUMMARY.md` - Plan 03 execution summary and outcomes.
- `tests/eval/config-checks.nix` - Added explicit trust-anchor checks for firewall/SSH/sysctl assertions.
- `SECURITY.md` - Corrected nono supply-chain claim from prebuilt to source-built and scoped prebuilt signature risk language.
- `.planning/STATE.md` - Updated project position, phase completion status, and decision log for Plan 03.

## Decisions Made
- Keep sysctl checks value-strict while type-robust by normalizing evaluated values through `toString` before comparing to `"1"`/`"2"`.

## Deviations from Plan
- [Rule 1 - Bug] The plan assumed evaluated sysctl values were strings; actual eval values were ints (`1`/`2`). Checks were adjusted to `toString ... == "1"/"2"` to preserve the intended invariant without loosening validation.

## Issues Encountered
- The initial verify pipeline (`nix flake check | grep | head`) can terminate output early; full validation was run separately with complete `nix flake check`.

## Next Phase Readiness
Phase 160 is fully complete (3/3 plans). Trust-boundary claims are now explicitly backed by code, regression-guarded at eval time, and consistent with `SECURITY.md`.
