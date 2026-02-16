---
phase: quick-001
plan: 01
subsystem: infra
tags: [zmx, tmux, session-persistence, zig, fetchurl]

# Dependency graph
requires:
  - phase: 05-user-environment
    provides: "home-manager config with tmux module"
  - phase: 06-user-services
    provides: "agent-compute module with agent-spawn script"
provides:
  - "zmx binary package via fetchurl (packages/zmx.nix)"
  - "zmx-based agent-spawn script"
  - "tmux fully removed from NixOS config"
affects: [agent-tooling, deployment]

# Tech tracking
tech-stack:
  added: [zmx-0.3.0]
  removed: [tmux]
  patterns: [fetchurl-static-binary]

key-files:
  created:
    - packages/zmx.nix
  modified:
    - modules/base.nix
    - modules/agent-compute.nix
    - home/default.nix
  deleted:
    - home/tmux.nix

key-decisions:
  - "Use fetchurl of pre-built static binary instead of zmx flake input (zig2nix bwrap incompatible with apparmor)"
  - "zmx v0.3.0 binary is statically linked -- no autoPatchelfHook needed"

patterns-established:
  - "fetchurl-static-binary: For Zig projects whose flake builds use bwrap, fetch pre-built static binaries directly"

# Metrics
duration: 16min
completed: 2026-02-16
---

# Quick 001: Replace tmux with zmx Summary

**zmx v0.3.0 static binary replaces tmux for session persistence -- fetchurl package, updated agent-spawn script, home-manager tmux config removed**

## Performance

- **Duration:** 16 min
- **Started:** 2026-02-16T17:54:06Z
- **Completed:** 2026-02-16T18:10:06Z
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments
- Replaced tmux with zmx in systemPackages (modules/base.nix)
- Updated agent-spawn script to use `zmx run` / `zmx attach` commands
- Removed home-manager tmux configuration entirely (zero-config zmx needs none)
- Created packages/zmx.nix with fetchurl of pre-built v0.3.0 static binary

## Task Commits

Each task was committed atomically:

1. **Task 1: Add zmx flake input and integrate into modules** - `44d5e21` (feat)
2. **Task 2: Update agent-spawn script to use zmx** - `67db1f0` (feat)
3. **Task 1+2 fix: Switch from flake input to fetchurl binary** - `c8bcb19` (fix)
4. **Task 3: Remove tmux home-manager configuration** - `5d72bea` (chore)

## Files Created/Modified
- `packages/zmx.nix` - zmx v0.3.0 pre-built static binary package via fetchurl
- `modules/base.nix` - Replaced tmux with zmx in systemPackages via callPackage
- `modules/agent-compute.nix` - agent-spawn uses zmx run/attach, zmx in runtimeInputs
- `home/default.nix` - Removed ./tmux.nix import
- `home/tmux.nix` - Deleted (zmx is zero-config)
- `flake.lock` - Removed zmx flake input entries

## Decisions Made
- **fetchurl over flake input:** The zmx flake uses zig2nix which internally runs bwrap (bubblewrap). On this machine, apparmor restricts unprivileged user namespaces (`apparmor_restrict_unprivileged_userns = 1`), causing the zig build to fail with "bwrap: setting up uid map: Permission denied". Since zmx publishes pre-built static binaries at zmx.sh, we use fetchurl instead. The binary is fully statically linked, so no autoPatchelfHook is needed.
- **pkgs.callPackage pattern:** Both base.nix and agent-compute.nix use `pkgs.callPackage ../packages/zmx.nix {}` rather than a flake input, keeping the dependency local and simple.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] zig2nix bwrap fails under apparmor -- switched to fetchurl binary**
- **Found during:** Task 1 (nix flake check after adding zmx flake input)
- **Issue:** zmx flake's zig2nix build system uses bubblewrap (bwrap) internally, which requires unprivileged user namespaces. This machine has `apparmor_restrict_unprivileged_userns = 1`, causing "bwrap: setting up uid map: Permission denied" even with `--option sandbox false`.
- **Fix:** Created `packages/zmx.nix` using fetchurl of the pre-built v0.3.0 static binary from `https://zmx.sh/a/zmx-0.3.0-linux-x86_64.tar.gz`. Reverted zmx flake input from flake.nix. Changed modules to use `pkgs.callPackage` instead of `inputs.zmx.packages`.
- **Files modified:** packages/zmx.nix (created), flake.nix, flake.lock, modules/base.nix, modules/agent-compute.nix
- **Verification:** `nix flake check` passes with all checks
- **Committed in:** `c8bcb19`

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Essential fix -- the planned flake input approach cannot work on machines with apparmor user namespace restrictions. The fetchurl approach is equally correct and simpler (no extra flake input).

## Issues Encountered
- The zmx `.tar.gz` URL is actually a raw ELF binary (not a tarball despite the extension). Used `dontUnpack = true` in the derivation.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- zmx is ready for deployment via `nixos-rebuild switch`
- On the target VPS (Contabo), the zmx binary should work without apparmor issues since it's a pre-built static binary
- agent-spawn script is ready for use: `agent-spawn myagent /path/to/project claude`

---
*Quick task: 001-replace-tmux-with-zmx*
*Completed: 2026-02-16*
