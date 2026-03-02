---
phase: 52
plan: 52-02
subsystem: private-overlay-openclaw-native-integration
tags:
  - nixos
  - private-overlay
  - openclaw
  - homepage
  - syncthing
  - eval-checks
requires:
  - 52-01
  - private-neurosys/modules/openclaw-auto-approve.nix
  - private-neurosys/modules/homepage.nix
  - private-neurosys/tests/eval/private-checks.nix
provides:
  - direct openclaw CLI auto-approval for jordan-claw and tal-claw
  - homepage OpenClaw widgets using siteMonitor-only health
  - private eval assertions for native openclaw systemd services and users
  - syncthing GUI host-check hardening aligned with SEC47-21
affects:
  - private-neurosys/flake.lock
  - private-neurosys/modules/openclaw-auto-approve.nix
  - private-neurosys/modules/homepage.nix
  - private-neurosys/modules/syncthing.nix
  - private-neurosys/tests/eval/private-checks.nix
  - private-neurosys/.claude/.test-status
tech-stack:
  - Nix flakes
  - NixOS modules
  - systemd
  - homepage-dashboard
  - sops-nix
key-files:
  - /data/projects/private-neurosys/.claude/worktrees/phase-52-02/modules/openclaw-auto-approve.nix
  - /data/projects/private-neurosys/.claude/worktrees/phase-52-02/modules/homepage.nix
  - /data/projects/private-neurosys/.claude/worktrees/phase-52-02/modules/syncthing.nix
  - /data/projects/private-neurosys/.claude/worktrees/phase-52-02/tests/eval/private-checks.nix
key-decisions:
  - HP-02
  - SEC47-21
  - TEST-50-01
duration: "00:07:31"
completed: 2026-03-02
---

# Phase 52 Plan 02: Update Private Overlay + Tests for Native OpenClaw Summary

Private overlay now consumes native OpenClaw services end-to-end: auto-approve uses direct CLI, homepage OpenClaw widgets dropped Docker container status, and private eval checks validate native `openclaw-*` services/users while preserving Spacebot Docker checks.

## Task Commits

- `76f051a` `chore(52-02): update neurosys input for native openclaw`
- `e71dbd3` `feat(52-02): switch openclaw auto-approve to native CLI`
- `5186af3` `refactor(52-02): monitor openclaw widgets via site checks only`
- `8a0ff00` `fix(52-02): re-enable syncthing GUI host check`
- `b59a19b` `test(52-02): assert native openclaw services in private eval`
- `a9191c9` `chore(52-02): record flake check pass status`

## Files Created/Modified

- Updated [/data/projects/private-neurosys/.claude/worktrees/phase-52-02/flake.lock](/data/projects/private-neurosys/.claude/worktrees/phase-52-02/flake.lock)
- Updated [/data/projects/private-neurosys/.claude/worktrees/phase-52-02/modules/openclaw-auto-approve.nix](/data/projects/private-neurosys/.claude/worktrees/phase-52-02/modules/openclaw-auto-approve.nix)
- Updated [/data/projects/private-neurosys/.claude/worktrees/phase-52-02/modules/homepage.nix](/data/projects/private-neurosys/.claude/worktrees/phase-52-02/modules/homepage.nix)
- Updated [/data/projects/private-neurosys/.claude/worktrees/phase-52-02/modules/syncthing.nix](/data/projects/private-neurosys/.claude/worktrees/phase-52-02/modules/syncthing.nix)
- Updated [/data/projects/private-neurosys/.claude/worktrees/phase-52-02/tests/eval/private-checks.nix](/data/projects/private-neurosys/.claude/worktrees/phase-52-02/tests/eval/private-checks.nix)
- Updated [/data/projects/private-neurosys/.claude/worktrees/phase-52-02/.claude/.test-status](/data/projects/private-neurosys/.claude/worktrees/phase-52-02/.claude/.test-status)

## Key Decisions Applied

- `openclaw-auto-approve` now packages and calls `${openclaw-pkg}/bin/openclaw` directly through `inputs.neurosys`, with per-instance websocket URLs (`:18793`, `:18794`) instead of Docker-internal `:18789`.
- OpenClaw homepage entries are health-monitored via `siteMonitor` only; Docker socket access and `SupplementaryGroups = [ "docker" ]` are retained specifically for Spacebot container status.
- Syncthing GUI `insecureSkipHostcheck` is set to `false` and documented with `SEC47-21` now that Docker bridge access is no longer part of OpenClaw.
- Private eval checks now assert native OpenClaw `systemd.services` and per-instance users; Spacebot container assertion remains unchanged.

## Deviations

- None.

## Verification

- `nix flake check` passed for private overlay outputs (`nixosConfigurations.neurosys` and `nixosConfigurations.ovh`).
- New checks `openclaw-native-services` and `openclaw-users` evaluated successfully.
- `.claude/.test-status` written as `pass|0|<unix_timestamp>`.
