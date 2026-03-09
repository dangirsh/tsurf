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
   # Deploy Contabo (services host) only:
   ./scripts/deploy.sh --node neurosys

   # Deploy OVH (dev host) only:
   ./scripts/deploy.sh --node ovh

   # Deploy BOTH hosts in parallel:
   ./scripts/deploy.sh --node all

   # Pull latest parts first (Contabo only):
   ./scripts/deploy.sh --node neurosys --update-parts

   # Local build fallback (if server unreachable):
   ./scripts/deploy.sh --node ovh --mode local
   ```

4. **Monitor output**:
   - Single node: shows progress inline (build → activate → health check).
   - `--node all`: spawns parallel processes, shows per-node success/failure summary.
     Logs written to `tmp/deploy-neurosys.log` and `tmp/deploy-ovh.log`.

5. **Verify deployment**:
   - Contabo checks: `parts-tools`, `parts-agent`, `postgresql`, `claw-swap-app`
   - OVH checks: `syncthing`, `tailscaled`, `secret-proxy-dev`
   - On success, prints duration and service status.

6. **Commit flake.lock if updated**:
   - If you ran `--update-input neurosys` or `--update-parts`, commit the updated `flake.lock` in the private overlay.

## Targeting Rules

| User says | Action |
|-----------|--------|
| "deploy" (no qualifier) | Ask which node, or deploy the node relevant to current work |
| "deploy to OVH" / "deploy dev" | `--node ovh` |
| "deploy to Contabo" / "deploy services" | `--node neurosys` |
| "deploy both" / "deploy all" / "deploy everything" | `--node all` |

**Never deploy Contabo when only OVH changes were made, and vice versa.**
Hosts are independent — deploy only what changed.

## Flags

| Flag | Description |
|------|-------------|
| `--node NAME` | Deploy flake node (`neurosys`, `ovh`, or `all`; default: `neurosys`) |
| `--update-parts` | Pull latest `parts` flake input before building (Contabo only) |
| `--skip-update` | No-op (parts update is skipped by default) |
| `--mode remote` | (default) Build on target host via deploy-rs `--remote-build` |
| `--mode local` | Build locally, push closure + switch remotely |
| `--target USER@HOST` | Override SSH target (default: `root@neurosys` or `root@neurosys-dev`) |
| `--first-deploy` | Disable magic rollback for one-time migration |
| `--no-magic-rollback` | Disable magic rollback for this deploy |

## What It Does

1. **Nix build** — Builds the full NixOS system closure (remote by default, local if `--mode local`)
2. **deploy-rs switch** — Atomically switches the server to the new config with magic rollback
3. **Service health poll** — Checks systemd services are running (30s timeout)
4. **Remote access verify** — Tests SSH via both Tailscale and public IP
5. **Cachix push** — Pushes system closure to cache after successful deploy (Contabo only)

## Troubleshooting

- **Rollback**: `ssh root@neurosys nixos-rebuild switch --rollback` (or `root@neurosys-dev`)
- **Service logs**: `ssh root@neurosys journalctl -u <service> -n 50`
- **Lock stuck**: If a previous deploy crashed, remove the remote lock:
  ```bash
  # Contabo:
  ssh root@neurosys rm -rf /var/lock/neurosys-neurosys-deploy.lock
  # OVH:
  ssh root@neurosys-dev rm -rf /var/lock/neurosys-ovh-deploy.lock
  ```
- **Build failures**: Check Nix build output for derivation errors.
- **Stale neurosys input**: Run `nix flake lock --update-input neurosys` in the private overlay.
- **Parallel deploy logs**: Check `tmp/deploy-neurosys.log` and `tmp/deploy-ovh.log`.
