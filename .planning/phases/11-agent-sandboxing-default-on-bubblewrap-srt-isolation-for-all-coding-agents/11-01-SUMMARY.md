---
phase: 11-agent-sandboxing-default-on-bubblewrap-srt-isolation-for-all-coding-agents
plan: 11-01
subsystem: infra
tags: [bubblewrap, podman, nftables, sops-nix, systemd-run, sandbox]
requires:
  - phase: 10-parts-consolidation-migrate-parts-from-standalone-vps-to-acfs-via-agent-neurosys
    provides: deployable NixOS baseline with agent tooling modules
provides:
  - Default-on bubblewrap isolation for `agent-spawn` sessions
  - Rootless Podman runtime configuration with dockerCompat for sandbox workflows
  - Outbound metadata endpoint block at 169.254.169.254
  - Subordinate UID/GID ranges for rootless container user namespaces
affects:
  - 11-02 runtime validation and sandbox policy hardening
  - agent security posture for prompt-injected workflows
tech-stack:
  added: [bubblewrap runtime integration, virtualisation.podman, nftables output filtering]
  patterns: [default-on sandbox with explicit opt-out flag, pre-sandbox secret-to-env injection]
key-files:
  created: [.planning/phases/11-agent-sandboxing-default-on-bubblewrap-srt-isolation-for-all-coding-agents/11-01-SUMMARY.md]
  modified: [modules/agent-compute.nix, modules/networking.nix, modules/users.nix, .planning/STATE.md]
key-decisions:
  - "Kept sandbox default-on with `--no-sandbox` explicit bypass."
  - "Used `dockerCompat = true` for Podman per locked Phase 11 context decision."
  - "Blocked metadata IP via nftables output chain rather than per-tool network stubbing."
patterns-established:
  - "Agent sandbox policy is introspectable via `agent-spawn --show-policy`."
  - "Sandbox mount strategy is ordered broad read-only first, then project-specific read-write override."
duration: 20min
completed: 2026-02-17
---

# Phase 11: Agent Sandboxing Plan 11-01 Summary

**Bubblewrap-wrapped `agent-spawn` now defaults every agent session into a least-privilege filesystem sandbox with rootless Podman support and metadata endpoint egress blocking.**

## Performance

- **Duration:** 20 min
- **Started:** 2026-02-17T20:38:00Z
- **Completed:** 2026-02-17T20:58:00Z
- **Tasks:** 1
- **Files modified:** 5

## Accomplishments

- Replaced `agent-spawn` with a bubblewrap launcher that supports `<name> <project-dir> [claude|codex]`, `--no-sandbox`, and `--show-policy`.
- Enforced sandbox mounts and env policy: `/data/projects` read-only with project override read-write, `/run/secrets` and `~/.ssh` unmounted, API keys injected from sops before sandbox entry.
- Enabled rootless Podman (`dockerCompat = true`) and added subordinate UID/GID ranges for `dangirsh`.
- Added nftables output rule dropping traffic to `169.254.169.254`.
- Added `TasksMax=4096` to `agent.slice` and in `systemd-run` launch parameters.

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite agent-spawn with bubblewrap + Podman + metadata block** - `32c9b9b` (feat)

**Plan metadata:** pending in follow-up docs commit

## Files Created/Modified

- `.planning/phases/11-agent-sandboxing-default-on-bubblewrap-srt-isolation-for-all-coding-agents/11-01-SUMMARY.md` - Plan execution summary with dependency and decision metadata.
- `modules/agent-compute.nix` - New sandboxed `agent-spawn`, Podman config, and agent slice limits.
- `modules/networking.nix` - nftables table `agent-metadata-block` dropping metadata endpoint egress.
- `modules/users.nix` - `subUidRanges` and `subGidRanges` for rootless Podman.
- `.planning/STATE.md` - Updated current phase/plan position and recorded 11-01 decisions.

## Decisions Made

- Kept default-on sandboxing, with explicit `--no-sandbox` bypass for operational escape hatch.
- Preserved sibling project visibility as read-only by bind-ordering `/data/projects` before project directory bind.
- Injected API keys via env vars at spawn time, while keeping `/run/secrets` itself outside the sandbox.
- Adopted Podman `dockerCompat = true` despite host CLI ambiguity, with explicit fallback noted for Plan 11-02.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Minor documentation lookup mismatch due long Phase 10 directory name; corrected path and continued.

## Next Phase Readiness

- Ready for Plan 11-02 runtime validation on host (`nixos-rebuild switch` + live `agent-spawn` behavior tests).
- No blockers identified in Nix evaluation for this plan.

---

*Phase: 11-agent-sandboxing-default-on-bubblewrap-srt-isolation-for-all-coding-agents*
*Completed: 2026-02-17*
