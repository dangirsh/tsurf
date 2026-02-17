# Deployment Runbook — Parts Pipeline

**Created:** 2026-02-17

## Prerequisites

- SSH access to `root@acfs` via Tailscale (`ssh root@acfs` must work)
- Nix installed with flakes enabled
- agent-neurosys repo checked out
- GitHub access token configured in `~/.config/nix/nix.conf` (for private repos)

## Deploy Commands

### Deploy with latest parts (most common)

```bash
./scripts/deploy.sh
```

Updates the `parts` flake input to latest `main`, builds the NixOS system locally, pushes the closure to acfs via SSH, activates it, and verifies all containers are running.

### Deploy without updating parts

```bash
./scripts/deploy.sh --skip-update
```

Skips `nix flake update parts`. Use when only agent-neurosys NixOS config changed (not parts).

### Deploy from the server itself

```bash
./scripts/deploy.sh --mode remote
```

SSHes into acfs, runs `git pull --ff-only`, updates parts input, and runs `nixos-rebuild switch` directly on the server. Useful when local machine has poor bandwidth.

## Expected Output (Success)

```
==> Updating parts flake input...
==> Parts revision: 1bbd22d
==> Building locally and deploying to root@acfs...
==> Verifying containers (polling up to 30s)...

=== Deploy SUCCESS ===
Parts revision: 1bbd22d
Duration: 3m 42s

Container status:
NAMES          STATUS
parts-tools    Up 15 seconds
parts-agent    Up 15 seconds
claw-swap-db   Up 2 hours
claw-swap-app  Up 2 hours
claw-swap-caddy Up 2 hours

NOTE: flake.lock was updated. Remember to commit when ready:
  git add flake.lock && git commit -m "chore: update parts input to 1bbd22d"
```

## Interpreting Failures

### Build failure
- Run `nix flake check` to check for evaluation errors
- Common causes: syntax errors in NixOS modules, missing inputs, broken dependencies
- The build happens locally — check local disk space and Nix store

### Switch failure
- Systemd service activation failed on the server
- Check logs: `ssh root@acfs journalctl -u docker-parts-tools.service --no-pager -n 50`
- Check all services: `ssh root@acfs systemctl list-units --failed`

### Container health failure
- Containers didn't start within 30s of switch
- Check Docker logs: `ssh root@acfs docker logs parts-tools`
- Check if images loaded: `ssh root@acfs docker images | grep parts`
- Check systemd: `ssh root@acfs systemctl status docker-parts-tools.service`

## Rollback

```bash
ssh root@acfs nixos-rebuild switch --rollback
```

Activates the previous NixOS generation. All containers, networks, and services revert to their prior state. NixOS generations are automatic — every `nixos-rebuild switch` creates one.

To see available generations:
```bash
ssh root@acfs nixos-rebuild list-generations | tail -5
```

## After Deploy

1. **Commit flake.lock** (if parts was updated):
   ```bash
   git add flake.lock && git commit -m "chore: update parts input to <rev>"
   ```

2. **Verify services** (optional spot-check):
   ```bash
   ssh root@acfs docker ps
   ssh root@acfs docker logs parts-tools --tail 20
   ```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `ssh: Could not resolve hostname acfs` | Tailscale not connected. Run `tailscale up` |
| `error: unable to download ... HTTP 404` | Private repo access. Check `access-tokens` in `~/.config/nix/nix.conf` |
| `command not found: nixos-rebuild` | Expected on non-NixOS. Script uses `nix shell nixpkgs#nixos-rebuild` |
| `error: path does not exist` | Still using `path:` input? Check `flake.nix` uses `github:` URLs |
| `No space left on device` | Run `ssh root@acfs nix-collect-garbage -d` |
| Containers flapping | Check Docker logs, verify secrets decrypted: `ssh root@acfs ls /run/secrets/` |

## What Gets Deployed

The deploy is a full `nixos-rebuild switch`. NixOS only rebuilds changed derivations and restarts affected services. Components managed:

- **parts**: 2 containers (parts-tools, parts-agent), 2 networks, 10 secrets, 2 env templates
- **claw-swap**: 3 containers (db, app, caddy), 1 network, secrets
- **System**: all NixOS modules (networking, firewall, users, home-manager, etc.)
