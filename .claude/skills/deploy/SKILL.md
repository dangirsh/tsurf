---
name: deploy
description: Deploy agent-neurosys NixOS config to neurosys server
user_invocable: true
---

# Deploy Skill

Deploy the agent-neurosys NixOS configuration to the Contabo VPS (neurosys) via `nixos-rebuild`.

## How to Deploy

When the user asks to deploy (or invokes `/deploy`), follow these steps:

1. **Detect repo and resolve script path**:
   - From **agent-neurosys**: `./scripts/deploy.sh`
   - From **parts**: `../agent-neurosys/scripts/deploy.sh`
   - Verify the script exists before proceeding.

2. **Execute the deploy script**:
   ```bash
   # From agent-neurosys:
   ./scripts/deploy.sh

   # Or with flags:
   ./scripts/deploy.sh --skip-update
   ```

3. **Monitor output**:
   - The script shows progress: flake update, nix build, nixos-rebuild switch, container health check.
   - Watch for errors at each phase.

4. **Verify deployment**:
   - The script polls containers for up to 30 seconds.
   - All containers (`parts-tools`, `parts-agent`, `claw-swap-db`, `claw-swap-app`, `claw-swap-caddy`) should show "Up".
   - On success, it prints the Parts git revision deployed and duration.

5. **Commit flake.lock if updated**:
   - If deployed without `--skip-update`, the script reminds you to commit `flake.lock` in agent-neurosys.

## Flags

| Flag | Description |
|------|-------------|
| `--skip-update` | Skip `nix flake update parts` — deploy whatever revision is already locked |
| `--mode local` | (default) Build locally, push closure + switch remotely |
| `--mode remote` | SSH into server, `git pull`, rebuild on server |
| `--target USER@HOST` | Override SSH target (default: `root@neurosys`) |

## What It Does

1. **Flake update** — Pulls latest Parts commit into `flake.lock` (unless `--skip-update`)
2. **Nix build** — Builds the full NixOS system closure (local or remote)
3. **nixos-rebuild switch** — Atomically switches the server to the new config
4. **Container health poll** — Checks all containers are running (30s timeout)

## Troubleshooting

- **Rollback**: `ssh root@neurosys nixos-rebuild switch --rollback`
- **Container logs**: `ssh root@neurosys docker logs parts-tools` (or `parts-agent`, etc.)
- **SSH access**: `ssh root@neurosys` (or `ssh root@62.171.134.33` via public IP)
- **Lock stuck**: If a previous deploy crashed, remove the remote lock:
  ```bash
  ssh root@neurosys rm -rf /var/lock/neurosys-deploy.lock
  ```
- **Build failures**: Check Nix build output for derivation errors. Common cause: Parts tests failing in the Nix build.
