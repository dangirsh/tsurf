---
name: deploy
description: Deploy neurosys NixOS config to neurosys server
user_invocable: true
---

# Deploy Skill

Deploy the neurosys NixOS configuration to the Contabo VPS (neurosys) via deploy-rs.

## How to Deploy

When the user asks to deploy (or invokes `/deploy`), follow these steps:

1. **Detect repo and resolve script path**:
   - From **neurosys**: `./scripts/deploy.sh`
   - From **parts**: `../neurosys/scripts/deploy.sh`
   - Verify the script exists before proceeding.

2. **Execute the deploy script**:
   ```bash
   # Default: remote build on neurosys (fastest — 18 vCPU EPYC builds faster than local)
   ./scripts/deploy.sh

   # Pull latest parts first:
   ./scripts/deploy.sh --update-parts

   # Local build fallback (if server unreachable or testing local changes):
   ./scripts/deploy.sh --mode local
   ```

3. **Monitor output**:
   - The script shows progress: nix build (on server), nixos-rebuild switch, service health check.
   - Watch for errors at each phase.

4. **Verify deployment**:
   - The script polls services for up to 30 seconds.
   - All services (`parts-tools`, `parts-agent`, `postgresql`, `claw-swap-app`) should show "active".
   - On success, it prints the Parts git revision deployed and duration.

5. **Commit flake.lock if updated**:
   - Only applies when run with `--update-parts`. The script reminds you to commit `flake.lock`.

## Flags

| Flag | Description |
|------|-------------|
| `--update-parts` | Pull latest `parts` flake input before building |
| `--skip-update` | No-op (parts update is skipped by default) |
| `--mode remote` | (default) Build on target host via deploy-rs `--remote-build` |
| `--mode local` | Build locally, push closure + switch remotely |
| `--target USER@HOST` | Override SSH target (default: `root@neurosys`) |
| `--first-deploy` | Disable magic rollback for one-time migration |
| `--no-magic-rollback` | Disable magic rollback for this deploy |

## What It Does

1. **Nix build** — Builds the full NixOS system closure (remote by default, local if `--mode local`)
2. **nixos-rebuild switch** — Atomically switches the server to the new config
3. **Service health poll** — Checks systemd services are running (30s timeout)
4. **Flake update** (only with `--update-parts`) — Pulls latest Parts commit into `flake.lock`

## Troubleshooting

- **Rollback**: `ssh root@neurosys nixos-rebuild switch --rollback`
- **Service logs**: `ssh root@neurosys journalctl -u parts-tools -n 50`
- **Lock stuck**: If a previous deploy crashed, remove the remote lock:
  ```bash
  ssh root@neurosys rm -rf /var/lock/neurosys-neurosys-deploy.lock
  rm -f tmp/neurosys-neurosys-deploy.local.lock
  ```
- **Build failures**: Check Nix build output for derivation errors. Common cause: Parts tests failing in the Nix build.
