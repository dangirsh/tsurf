---
name: deploy
description: Deploy tsurf NixOS config to tsurf server
user_invocable: true
---

# Deploy Skill

Deploy the tsurf NixOS configuration via deploy-rs.

**CRITICAL: ALL deploys MUST run from the private overlay.** The public repo's
`deploy.sh` refuses all deploys because both hosts run the private overlay config.

## How to Deploy

When the user asks to deploy (or invokes `/deploy`), follow these steps:

1. **Always use the private overlay**:
   ```bash
   cd /path/to/private-tsurf
   ```

2. **If public tsurf was updated**, refresh the input first:
   ```bash
   nix flake lock --update-input tsurf
   ```

3. **Execute the deploy script**:
   ```bash
   # Deploy Contabo (services host) only:
   ./scripts/deploy.sh --node tsurf

   # Deploy OVH (dev host) only:
   ./scripts/deploy.sh --node ovh

   # Deploy BOTH hosts in parallel:
   ./scripts/deploy.sh --node all

   # Pull latest parts first (Contabo only):
   ./scripts/deploy.sh --node tsurf --update-parts

   # Local build fallback (if server unreachable):
   ./scripts/deploy.sh --node ovh --mode local
   ```

4. **Monitor output**:
   - Single node: shows progress inline (build → activate → health check).
   - `--node all`: spawns parallel processes, shows per-node success/failure summary.
     Logs written to `tmp/deploy-tsurf.log` and `tmp/deploy-ovh.log`.

5. **Verify deployment**:
   - deploy.sh runs service health checks automatically (private overlay defines which services).
   - On success, prints duration and service status.

6. **Commit flake.lock if updated**:
   - If you ran `--update-input tsurf` or `--update-parts`, commit the updated `flake.lock` in the private overlay.

## Targeting Rules

| User says | Action |
|-----------|--------|
| "deploy" (no qualifier) | Ask which node, or deploy the node relevant to current work |
| "deploy to OVH" / "deploy dev" | `--node ovh` |
| "deploy to Contabo" / "deploy services" | `--node tsurf` |
| "deploy both" / "deploy all" / "deploy everything" | `--node all` |

**Never deploy Contabo when only OVH changes were made, and vice versa.**
Hosts are independent — deploy only what changed.

## Flags

| Flag | Description |
|------|-------------|
| `--node NAME` | Deploy flake node (`tsurf`, `ovh`, or `all`; default: `tsurf`) |
| `--update-parts` | Pull latest `parts` flake input before building (Contabo only) |
| `--skip-update` | No-op (parts update is skipped by default) |
| `--mode remote` | (default) Build on target host via deploy-rs `--remote-build` |
| `--mode local` | Build locally, push closure + switch remotely |
| `--target USER@HOST` | Override SSH target (default: `root@tsurf` or `root@tsurf-dev`) |
| `--first-deploy` | Disable magic rollback for one-time migration |
| `--no-magic-rollback` | Disable magic rollback for this deploy |

## What It Does

1. **Nix build** — Builds the full NixOS system closure (remote by default, local if `--mode local`)
2. **deploy-rs switch** — Atomically switches the server to the new config with magic rollback
3. **Service health poll** — Checks systemd services are running (30s timeout)
4. **Remote access verify** — Tests SSH via both Tailscale and public IP
5. **Cachix push** — Pushes system closure to cache after successful deploy (Contabo only)

## Troubleshooting

- **Rollback**: `ssh root@tsurf nixos-rebuild switch --rollback` (or `root@tsurf-dev`)
- **Service logs**: `ssh root@tsurf journalctl -u <service> -n 50`
- **Lock stuck**: If a previous deploy crashed, remove the remote lock:
  ```bash
  # Contabo:
  ssh root@tsurf rm -rf /var/lock/tsurf-tsurf-deploy.lock
  # OVH:
  ssh root@tsurf-dev rm -rf /var/lock/tsurf-ovh-deploy.lock
  ```
- **Build failures**: Check Nix build output for derivation errors.
- **Stale tsurf input**: Run `nix flake lock --update-input tsurf` in the private overlay.
- **Parallel deploy logs**: Check `tmp/deploy-tsurf.log` and `tmp/deploy-ovh.log`.
