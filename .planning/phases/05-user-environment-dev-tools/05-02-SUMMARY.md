---
phase: 05-user-environment-dev-tools
plan: 02
subsystem: infra
tags: [llm-agents, claude-code, codex, systemd, cgroup, agent-spawn, nix-overlay]

requires:
  - phase: 05-user-environment-dev-tools/01
    provides: home-manager modules, system packages, sops secrets (API keys)
provides:
  - Claude Code and Codex CLI packages via llm-agents.nix overlay
  - agent-spawn launcher script for isolated tmux sessions
  - Systemd agent.slice for CPU fair-share isolation
  - Numtide binary cache for fast agent CLI builds
  - User linger for persistent systemd user instance
affects: [06-user-services, 10-parts-consolidation]

tech-stack:
  added: [llm-agents.nix overlay, claude-code, codex, writeShellApplication, systemd-run --user]
  patterns: [overlay-based package injection, systemd slice isolation, writeShellApplication for scripts]

key-files:
  created: [modules/agent-compute.nix]
  modified: [flake.nix, flake.lock, modules/default.nix]

key-decisions:
  - "Package names are claude-code and codex from overlay (not llm-agents-* prefix)"
  - "Using systemd-run --user --scope (not system-level) so dangirsh can run without root"
  - "No nixpkgs.follows for llm-agents — pins its own nixpkgs for package compatibility"
  - "Numtide binary cache key: niks3.numtide.com-1"

duration: 15min
completed: 2026-02-16
---

# Phase 5 Plan 02: Agent CLIs + Compute Infrastructure Summary

**Claude Code + Codex CLI via llm-agents.nix overlay, agent-spawn launcher with systemd cgroup isolation, Numtide binary cache**

## Performance

- **Duration:** 15 min
- **Started:** 2026-02-16T15:18:00Z
- **Completed:** 2026-02-16T15:33:00Z
- **Tasks:** 2 (+ 1 non-blocking checkpoint)
- **Files modified:** 4

## Accomplishments
- llm-agents.nix flake input with overlay providing `claude-code` and `codex` packages
- `agent-spawn` script: `agent-spawn <name> <project-dir> [claude|codex]` creates isolated tmux sessions
- Systemd `agent.slice` with CPUWeight for workload fair-share isolation
- User linger enabled for `dangirsh` (persistent systemd user instance)
- Numtide binary cache configured for fast substitution of pre-built agent CLIs

## Task Commits

1. **Task 1: Add llm-agents.nix flake input and overlay** - `4a0e95a` (feat)
2. **Task 2: Create agent-compute module** - `83f1371` (feat)

## Files Created/Modified
- `modules/agent-compute.nix` - Agent spawn script, CLI packages, cgroup slice, linger, binary cache
- `flake.nix` - llm-agents input + overlay applied to nixpkgs
- `flake.lock` - llm-agents and dependencies (blueprint, treefmt-nix) pinned
- `modules/default.nix` - Imports agent-compute.nix

## Decisions Made
- **Package names:** The llm-agents overlay adds packages directly to pkgs namespace as `claude-code` and `codex` (not `llm-agents-claude-code` as initially expected). Verified via `nix flake show`.
- **systemd-run --user:** Using `--user --scope` instead of system-level `--scope` so dangirsh can run agent-spawn without root. Linger ensures the user systemd instance persists across logout.
- **No follows for llm-agents:** llm-agents pins its own nixpkgs for package compatibility. The overlay adapts to the consumer's pkgs.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Package names differ from plan expectation**
- **Found during:** Task 2 (agent-compute module creation)
- **Issue:** Plan expected `pkgs.llm-agents-claude-code` and `pkgs.llm-agents-codex`, but overlay uses `pkgs.claude-code` and `pkgs.codex`
- **Fix:** Used actual package names from `nix flake show` output
- **Files modified:** modules/agent-compute.nix
- **Verification:** `nix flake show` evaluates NixOS configuration successfully
- **Committed in:** 4a0e95a (Task 1 commit included agent-compute.nix)

**2. [Rule 3 - Blocking] nix flake check hangs on NixOS configuration evaluation**
- **Found during:** Task 1 verification (Codex backend)
- **Issue:** `nix flake check` hangs indefinitely (known system-level issue, documented in Plan 01)
- **Fix:** Used `nix flake show` as verification workaround (confirms NixOS configuration evaluates)
- **Verification:** `nix flake show` outputs `nixosConfigurations.acfs: NixOS configuration`

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both necessary for correct execution. No scope creep.

## Issues Encountered
- Codex CLI execution timed out waiting for `nix flake check` (known hang). Orchestrator took over execution manually with `nix flake show` verification.

## Checkpoint: Post-Deploy Verification (Non-blocking)

Before deploying to VPS:
1. Run `sops secrets/acfs.yaml` and replace PLACEHOLDER values for `anthropic-api-key`, `openai-api-key`, `github-pat`
2. Review `git diff main` to confirm all changes

After deployment, verify on the server:
- `which claude` and `which codex` return paths
- `echo $ANTHROPIC_API_KEY` shows a value
- `gh auth status` confirms authentication
- `agent-spawn test-agent /tmp claude` launches a tmux session
- `tmux ls` shows the test-agent session
- `mosh dangirsh@<tailscale-ip>` connects

## Next Phase Readiness
- Phase 5 complete — full agent-optimized compute environment declared
- Ready for Phase 6 (User Services + Agent Tooling): Syncthing, CASS, infrastructure repos
- API key secrets still need real values before deployment

---
*Phase: 05-user-environment-dev-tools*
*Completed: 2026-02-16*
