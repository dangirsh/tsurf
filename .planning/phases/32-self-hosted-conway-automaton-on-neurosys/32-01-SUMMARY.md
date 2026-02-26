---
phase: 32-self-hosted-conway-automaton-on-neurosys
plan: 01
subsystem: infra
tags: [nixos, buildnpmpackage, nodejs, better-sqlite3, automaton, conway]
key-decisions:
  - "Use buildNpmPackage with a vendored converted package-lock.json for deterministic npmDepsHash"
  - "Patch Anthropic endpoint to honor ANTHROPIC_BASE_URL at runtime"
duration: 90min
completed: 2026-02-26
---

# Phase 32 Plan 01: Package Conway Automaton as NixOS Derivation Summary

Packaged `@conway/automaton` as a reproducible Nix derivation exposed at `packages.x86_64-linux.automaton`, with native `better-sqlite3` compile and Anthropic base URL env patching.

## Performance
- **Duration:** 90 min
- **Tasks:** 5 completed
- **Files modified:** 6

## Accomplishments
- Added `inputs.automaton` (`flake = false`) and pinned it in `flake.lock`.
- Implemented `packages/automaton.nix` via `buildNpmPackage` (Node 22, TS compile, native addon rebuild).
- Patched upstream `src/conway/inference.ts` URL reference to use `ANTHROPIC_BASE_URL` fallback behavior.
- Added vendored converted lockfile (`packages/automaton-package-lock.json`) and pinned `npmDepsHash`.
- Verified `nix build .#automaton` and `nix flake check` (neurosys + ovh) both pass.

## Task Commits
1. **Task 32-01-A: Add automaton input/output wiring** - `65c6ea8` (feat)
2. **Task 32-01-B/C/D/E: Package, validate build/check, finalize derivation** - `68166c1` (feat)

## Files Created/Modified
- `flake.nix` - added `automaton` input usage in packages output and consolidated dynamic package attrset
- `flake.lock` - pinned `github:Conway-Research/automaton` rev/hash
- `packages/automaton.nix` - automaton derivation with lockfile vendoring, endpoint patch, TS compile, native rebuild, wrapper
- `packages/automaton-package-lock.json` - converted npm lockfile used by `buildNpmPackage`
- `.planning/phases/32-self-hosted-conway-automaton-on-neurosys/32-01-SUMMARY.md` - this execution summary
- `.planning/STATE.md` - updated current phase/progress and decisions

## Decisions Made
- Used a vendored converted npm lockfile rather than in-sandbox conversion to keep `fetchNpmDeps` deterministic.
- Kept explicit `npm rebuild better-sqlite3` in `buildPhase` to guarantee native addon compilation.

## Deviations from Plan
- `[Rule 1 - Bug]` Found invalid duplicated dynamic attr assignment in `flake.nix` (`packages.${system}` defined twice). Fixed by grouping package outputs into one attrset.
- `[Rule 3 - Blocking]` In-sandbox `pnpm import` failed (network/certificate/tool bootstrap). Switched to vendored converted lockfile (`automaton-package-lock.json`) and copied it in `postPatch`.
- `[Rule 1 - Bug]` Wrapper script initially emitted runtime path with literal `$out`; fixed heredoc expansion so `bin/automaton` resolves packaged `dist/index.js` correctly.

## Issues Encountered
- `pnpm import` attempted network/tool bootstrap in fetcher derivation and failed due sandbox/cert constraints; resolved by lockfile vendoring.
- `./result/bin/automaton --help` does not print conventional help text but exits cleanly with runtime startup info logs.

## Self-Check
PASSED: `nix build .#automaton` succeeds; output contains `lib/node_modules/@conway/automaton/dist/index.js`, `constitution.md`, and patched `ANTHROPIC_BASE_URL` logic (`dist/conway/inference.js`); `nix flake check` passed.

## Next Phase Readiness
Phase 32 Plan 02 can now consume `packages.x86_64-linux.automaton` for systemd service/module wiring and secret-proxy integration.

---
*Phase: 32-self-hosted-conway-automaton-on-neurosys*
*Completed: 2026-02-26*
