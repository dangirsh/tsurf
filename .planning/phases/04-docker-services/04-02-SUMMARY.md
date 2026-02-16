---
phase: 04-docker-services
plan: 02
subsystem: claw-swap
tags: [nixos-module, containers, hardening, sops-nix, caddy, postgres, flake-integration]

requires:
  - phase: 04-docker-services
    plan: 01
    provides: claw-swap flake (nixosModules.default + packages) + sops secrets + Docker image
provides:
  - Complete NixOS module with 3 hardened containers, 1 Docker network, 5 secrets, 2 env templates
  - agent-neurosys flake integration importing claw-swap alongside parts
affects: [phase-04-docker-services, agent-neurosys-flake]

tech-stack:
  added: [caddy, postgres-alpine]
  patterns: [dockerTools-pullImage, container-hardening, caddyfile-via-writeText]

key-files:
  created: []
  modified:
    - /data/projects/claw-swap/nix/module.nix
    - /data/projects/agent-neurosys/flake.nix
    - /data/projects/agent-neurosys/flake.lock
  bugfix:
    - /data/projects/parts/flake.nix
    - /data/projects/parts/nix/module.nix

key-decisions:
  - "Follow parts module pattern exactly: curried args, per-secret sopsFile, no sops-nix import, no system-level config"
  - "Harden all containers: --read-only, --cap-drop=ALL, --security-opt=no-new-privileges, resource limits"
  - "PostgreSQL needs 5 cap-adds (CHOWN/SETUID/SETGID/FOWNER/DAC_OVERRIDE) + tmpfs for /tmp and /run/postgresql + --shm-size=128m"
  - "Caddy needs NET_BIND_SERVICE for ports 80/443, persistent volumes for TLS certs"
  - "Use dockerTools.pullImage with digest pinning for postgres:16-alpine and caddy:2-alpine"
  - "Caddyfile declared via pkgs.writeText, domain config lives with the app"
  - "Docker network claw-swap-net (172.22.0.0/24) as systemd oneshot, all containers require it"

duration: ~35min
completed: 2026-02-16
---

# Phase 4 Plan 02: Claw-Swap NixOS Module + Agent-Neurosys Integration

**Shipped the complete claw-swap NixOS module (3 hardened containers, network, secrets) and integrated it into agent-neurosys as a flake input. `nix flake check` validates the full combined stack.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-02-16
- **Tasks:** 2 (plus parts bugfix for clawvault/qmd args)
- **Repos touched:** /data/projects/claw-swap, /data/projects/agent-neurosys, /data/projects/parts (bugfix)

## Accomplishments

- Replaced placeholder `nix/module.nix` with 220-line NixOS module declaring:
  - 5 sops.secrets with per-secret sopsFile overrides and restartUnits
  - 2 sops.templates (db-env, app-env) for container env file injection
  - dockerTools.pullImage for postgres:16-alpine and caddy:2-alpine with real digest + sha256
  - Caddyfile via pkgs.writeText (reverse proxy to app:3000)
  - Docker network claw-swap-net (172.22.0.0/24) as systemd oneshot
  - 3 hardened containers (db, app, caddy) with --read-only, --cap-drop=ALL, --no-new-privileges, resource limits
  - Systemd ordering (after + requires) for all containers on network service
  - tmpfiles.rules for 4 host directories
- Added claw-swap as flake input in agent-neurosys with nixpkgs + sops-nix follows
- Fixed parts module bug (missing clawvault/qmd args in callPackage calls)
- `nix flake check` passes for both claw-swap and agent-neurosys

## Task Commits

**claw-swap repo:**
1. **Task 1: NixOS module with hardened containers** — `9845861`

**agent-neurosys repo:**
2. **Task 2: Flake integration** — `4433ebf`

**parts repo (bugfix):**
3. **Module callPackage fix** — `b580dcc`

## Files Modified

- `/data/projects/claw-swap/nix/module.nix` — Complete NixOS module (220 lines)
- `/data/projects/agent-neurosys/flake.nix` — Added claw-swap input + module import
- `/data/projects/agent-neurosys/flake.lock` — Updated with claw-swap + parts inputs
- `/data/projects/parts/flake.nix` — Pass clawvault/qmd to module (bugfix)
- `/data/projects/parts/nix/module.nix` — Accept and forward clawvault/qmd (bugfix)

## Deviations From Plan

- **Parts module bugfix required:** The parts module's callPackage calls were missing clawvault and qmd arguments added in recent parts repo changes. Fixed in a separate commit before proceeding.
- **Root-owned Docker data cleanup:** `/data/projects/claw-swap/deploy/caddy-{config,data}/caddy/` directories were root-owned Docker artifacts that blocked Nix's path: fetcher. Removed manually.

## Issues Encountered

- Codex CLI hit token limit while waiting for `nix flake lock --update-input claw-swap` — Task 2 (flake integration) completed manually.
- NAR hash mismatch for parts input required updating both parts and claw-swap inputs.
- Shell CWD got stuck on deleted worktree path — recovered by recreating the directory temporarily.

## Verification

All plan verification criteria met:
- `nix flake check` passes for claw-swap (module + containers valid)
- `nix flake check` passes for agent-neurosys (full system with parts + claw-swap)
- All 3 containers have security hardening (read-only, cap-drop ALL, no-new-privileges, memory, cpus)
- Docker network has systemd ordering for all containers
- All secrets use sops.templates (no plaintext)
- Resource limits match: app 512MB/1CPU, db 512MB/1CPU/128MB shm, caddy 256MB/0.5CPU

---
*Phase: 04-docker-services*
*Completed: 2026-02-16*
