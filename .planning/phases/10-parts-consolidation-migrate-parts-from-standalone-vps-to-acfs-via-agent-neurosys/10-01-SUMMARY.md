# Plan 10-01 Summary

**Status:** COMPLETE
**Duration:** ~25min
**Commits:** 4 (358254f, 34edca4, 461be87, b10ee70)

## What Was Done

1. **Documented current deployment** (10-CURRENT-DEPLOY.md) — Captured pre-pipeline state: manual trigger, path: inputs, nix copy mechanism, 2 containers + 2 networks + 10 secrets, limitations (single-machine only, no health checks, no rollback guidance).

2. **Switched flake inputs to github:** — Changed `parts` from `path:/data/projects/parts` to `github:dangirsh/personal-agent-runtime` and `claw-swap` from `path:/data/projects/claw-swap` to `github:dangirsh/claw-swap`. Required adding GitHub access token to `~/.config/nix/nix.conf` for private repo access. `nix flake check` passes.

3. **Created deploy script** (scripts/deploy.sh, 151 lines) — Single-command deploy with:
   - `--mode local` (default): build locally, push + switch via `nixos-rebuild --target-host`
   - `--mode remote`: SSH in, pull, rebuild on server
   - `--skip-update`: skip `nix flake update parts`
   - Health verification: polls 5 containers for 30s
   - Success: prints revision, duration, container status, flake.lock commit reminder
   - Failure: prints failed containers, rollback command

4. **Created deployment runbook** (10-RUNBOOK.md) — Operational guide covering prerequisites, all deploy modes, expected output, failure interpretation, rollback, troubleshooting table.

## Decisions

- @decision Manual deploy only (no CI/CD) — NixOS handles incrementality
- @decision Full nixos-rebuild switch every deploy — no partial/container-only path
- @decision Container health polling (30s) — no app-level health checks
- @decision No auto-commit of flake.lock — print reminder instead

## Artifacts

| File | Purpose |
|------|---------|
| `flake.nix` | github: inputs for parts and claw-swap |
| `flake.lock` | Locked to parts rev 1bbd22d |
| `scripts/deploy.sh` | Deploy script with dual modes |
| `10-CURRENT-DEPLOY.md` | Pre-pipeline deployment documentation |
| `10-RUNBOOK.md` | Operational deployment runbook |

## Next

Plan 10-02: Run deploy script end-to-end against acfs server, verify all containers, user sign-off.
