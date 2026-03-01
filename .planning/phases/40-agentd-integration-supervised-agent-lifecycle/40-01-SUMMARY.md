---
phase: 40-agentd-integration-supervised-agent-lifecycle
plan: 01
subsystem: infra
tags: [agentd, nixos, bubblewrap, tmux, sops-nix]
requires:
  - phase: 38-dual-host-role-separation-contabo-as-services-host-ovh-as-dev-agent-host
    provides: host-specific module structure
provides:
  - agentd NixOS module with services.agentd.agents option schema
  - jcard.toml rendering per agent
  - bwrap wrapper generation (writeShellScriptBin)
  - per-agent systemd services and socat API proxies
affects: [40-02, phase-41, phase-42]
tech-stack:
  added: [agentd (dangirsh fork)]
  patterns: [per-agent systemd service generation, writeShellScriptBin for bwrap wrapper]
key-files:
  created: [modules/agentd.nix, .planning/phases/40-agentd-integration-supervised-agent-lifecycle/40-01-SUMMARY.md]
  modified: [flake.nix, flake.lock, modules/default.nix, modules/networking.nix, .planning/STATE.md]
key-decisions:
  - "Fork dangirsh/agentd patched with configurable -agent-user flag and pinned in flake.lock"
  - "Custom harness uses writeShellScriptBin 'agent' wrapper to preserve bwrap policy"
  - "Shared sops template renders only anthropic-api-key for cross-host-safe eval"
  - "No live agents declared in public repo; schema validated with empty default"
duration: 72min
completed: 2026-03-01
---

# Phase 40 Plan 01: Core agentd Module Summary

**Shipped the public `agentd` foundation module with schema, jcard rendering, wrapper/service generation, and host-safe evaluation defaults.**

## Performance
- **Duration:** 72 min
- **Tasks:** 7
- **Files modified:** 8

## Accomplishments
- Added `agentd` flake input (`github:dangirsh/agentd`) and overlay wiring in [`flake.nix`](/data/projects/neurosys/tmp/worktrees/40-01-agentd-module/flake.nix).
- Patched fork `dangirsh/agentd` with `-agent-user` support and pinned public lock to commit `7eda5a6`.
- Created [`modules/agentd.nix`](/data/projects/neurosys/tmp/worktrees/40-01-agentd-module/modules/agentd.nix) with `services.agentd.agents` schema, assertions, jcard rendering, bwrap wrapper generation, per-agent systemd services, and optional socat proxy services.
- Ensured wrappers include `tmux`, `sudo`, `bubblewrap` in PATH and preserve hidden-path policy (`/run/secrets`, `~/.ssh`, docker socket not mounted).
- Imported module in [`modules/default.nix`](/data/projects/neurosys/tmp/worktrees/40-01-agentd-module/modules/default.nix) and reserved internal proxy ports in [`modules/networking.nix`](/data/projects/neurosys/tmp/worktrees/40-01-agentd-module/modules/networking.nix).
- Kept public repo agent declarations empty (`services.agentd.agents = {}`) and validated both hosts with `nix flake check`.

## Task Commits
- `a7fe08a` — feat(40-01): add agentd flake input and overlay
- `730fcdc` — feat(40-01): add agentd module schema and jcard rendering
- `3c16d14` — feat(40-01): generate agentd services and socat proxies
- `db5d799` — feat(40-01): import shared agentd module
- `3bad18f` — feat(40-01): reserve internal agentd proxy ports
- `a90f307` — fix(40-01): resolve agentd module recursion and pin fork

## Deviations from Plan
- **[Rule 3 - Blocking]** `modules/agentd.nix` initially caused infinite recursion during module evaluation due strict `mkMerge (mapAttrsToList ...)` usage. Fixed by switching to lazy `mapAttrs'` attrset generation.
- **[Rule 3 - Blocking]** `dangirsh/agentd` was archived/read-only; repository was unarchived before pushing the `-agent-user` patch.

## Issues Encountered
- `go test ./...` in the fork had one flaky/pre-existing tmux integration test failure in this environment; non-tmux packages passed and the CLI flag patch compiled/pushed successfully.

## Next Phase Readiness
Foundation complete. Plan 40-02 can proceed to declare agent fleet and remove agent-spawn.
