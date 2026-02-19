---
phase: 17-hardcore-simplicity-security-audit
plan: 01
subsystem: infra
tags: [nix, security, hardening]
duration: 31min
completed: 2026-02-19
---

# Phase 17 Plan 01: Simplicity Cleanup + Foundational Hardening Summary

**Removed dead/duplicate configuration, tightened kernel defaults, and aligned llm-agents supply chain with the root nixpkgs.**

## Accomplishments
- Removed duplicate `zmx` declaration from `modules/base.nix` and kept `zmx` in `modules/agent-compute.nix` system packages.
- Removed unused features/packages: `programs.git.lfs.enable` and `pkgs.podman-compose`.
- Removed stale `parts-agent@vm` SSH keys from both `dangirsh` and `root` authorized keys.
- Added kernel sysctl hardening for dmesg/kptr/bpf/redirect handling and martian packet logging.
- Switched deploy script local lock path to project-local `tmp/` and ensured directory creation.
- Consolidated homepage Tailscale IP into one `let` binding.
- Set `llm-agents.inputs.nixpkgs.follows = "nixpkgs"`, updated lock input, and validated compatibility.
- Ran `nix flake check` after each change group and at final completion; all checks passed.

## Task Commits
1. **Task 1: Module-level simplicity cleanup** - `b4d846f`
2. **Task 2: Non-module cleanup + hardening + supply chain** - `6703fed`

## Files Created/Modified
- `modules/base.nix` - Removed base-level `zmx`; added SEC-17-01 sysctl hardening block.
- `modules/agent-compute.nix` - Added `zmx` to system packages; removed `podman-compose`.
- `modules/users.nix` - Removed stale `parts-agent@vm` SSH keys.
- `home/git.nix` - Removed `lfs.enable`.
- `modules/homepage.nix` - Added `tailscaleIP` let binding and replaced hardcoded usage sites.
- `scripts/deploy.sh` - Moved lock path to `$FLAKE_DIR/tmp/...` and added `mkdir -p "$FLAKE_DIR/tmp"`.
- `flake.nix` - Added `llm-agents` nixpkgs follow.
- `flake.lock` - Refreshed `llm-agents` (and nested blueprint) after follows update.
- `.planning/STATE.md` - Updated current position and recorded 17-01 decisions.
- `.planning/phases/17-hardcore-simplicity-security-audit/17-01-SUMMARY.md` - Added execution summary.

## Decisions Made
- Keep `zmx` system-available from `agent-compute` rather than `base` to remove duplication without changing user workflows.
- Retain `llm-agents` nixpkgs follow because `nix flake check` passed after lock update; no compatibility rollback needed.

## Deviations from Plan
None - plan executed exactly as specified.

## Issues Encountered
None

## Next Phase Readiness
Phase 17 Plan 01 outputs are complete and validated; repository is ready to proceed to Plan 17-02.

## Self-Check: PASSED
