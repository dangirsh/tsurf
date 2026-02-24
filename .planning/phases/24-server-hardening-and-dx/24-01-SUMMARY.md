---
phase: 24-server-hardening-and-dx
plan: 01
subsystem: server-hardening-and-developer-experience
tags: [srvos, hardening, bubblewrap, treefmt-nix, devshell, nixos]

requires:
  - phase: 11-agent-sandboxing-default-on-bubblewrap-srt-isolation-for-all-coding-agents
    provides: baseline bubblewrap sandbox and agent-spawn workflow
  - phase: 25-deploy-safety-with-deploy-rs
    provides: deploy-rs flake wiring used in devShell
provides:
  - srvos server profile import with explicit neurosys overrides
  - PID and cgroup namespace isolation in agent-spawn bubblewrap policy
  - treefmt-nix formatter integration and operator-focused devShell tooling
affects: [nixos-host-hardening, agent-sandbox-isolation, developer-experience]

tech-stack:
  added: [srvos, treefmt-nix]
  patterns: [mkDefault override layering, namespace isolation hardening, flake formatter/devShell outputs]

key-files:
  created:
    - treefmt.nix
    - .planning/phases/24-server-hardening-and-dx/24-01-SUMMARY.md
  modified:
    - flake.nix
    - flake.lock
    - hosts/neurosys/default.nix
    - modules/agent-compute.nix
    - .planning/STATE.md

key-decisions:
  - "Import `srvos.nixosModules.server` first so srvos `mkDefault` values stay lowest-priority under existing explicit neurosys config."
  - "Force scripted networking and initrd systemd off with `lib.mkForce false`; keep docs and command-not-found enabled for interactive operations."
  - "Enable treefmt formatter output and devShell tooling now, but defer formatting enforcement in flake checks due large unrelated repo-wide churn."

duration: 16min
completed: 2026-02-23
---

# Phase 24 Plan 01: Server Hardening + DX Summary

**srvos hardening baseline + treefmt-nix formatter/devShell tooling + PID/cgroup namespace isolation for agent sandbox visibility hardening.**

## Performance

- **Duration:** 16min
- **Started:** 2026-02-23T14:12:00+01:00
- **Completed:** 2026-02-23T14:28:00+01:00
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments
- Added `srvos` flake input and imported `srvos.nixosModules.server` as the first NixOS module so hardening defaults apply while explicit neurosys settings still win.
- Added neurosys srvos overrides in `hosts/neurosys/default.nix`: forced `networking.useNetworkd = false`, enabled `srvos.server.docs.enable`, enabled `programs.command-not-found.enable`, and force-disabled `boot.initrd.systemd.enable`.
- Added `treefmt-nix` input and `treefmt.nix` (nixfmt + shellcheck), plus flake `formatter` output and `devShells.x86_64-linux.default` with `sops`, `age`, `deploy-rs`, `nixfmt`, and `shellcheck`.
- Added `--unshare-pid` and `--unshare-cgroup` to `agent-spawn` bubblewrap args and updated `--show-policy` output to document namespace isolation.
- Validated repeatedly with `nix flake check` (passing) and `nix develop --command which sops` (store path returned).

## Task Commits

1. **Task 1: Import srvos server profile + host overrides** - `fddade6` (feat)
2. **Task 2: Add treefmt-nix formatter + devShell tooling** - `dc7b3f1` (feat)
3. **Task 3: Add PID/cgroup namespace isolation to agent-spawn** - `a39bc87` (feat)

## Files Created/Modified
- `flake.nix` - srvos + treefmt-nix inputs, srvos module ordering, shared system/pkgs bindings, formatter output, devShell output.
- `flake.lock` - added srvos and treefmt-nix lock entries.
- `hosts/neurosys/default.nix` - srvos-specific host overrides and initrd guard.
- `treefmt.nix` - treefmt-nix module enabling nixfmt and shellcheck.
- `modules/agent-compute.nix` - added `--unshare-pid`, `--unshare-cgroup`, and policy text update.

## Decisions Made
- Prioritized upstream-maintained srvos defaults over hand-maintained hardening duplication while preserving explicit host behavior.
- Enforced namespace isolation where leakage mattered (process and cgroup visibility) without changing network/docker behavior.
- Kept formatter integration active via `nix fmt` while deferring mandatory formatting checks in `nix flake check` for this phase.

## Deviations from Plan
- Formatting check enforcement in `checks` was removed after validation showed repo-wide formatter churn (28 files rewritten) and existing shellcheck findings in `scripts/deploy.sh`; fallback path from plan applied (formatter retained, check not enforced).
- Planned verification command `nix fmt -- --check .` is not supported by current treefmt CLI (`unknown flag: --check`); equivalent treefmt check mode is `--ci`/`--fail-on-change`.

## Issues Encountered
- None blocking. Existing evaluation warnings (home-manager option rename notices, `runCommandNoCC` rename) remained non-fatal and pre-existing.

## Next Phase Readiness
- Host hardening baseline is centralized through srvos with local overrides explicit and documented.
- Agent sandbox now hides host process/cgroup state by default.
- Repo has a standardized formatter output and dev shell for operators/agents.
- Deferred follow-up remains explicit: optional strict formatting enforcement once broad repo formatting/shellcheck cleanup is scheduled.
