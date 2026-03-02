---
name: deploy
description: Deploy neurosys NixOS config to neurosys server
user_invocable: true
---

# Deploy Skill

Deploy the neurosys NixOS configuration via deploy-rs.

**CRITICAL: ALL deploys MUST run from the private overlay.** The public repo's
`deploy.sh` refuses all deploys because both hosts run the private overlay config.

## How to Deploy

When the user asks to deploy (or invokes `/deploy`), follow these steps:

1. **Always use the private overlay**:
   ```bash
   cd /data/projects/private-neurosys
   ```

2. **If public neurosys was updated**, refresh the input first:
   ```bash
   nix flake lock --update-input neurosys
   ```

3. **Execute the deploy script**:
   ```bash
   # Default: deploy neurosys (Contabo) with remote build
   ./scripts/deploy.sh

   # Deploy OVH:
   ./scripts/deploy.sh --node ovh

   # Pull latest parts first:
   ./scripts/deploy.sh --update-parts

   # Local build fallback (if server unreachable):
   ./scripts/deploy.sh --mode local
   ```

4. **Monitor output**:
   - The script shows progress: nix build (on server), nixos-rebuild switch, service health check.
   - Watch for errors at each phase.

5. **Verify deployment**:
   - The script polls services for up to 30 seconds.
   - All services (`parts-tools`, `parts-agent`, `postgresql`, `claw-swap-app`) should show "active".
   - On success, it prints the Parts git revision deployed and duration.

6. **Commit flake.lock if updated**:
   - If you ran `--update-input neurosys` or `--update-parts`, commit the updated `flake.lock` in the private overlay.

## Flags

| Flag | Description |
|------|-------------|
| `--node NAME` | Deploy flake node (`neurosys` or `ovh`, default: `neurosys`) |
| `--update-parts` | Pull latest `parts` flake input before building |
| `--skip-update` | No-op (parts update is skipped by default) |
| `--mode remote` | (default) Build on target host via deploy-rs `--remote-build` |
| `--mode local` | Build locally, push closure + switch remotely |
| `--target USER@HOST` | Override SSH target (default: `root@neurosys`) |
| `--first-deploy` | Disable magic rollback for one-time migration |
| `--no-magic-rollback` | Disable magic rollback for this deploy |

## What It Does

1. **Nix build** — Builds the full NixOS system closure (remote by default, local if `--mode local`)
2. **deploy-rs switch** — Atomically switches the server to the new config with magic rollback
3. **Service health poll** — Checks systemd services are running (30s timeout)
4. **Cachix push** — Pushes system closure to cache after successful deploy (Contabo only)

## Troubleshooting

- **Rollback**: `ssh root@neurosys nixos-rebuild switch --rollback`
- **Service logs**: `ssh root@neurosys journalctl -u <service> -n 50`
- **Lock stuck**: If a previous deploy crashed, remove the remote lock:
  ```bash
  ssh root@neurosys rm -rf /var/lock/neurosys-neurosys-deploy.lock
  rm -f tmp/neurosys-neurosys-deploy.local.lock
  ```
- **Build failures**: Check Nix build output for derivation errors. Common cause: Parts tests failing in the Nix build.
- **Stale neurosys input**: If public neurosys was updated but private overlay uses old version, run `nix flake lock --update-input neurosys` in the private overlay.
