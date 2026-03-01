---
phase: 40-agentd-integration-supervised-agent-lifecycle
plan: 02
subsystem: infra
tags: [agentd, nixos, agent-spawn, homepage]
requires:
  - phase: 40-01
    provides: agentd module foundation
provides:
  - Full agent fleet declared across both hosts
  - agent-spawn removed (hard cutover)
  - Homepage Agents section with agentd API widgets
affects: [deploy, phase-41]
tech-stack:
  removed: [agent-spawn]
  patterns: [agentd fleet declaration in private overlay, homepage customapi widgets]
key-files:
  modified: [modules/networking.nix, modules/agent-compute.nix, modules/agentd.nix]
  private-modified: [flake.nix, modules/agent-compute.nix, modules/homepage.nix]
key-decisions:
  - "All agent declarations in private overlay (contaboModules/ovhModules) — public repo stays declaration-free"
  - "claw-swap-dev uses custom sops template for secret proxy env (ANTHROPIC_BASE_URL=http://127.0.0.1:9091)"
  - "Homepage Agents section extended with agentd customapi widgets for all 4 agents"
  - "OVH ovh-dev queried cross-host via Tailscale MagicDNS (neurosys-prod:9204)"
duration: 9min
completed: 2026-03-01
---

# Phase 40 Plan 02: Agent Fleet Declaration + agent-spawn Removal

**Hard cutover complete: agentd is now the sole agent lifecycle manager.**

## Performance
- **Duration:** 9 min
- **Tasks:** 7
- **Files modified (public):** 3
- **Files modified (private overlay):** 3

## Accomplishments
- Declared full agent fleet: neurosys-dev, conway-automaton, claw-swap-dev (Contabo) + ovh-dev (OVH)
- Removed agent-spawn from both public and private agent-compute.nix
- Added agentd overlay to private overlay flake.nix
- Updated homepage dashboard with agentd customapi widgets for all 4 agents
- Port 9204 reserved for OVH agentd proxy
- Cleared all remaining `agent-spawn` mentions from `.nix` files in both feature worktrees

## Task Commits
- Task 1 (public): `4ebd6a3` — feat(40-02): add ovh-only agentd proxy port 9204
- Task 2 (public): `ebb975c` — feat(40-02): remove agent-spawn from public agent compute
- Task 3 (private): `14c8746` — feat(40-02): declare agentd fleet in private flake
- Task 4 (private): `1121d53` — feat(40-02): remove agent-spawn from private agent compute
- Task 5 (private): `932c32b` — feat(40-02): add agentd widgets to homepage agents
- Task 6 hard-cutover cleanup (public): `2f1fd5c` — fix(40-02): remove residual agent-spawn references
- Task 7 (public summary): `71e18aa` — feat(40-02): add plan 02 execution summary

## Deviations from Plan
- Public repo completeness grep was executed against the public feature worktree path (instead of `/data/projects/neurosys` with `tmp/` excluded) to avoid false positives from untouched `main` while following the required worktree-only workflow.

## Issues Encountered
- Private overlay `nix flake check` currently fails before build with `attribute 'toTOML' missing` in `inputs.neurosys/modules/agentd.nix` (resolved from GitHub input revision), so full private validation is deferred until public input revision is updated/consumed.

## Next Phase Readiness
Phase 40 complete. Ready for deploy (Phase 46 or manual nixos-rebuild).
