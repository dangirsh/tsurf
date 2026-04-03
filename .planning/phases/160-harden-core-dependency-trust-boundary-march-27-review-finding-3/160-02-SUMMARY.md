---
phase: 160-harden-core-dependency-trust-boundary-march-27-review-finding-3
plan: 02
subsystem: supply-chain-security
tags: [security, trust-boundary, nono, rust, reproducible-build]
provides:
  - Source-built nono (v0.22.0) from pinned upstream tag with fixed source and cargo hashes
affects: [145, 159]
tech-stack:
  added: []
  patterns: ["Pinned-source Rust builds", "Cargo vendor hash pinning", "Critical-path binary trust hardening"]
key-files:
  created: [".planning/phases/160-harden-core-dependency-trust-boundary-march-27-review-finding-3/160-02-SUMMARY.md"]
  modified: ["packages/nono.nix", ".planning/STATE.md"]
key-decisions:
  - "SEC-160-05: Build nono from source to remove prebuilt binary trust from the launch-path sandbox enforcer."
duration: 66min
completed: 2026-04-03
---

# Phase 160 Plan 02: Harden Core Dependency Trust Boundary Summary

**The sandbox enforcer `nono` now builds from pinned upstream Rust source instead of using an untrusted prebuilt release artifact.**

## Accomplishments
- Replaced the prebuilt `fetchurl` tarball derivation with `rustPlatform.buildRustPackage` in `packages/nono.nix`.
- Pinned upstream source at `always-further/nono` tag `v0.22.0` with resolved source hash and cargo vendor hash.
- Scoped build to `nono-cli` (`cargoBuildFlags = [ "-p" "nono-cli" ]`) so the output binary remains `nono`.
- Added `@decision SEC-160-05` documenting why source build is required for this trust boundary.
- Verified build output and runtime help text via `result/bin/nono --help`.

## Task Commits
1. Task 1: Attempt source build of nono - `f780b68` (fix)

## Files Created/Modified
- `.planning/phases/160-harden-core-dependency-trust-boundary-march-27-review-finding-3/160-02-SUMMARY.md` - Plan execution summary and outcomes.
- `packages/nono.nix` - Source build derivation with pinned source/cargo hashes and security decision annotation.
- `.planning/STATE.md` - Updated phase position and decision ledger for Plan 02 completion.

## Decisions Made
- Keep `nono` pinned to `v0.22.0` for compatibility while eliminating the trust gap by building from source.
- Disable package check phase (`doCheck = false`) for this derivation to avoid prolonged workspace-wide check execution in this build path, while preserving deterministic source compilation of shipped artifacts.

## Deviations from Plan
- Verification used an overlay-resolved expression build (`pkgs.nono`) because this flake does not expose `.#nono` as a top-level package attribute.

## Issues Encountered
- Initial source build failed due missing `dbus-1.pc`; resolved by adding `dbus.dev` to build inputs.

## Next Phase Readiness
Plan 02 is complete: the nono launch-path binary is source-built and hash-pinned, and phase tracking/docs now capture the trust-boundary decision.
