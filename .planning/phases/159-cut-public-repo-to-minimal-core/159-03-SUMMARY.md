---
phase: 159-cut-public-repo-to-minimal-core
plan: 03
subsystem: documentation
tags: [docs, minimal-core, quickstart, extras, private-overlay]
provides:
  - "Cross-document consistency for the minimal-core public repo model"
affects:
  - "README.md"
  - "docs/architecture.md"
  - "docs/extras.md"
  - "SECURITY.md"
  - "CLAUDE.md"
  - "examples/private-overlay/flake.nix"
  - "examples/private-overlay/hosts/example/default.nix"
  - "examples/private-overlay/README.md"
tech-stack:
  added: []
  patterns:
    - "Quickstart-first newcomer path"
    - "Opt-in extras documentation model"
    - "Generic launcher framed as advanced extension API"
key-files:
  created: [".planning/phases/159-cut-public-repo-to-minimal-core/159-03-SUMMARY.md"]
  modified:
    - "README.md"
    - "docs/architecture.md"
    - "docs/extras.md"
    - "SECURITY.md"
    - "CLAUDE.md"
    - "examples/private-overlay/flake.nix"
    - "examples/private-overlay/hosts/example/default.nix"
    - "examples/private-overlay/README.md"
    - ".test-status"
    - ".planning/STATE.md"
key-decisions:
  - "Public docs should route newcomers through QUICKSTART.md and remove maintainer-only spec references."
  - "Extras and Home Manager usage are opt-in patterns; generic launcher docs should be framed as extension API guidance."
duration: 32min
completed: 2026-03-27
---

# Phase 159 Plan 03: Documentation updates across all affected files Summary

**Public documentation and examples now consistently describe the minimal-core baseline with opt-in extras and QUICKSTART-first onboarding.**

## Accomplishments
- Updated README navigation and content so newcomers start at `QUICKSTART.md`, with an explicit `Available Extras` section and extension-API pointer.
- Aligned architecture/extras/security/CLAUDE docs and private overlay examples to the same opt-in extras model.
- Removed stale public `spec/` references from active docs and validated with `nix flake check`.

## Task Commits
1. **Task 03.1: Update README.md** - `72ce47f` (docs)
2. **Task 03.2: Update docs/architecture.md** - `a46fe94` (docs)
3. **Task 03.3: Update docs/extras.md** - `262978b` (docs)
4. **Task 03.4: Update SECURITY.md** - `fd43064` (docs)
5. **Task 03.5: Update CLAUDE.md** - `1445186` (docs)
6. **Task 03.6: Update private overlay example files** - `9ed5865` (docs)
7. **Task 03.7: Final validation (`nix flake check`)** - `5ea9123` (test)

## Files Created/Modified
- `.planning/phases/159-cut-public-repo-to-minimal-core/159-03-SUMMARY.md` - Plan 03 execution summary.
- `.planning/STATE.md` - Advanced Phase 159 to Plan 03 complete and recorded Plan 03 decision.
- `README.md` - Added `Available Extras`, switched newcomer path to `QUICKSTART.md`, removed `spec` and `CLAUDE` doc links.
- `docs/architecture.md` - Updated fixture scope and opt-in extras language; removed stale `spec` reference.
- `docs/extras.md` - Reframed extras as opt-in and positioned custom agents as advanced extension API.
- `SECURITY.md` - Updated scope to reflect opt-in extras model and services/restic example.
- `CLAUDE.md` - Updated host fixture descriptions and key decision for opt-in extras.
- `examples/private-overlay/flake.nix` - Added grouped optional extras import examples and Home Manager opt-in pattern comment.
- `examples/private-overlay/hosts/example/default.nix` - Added Home Manager opt-in commented line.
- `examples/private-overlay/README.md` - Split required agent modules from optional extras and clarified CASS optionality.
- `.test-status` - Updated with passing `nix flake check` timestamp.

## Decisions Made
- Docs should describe only the shipped public behavior: core fixtures by default, extras enabled explicitly.
- The generic launcher should be documented as the advanced extension interface, with `extras/codex.nix` as a concrete example.

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None.

## Next Phase Readiness
Phase 159 is fully complete (3/3 plans) with passing `nix flake check` and consistent public documentation.
