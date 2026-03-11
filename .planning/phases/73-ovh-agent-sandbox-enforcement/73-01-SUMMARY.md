---
phase: 73-ovh-agent-sandbox-enforcement
plan: 01
subsystem: infra
tags: [nixos, bubblewrap, sandbox, agent-security]

requires: []
provides:
  - OVH `claude`/`codex` wrappers that sandbox by default via bubblewrap
  - Guarded `--no-sandbox` path requiring `AGENT_ALLOW_NOSANDBOX=1`
  - Eval checks confirming OVH enablement and module bubblewrap reference
affects: [private-neurosys, deployment]

tech-stack:
  added: []
  patterns: [bubblewrap sandbox wrapper, audit logging]

key-files:
  created: [modules/agent-sandbox.nix]
  modified: [hosts/dev/default.nix, tests/eval/config-checks.nix, .test-status, .planning/STATE.md]

key-decisions:
  - "SANDBOX-73-01: Replace bare agent binaries with wrappers (priority 4) on OVH."
  - "SANDBOX-73-02: Record every launch attempt to /data/projects/.agent-audit/agent-launches.log."
  - "SANDBOX-73-03: Inject secret-proxy env only when `secretProxyPort` is set."

duration: 29min
completed: 2026-03-11
---

# Phase 73 Plan 01: OVH Agent Sandbox Wrapper Enforcement Summary

**Implemented OVH-safe wrapper binaries for `claude` and `codex` with sandbox-on-by-default enforcement and validation checks.**

## Performance
- **Duration:** 29min
- **Tasks:** 4
- **Files modified:** 5

## Accomplishments
- Added `modules/agent-sandbox.nix` with `services.agentSandbox.enable` options and wrapper scripts using `bwrap` by default.
- Enforced `AGENT_ALLOW_NOSANDBOX=1` for explicit unsandboxed launches, otherwise fail-fast with exit 1.
- Added audit logging and optional secret-proxy environment injection.
- Imported and enabled module on OVH host (`hosts/dev/default.nix`).
- Added eval checks for OVH enablement and module source bubblewrap reference.
- Ran `nix flake check` successfully and updated `.test-status`.

## Task Commits
1. **Task A: Create modules/agent-sandbox.nix** - `0e6b039` (feat)
2. **Task B: Enable module on OVH host** - `416ba8a` (feat)
3. **Task C: Add eval checks** - `76c96ab` (test)
4. **Task D: Validate flake checks** - `ea82e91` (chore)

## Files Created/Modified
- `modules/agent-sandbox.nix` - New NixOS module with wrapper generators and options.
- `hosts/dev/default.nix` - Imported module and enabled `services.agentSandbox.enable`.
- `tests/eval/config-checks.nix` - Added `agent-sandbox-ovh-enabled` and `agent-sandbox-module-has-bwrap` checks.
- `.test-status` - Updated to `pass|0|<timestamp>` after successful flake check.
- `.planning/STATE.md` - Updated current phase/plan status and recorded 73-01 decisions.

## Decisions Made
- Use wrapper priority override (`meta.priority = 4`) to shadow bare binaries without removing upstream packages.
- Keep proxy env injection conditional on module option (`secretProxyPort != null`) to preserve public repo evaluation.
- Keep sandbox bind list mostly static in Nix and append runtime `$PWD` bind dynamically in shell for correctness.

## Deviations from Plan
None.

## Issues Encountered
- `node /home/ubuntu/.claude/get-shit-done/bin/gsd-tools.js state advance-plan` returned: `Cannot parse Current Plan or Total Plans in Phase from STATE.md`; state was updated manually.

## Next Phase Readiness
Plan 73-02 can build on this baseline to tighten shell-level interception and any remaining OVH agent sandbox policy work.

---
*Phase: 73-ovh-agent-sandbox-enforcement*
*Completed: 2026-03-11*
