---
phase: 52
plan: 52-01
subsystem: openclaw-package-and-service-runtime
tags:
  - nixos
  - openclaw
  - systemd
  - sops-nix
  - docker-migration
requires:
  - modules/docker.nix
  - modules/networking.nix
  - modules/secrets.nix
provides:
  - packages.x86_64-linux.openclaw
  - modules/openclaw.nix native systemd service model
  - eval check coverage for native openclaw services
affects:
  - packages/openclaw.nix
  - packages/openclaw-package-lock.json
  - modules/openclaw.nix
  - hosts/neurosys/default.nix
  - tests/eval/config-checks.nix
  - flake.nix
  - .claude/.test-status
tech-stack:
  - Nix flakes
  - NixOS modules
  - systemd
  - Node.js 22
  - npm tarball packaging
key-files:
  - packages/openclaw.nix
  - modules/openclaw.nix
  - tests/eval/config-checks.nix
  - flake.nix
key-decisions:
  - OCL-PKG-01
  - OCL-PKG-02
  - OCL-01
  - OCL-03
  - OCL-06
  - OCL-11
  - OCL-12
  - OCL-13
  - OCL-14
duration: "00:06:17"
completed: 2026-03-02
---

# Phase 52 Plan 01: Package OpenClaw + Rewrite Public Module Summary

OpenClaw is now packaged from npm tarball and neurosys runs 6 native systemd instances with per-instance users instead of Docker OCI containers.

## Task Commits

- `985590c` `feat(52-01): package openclaw from npm tarball`
- `d346bcf` `feat(52-01): nativize openclaw system services`
- `c540f3d` `test(52-01): assert native openclaw services in eval checks`
- `350cada` `feat(52-01): export openclaw package in flake outputs`
- `6a663f4` `fix(52-01): align openclaw service ordering with sops units`

## Files Created/Modified

- Created [packages/openclaw.nix](/data/projects/neurosys/.claude/worktrees/phase-52/packages/openclaw.nix)
- Created [packages/openclaw-package-lock.json](/data/projects/neurosys/.claude/worktrees/phase-52/packages/openclaw-package-lock.json)
- Rewrote [modules/openclaw.nix](/data/projects/neurosys/.claude/worktrees/phase-52/modules/openclaw.nix)
- Updated [hosts/neurosys/default.nix](/data/projects/neurosys/.claude/worktrees/phase-52/hosts/neurosys/default.nix)
- Updated [tests/eval/config-checks.nix](/data/projects/neurosys/.claude/worktrees/phase-52/tests/eval/config-checks.nix)
- Updated [flake.nix](/data/projects/neurosys/.claude/worktrees/phase-52/flake.nix)
- Updated [.claude/.test-status](/data/projects/neurosys/.claude/worktrees/phase-52/.claude/.test-status)

## Key Decisions Applied

- Packaged OpenClaw from npm registry tarball with pinned source hash and npm deps hash.
- Replaced Docker container model with six native services (`openclaw-mark` through `openclaw-tal-claw`).
- Added per-instance system users and shifted sops template ownership to those users.
- Migrated Docker-era state layout by chowning `/var/lib/openclaw-*` and creating `.openclaw -> .` compatibility symlinks.
- Restricted `trustedProxies` to `127.0.0.1` after removing Docker bridge dependency.
- Kept Docker module intact for non-OpenClaw workloads (Spacebot path remains valid).

## Deviations

- Planned npm version `2026.2.27` was not published on npm (404). Used latest published `openclaw@2026.3.1` from the official registry tarball.

## Verification

- `nix build .#openclaw` passes.
- Native service eval checks pass, including `openclaw-services-neurosys`.
- `nix flake check` passes for public repo outputs/configurations.
- `.claude/.test-status` written as `pass|0|<unix_timestamp>`.
