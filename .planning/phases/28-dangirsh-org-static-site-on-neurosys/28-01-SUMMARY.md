---
phase: 28-dangirsh-org-static-site-on-neurosys
plan: 01
subsystem: dangirsh-site-build
tags: [nix, flake, hakyll, static-site, nginx]

requires:
  - phase: 27-ovh-vps-production-migration
    provides: neurosys multi-host flake baseline and deployment workflow
provides:
  - flake output `packages.x86_64-linux.default` for dangirsh.org static site
  - nixos-25.11 pinned flake input for reproducible site builds
  - cabal bounds compatible with nixos-25.11 Haskell package set (`pandoc 3.7`)
affects: [neurosys-nginx-root, external-repo-dangirsh-site, phase-28]

tech-stack:
  added: [nix-flakes]
  patterns: [two-derivation build, hakyll generator in nix store, static output copy to $out]

key-files:
  created:
    - /data/projects/dangirsh-site/flake.nix
    - /data/projects/dangirsh-site/flake.lock
    - .planning/phases/28-dangirsh-org-static-site-on-neurosys/28-01-SUMMARY.md
  modified:
    - /data/projects/dangirsh-site/generator/site.cabal
    - .planning/STATE.md

key-decisions:
  - "Pin dangirsh-site flake to `github:NixOS/nixpkgs/nixos-25.11` and expose `packages.x86_64-linux.default` for direct neurosys consumption."
  - "Keep Hakyll constraint at 4.16.x and only widen pandoc upper bound to `< 3.8` to match nixos-25.11 (`pandoc 3.7.0.2`)."
  - "Generate site output in a dedicated derivation that copies full `_site` content to `$out` for Nix-store-backed nginx serving."

duration: 6min
completed: 2026-02-23
---

# Phase 28 Plan 01: Modernize dangirsh-site Build to Flake

**Shipped a nixos-25.11 flake in `dangirsh-site` that builds the full Hakyll site into the Nix store via `packages.x86_64-linux.default`, then pushed it to GitHub for neurosys flake input consumption.**

## Performance

- **Duration:** 6min
- **Started:** 2026-02-23T20:29:00Z
- **Completed:** 2026-02-23T20:35:13Z
- **Tasks:** 1
- **Files changed:** 5 (3 in `/data/projects/dangirsh-site`, 2 in `/data/projects/neurosys`)

## Accomplishments

- Created `/data/projects/dangirsh-site/flake.nix` with `nixos-25.11` input and `packages.x86_64-linux.default` output.
- Implemented two-stage derivation flow in flake: compile `generator/site.hs` with `ghcWithPackages`, then run `generator build` against `site/` and copy `_site/*` to `$out`.
- Added `/data/projects/dangirsh-site/flake.lock` by building the flake.
- Updated `/data/projects/dangirsh-site/generator/site.cabal` pandoc bound from `< 3.6` to `< 3.8` for nixos-25.11 compatibility (`pandoc 3.7.0.2`).
- Verified `nix build` and `nix flake check` both pass and output contains `index.html`, `css/`, and `posts/`.
- Fast-forwarded/rebased/pushed to GitHub; final remote commit on `master` is `c309419`.

## Task Commits

1. **Task 1: Create flake.nix and modernize Haskell bounds for nixos-25.11 build** - `c309419` (feat)

## Files Created/Modified

- `/data/projects/dangirsh-site/flake.nix` - new flake with default package output for static site derivation.
- `/data/projects/dangirsh-site/flake.lock` - locked nixpkgs input (`nixos-25.11` revision).
- `/data/projects/dangirsh-site/generator/site.cabal` - widened `pandoc` upper bound to `< 3.8`.
- `.planning/phases/28-dangirsh-org-static-site-on-neurosys/28-01-SUMMARY.md` - plan execution summary.
- `.planning/STATE.md` - current phase/progress/decisions updated.

## Decisions Made

- Build target for neurosys is the flake default package path (`packages.x86_64-linux.default`) rather than legacy `default.nix` + `nix-build`.
- Locale settings remain explicit (`LANG`, `LOCALE_ARCHIVE`) in site derivation to preserve UTF-8 behavior.
- Compatibility change was minimal and source-grounded: only `pandoc` upper bound changed because `hakyll 4.16.7.1` already matches existing bounds.

## Deviations from Plan

- [Rule 3 - Blocking] `git push origin master` was rejected because remote `master` had advanced; resolved by `git fetch` + `git rebase origin/master` + push.
- `nix build` initially failed before tracking `flake.nix` (flake source must be git-tracked); resolved by staging the new file before build.

## Issues Encountered

- None remaining. All verification commands passed after resolving the two blockers above.

## Next Phase Readiness

- Neurosys can now reference `github:dangirsh/dangirsh.org` as a flake input and use the resulting store path as nginx `root`.
- Plan 28-02 can proceed with neurosys-side flake input wiring and nginx integration.
