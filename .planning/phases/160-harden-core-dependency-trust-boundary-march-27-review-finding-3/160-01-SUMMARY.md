---
phase: 160-harden-core-dependency-trust-boundary-march-27-review-finding-3
plan: 01
subsystem: security-hardening
tags: [security, trust-boundary, srvos, nix-mineral, self-backing]
provides:
  - Explicit in-repo security defaults for firewall, SSH auth, and critical sysctls
affects: [145, 159]
tech-stack:
  added: []
  patterns: ["Self-backing security declarations", "Annotated compatibility shims"]
key-files:
  created: [".planning/phases/160-harden-core-dependency-trust-boundary-march-27-review-finding-3/160-01-SUMMARY.md"]
  modified: ["modules/networking.nix", "modules/base.nix", "flake.nix", "SECURITY.md", ".planning/STATE.md"]
key-decisions:
  - "SEC-160-01/02/03/04: Critical security claims must be explicit in tsurf modules, with transitive modules treated as defense-in-depth."
duration: 54min
completed: 2026-04-03
---

# Phase 160 Plan 01: Harden Core Dependency Trust Boundary Summary

**Security claims now have explicit in-repo trust anchors for firewall, SSH defaults, and critical kernel/network sysctls instead of relying on transitive module defaults.**

## Accomplishments
- Added explicit `networking.firewall.enable = true` and explicit SSH auth/forwarding defaults in `modules/networking.nix` with decision annotations.
- Added explicit critical sysctls (`kexec`, `bpf`, `io_uring`, `sysrq`, source-route disable, `rp_filter`) in `modules/base.nix` with decision annotation.
- Annotated the nix-mineral compat shim in `flake.nix` with `@decision SEC-160-04`.
- Updated `SECURITY.md` to clearly separate self-backing defaults from inherited defense-in-depth.

## Task Commits
1. Task 1: Explicit srvos-overlapping settings in modules/networking.nix - `d2a0270` (fix)
2. Task 2: Explicit critical sysctls in modules/base.nix and annotate compat shim - `7f06e2a` (fix)
3. Task 3: Update SECURITY.md to distinguish explicit vs inherited settings - `7b8858c` (docs)

## Files Created/Modified
- `.planning/phases/160-harden-core-dependency-trust-boundary-march-27-review-finding-3/160-01-SUMMARY.md` - Plan execution summary and outcomes.
- `modules/networking.nix` - Explicit firewall and SSH inherited defaults with self-backing annotations.
- `modules/base.nix` - Explicit critical hardening sysctls with self-backing annotation.
- `flake.nix` - Compat shim annotated with upgrade/re-evaluation rationale.
- `SECURITY.md` - Trust-model language updated to distinguish explicit anchors vs inherited depth.
- `.planning/STATE.md` - Current position and decision ledger updated for Phase 160 Plan 01.

## Decisions Made
- Security claims in `SECURITY.md` must map to explicit declarations in tsurf-owned modules.
- `srvos` and `nix-mineral` remain important depth layers, but not the sole trust anchors for core claims.

## Deviations from Plan
None.

## Issues Encountered
None.

## Next Phase Readiness
Phase 160 Plan 01 is complete with passing `nix flake check` and explicit trust-boundary ownership captured in code and docs.
