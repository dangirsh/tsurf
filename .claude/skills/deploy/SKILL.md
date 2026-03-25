---
name: deploy
description: Deploy tsurf NixOS config to a server
user_invocable: true
---

# Deploy Skill

Deploy the tsurf NixOS configuration via deploy-rs.

**CRITICAL: ALL deploys MUST run from the private overlay.** The public repo's
`deploy.sh` refuses all deploys because hosts run the private overlay config.

## How to Deploy

When the user asks to deploy (or invokes `/deploy`), follow these steps:

1. **Always use the private overlay**:
   ```bash
   cd /path/to/private-overlay
   ```

2. **If public tsurf was updated**, refresh the input first:
   ```bash
   nix flake lock --update-input tsurf
   ```

3. **Execute the deploy script**:
   ```bash
   # Deploy a specific host:
   ./scripts/deploy.sh --node <hostname>

   # Local build fallback (if server can't build):
   ./scripts/deploy.sh --node <hostname> --mode local

   # Fast mode (local build, single eval):
   ./scripts/deploy.sh --node <hostname> --fast

   # First migration deploy from nixos-rebuild:
   ./scripts/deploy.sh --node <hostname> --first-deploy
   ```

4. **Monitor output**:
   - Shows progress inline (build, activate, health check).

5. **Verify deployment**:
   - deploy.sh runs service health checks automatically.
   - On success, prints duration and service status.

6. **Commit flake.lock if updated**:
   - If you ran `--update-input tsurf`, commit the updated `flake.lock` in the private overlay.

## Targeting Rules

| User says | Action |
|-----------|--------|
| "deploy" (no qualifier) | Ask which node, or deploy the node relevant to current work |
| "deploy to <hostname>" | `--node <hostname>` |
| "deploy both" / "deploy all" | Deploy each node separately in sequence |

**Never deploy a host when only a different host's changes were made.**
Hosts are independent -- deploy only what changed.

## Flags

| Flag | Description |
|------|-------------|
| `--node NAME` | Flake node to deploy (required) |
| `--mode remote` | (default) Build on target host via deploy-rs `--remote-build` |
| `--mode local` | Build locally, push closure + switch remotely |
| `--target USER@HOST` | Override SSH target (default: `root@<node>`) |
| `--first-deploy` | Disable magic rollback for one-time migration |
| `--fast` | Local build, single evaluation |
| `--magic-rollback` | Enable deploy-rs magic rollback (300s confirm timeout) |
| `--public-ip IP` | Public IP for post-deploy connectivity check |
| `--post-hook PATH` | Run script at absolute PATH after successful deploy |

## What It Does

1. **Safety guard** -- Refuses to deploy from the public repo (no `tsurf.url` in flake.nix)
2. **Remote lock** -- Prevents concurrent deploys via remote directory lock
3. **Nix build** -- Builds the full NixOS system closure (remote by default, local if `--mode local`)
4. **deploy-rs switch** -- Atomically switches the server to the new config
5. **Service verification** -- Checks tailscaled and sshd are running
6. **SSH connectivity** -- Verifies fresh SSH connection (non-multiplexed)

## Troubleshooting

- **Rollback**: `ssh root@<hostname> nixos-rebuild switch --rollback`
- **Service logs**: `ssh root@<hostname> journalctl -u <service> -n 50`
- **Lock stuck**: If a previous deploy crashed, remove the remote lock:
  ```bash
  ssh root@<hostname> rm -rf /var/lock/deploy-<node>.lock
  ```
- **Build failures**: Check Nix build output for derivation errors.
- **Stale tsurf input**: Run `nix flake lock --update-input tsurf` in the private overlay.
