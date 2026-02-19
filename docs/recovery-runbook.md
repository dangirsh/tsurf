# Disaster Recovery Runbook -- neurosys VPS

> **Last verified: 2026-02-19.** Review after any changes to backup paths, services, or secrets.

## 1. Overview

This document covers **complete VPS recovery from catastrophic loss** -- total disk failure, provider wipe, or any scenario where the server must be rebuilt from scratch.

**Recovery sources:**

| Source | Contains |
|--------|----------|
| Git repo (`agent-neurosys`) | NixOS configuration, encrypted secrets, flake lock |
| Backblaze B2 (`SyncBkp`) | Stateful data: projects, home dir, Docker data, SSH host key, Tailscale state, Home Assistant |
| Manual | Tailscale re-auth (if backup stale), Home Assistant device pairing (if restore fails) |

**Recovery targets:**

| Metric | Target |
|--------|--------|
| RTO (Recovery Time Objective) | < 2 hours |
| RPO (Recovery Point Objective) | 24 hours (daily backups) |

**Time breakdown:**

| Phase | Estimated Time |
|-------|---------------|
| Phase 1: Deploy NixOS from git | 30 min |
| Phase 2: Restore stateful data from B2 | 30 min |
| Phase 3: Manual re-authentication | 15 min |
| Phase 4: Verification | 15 min |
| Buffer | 30 min |
| **Total** | **< 2 hours** |

---

## 2. Prerequisites

Before starting recovery, gather the following. **You need items 1-4 before anything else works.**

### 2.1 Local machine with Nix installed

`nixos-anywhere` runs from your local workstation. Install Nix if not present:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### 2.2 The agent-neurosys git repo cloned locally

```bash
git clone git@github.com:<org>/agent-neurosys.git
cd agent-neurosys
```

### 2.3 SSH access to the new VPS

Obtain root SSH access via:
- Contabo dashboard rescue console, OR
- New VPS provisioning (note the new IP address)

Verify:

```bash
ssh root@<new-vps-ip> echo "SSH works"
```

### 2.4 Restic credentials (needed BEFORE sops-nix works on the new server)

The restic password and B2 API keys are encrypted in `secrets/neurosys.yaml`. On recovery, the new server cannot decrypt them yet (no SSH host key = no age key). Extract them locally using your admin age private key.

**Admin age private key must be at:** `~/.config/sops/age/keys.txt` on your local machine.

```bash
# Extract restic repository password
sops -d secrets/neurosys.yaml | grep restic-password

# Extract B2 credentials
sops -d secrets/neurosys.yaml | grep b2-key-id
sops -d secrets/neurosys.yaml | grep b2-application-key
```

Write these values down or export them -- you will need them in Phase 1 and Phase 2.

### 2.5 Fresh Tailscale auth key (if needed)

If the Tailscale state backup is stale (device was re-authed after the last backup), generate a new auth key:

1. Go to https://login.tailscale.com/admin/settings/keys
2. Generate a reusable auth key
3. Keep it ready for Phase 3

### 2.6 New VPS IP address

The new VPS may have a different IP than the old one (`161.97.74.121`). Record the new IP -- you will need to update NixOS config if it changed.

---

## 3. What's Where

**Backup approach:** Blanket `/` with `--one-file-system` and exclusions. All stateful paths on the root filesystem are backed up automatically -- no manual path additions needed when services are added. See `modules/restic.nix` for the exclusion list. To opt out a directory, place a `.nobackup` file in it.

| Data | Source | Recovery Method |
|------|--------|----------------|
| NixOS configuration | Git repo | `nix flake check` validates, `nixos-anywhere` deploys |
| SSH host ed25519 key | B2 backup | `restic restore` then `--extra-files` to nixos-anywhere |
| Docker bind mount data (claw-swap, parts) | B2 backup | `restic restore` to `/var/lib/claw-swap/`, `/var/lib/parts/` |
| PostgreSQL logical dump | B2 backup | Inside `/var/lib/claw-swap/pgdata/backup.sql` (from pre-backup hook) |
| Tailscale device state | B2 backup | `restic restore` to `/var/lib/tailscale/` |
| Home Assistant state | B2 backup | `restic restore` to `/var/lib/hass/` |
| User home + Syncthing | B2 backup | `restic restore` to `/home/dangirsh/` |
| Code repos | B2 backup + git remotes | B2 has latest uncommitted work; git has committed history |
| All other `/var/lib/*` state | B2 backup | Auto-included by blanket backup (Syncthing certs, NixOS UID maps, fail2ban, etc.) |
| sops-nix secrets | Git repo (encrypted) | Decrypted automatically once SSH host key is restored |
| Tailscale auth | Manual re-auth | Only if `/var/lib/tailscale/` restore is stale |
| Home Assistant device pairing | Manual re-setup | Only if `/var/lib/hass/` restore fails |

---

## 4. Phase 1 -- Deploy NixOS from Git (est. 30 min)

### Step 1.1: Extract SSH host key from B2 backup

The SSH host key is the **single most critical file**. Without it, sops-nix cannot derive the age decryption key, and no secrets will decrypt on the new server.

```bash
# On your LOCAL machine -- set restic credentials from step 2.4
export AWS_ACCESS_KEY_ID="<b2-key-id from sops -d secrets/neurosys.yaml>"
export AWS_SECRET_ACCESS_KEY="<b2-application-key from sops -d secrets/neurosys.yaml>"
export RESTIC_REPOSITORY="s3:s3.eu-central-003.backblazeb2.com/SyncBkp"
export RESTIC_PASSWORD="<restic-password from sops -d secrets/neurosys.yaml>"
```

```bash
# List available snapshots -- pick the latest
restic snapshots
```

```bash
# Restore only the SSH host key to a staging directory
mkdir -p /tmp/host-keys/etc/ssh
restic restore latest --target /tmp/host-keys \
  --include /etc/ssh/ssh_host_ed25519_key \
  --include /etc/ssh/ssh_host_ed25519_key.pub
```

```bash
# Fix permissions (restic may not preserve them correctly)
chmod 600 /tmp/host-keys/etc/ssh/ssh_host_ed25519_key
chmod 644 /tmp/host-keys/etc/ssh/ssh_host_ed25519_key.pub
```

**Verify:**

```bash
ls -la /tmp/host-keys/etc/ssh/ssh_host_ed25519_key
# Expected: non-empty file with -rw------- (600) permissions
```

### Step 1.2: Update NixOS config if IP changed

If the new VPS has a different IP than `161.97.74.121`, update the static IP configuration:

```bash
cd /path/to/agent-neurosys

# Edit the hardware/networking config
# Look for the old IP and replace with the new one
grep -r "161.97.74.121" hosts/neurosys/
# Update the matching file(s)
```

Commit the change if needed:

```bash
git add hosts/neurosys/
git commit -m "fix: update VPS IP for disaster recovery"
```

### Step 1.3: Deploy with nixos-anywhere

```bash
cd /path/to/agent-neurosys
nixos-anywhere --extra-files /tmp/host-keys \
  --flake .#neurosys root@<new-vps-ip>
```

This will:
1. Boot the target into a kexec environment
2. Partition disks (via disko)
3. Install the NixOS configuration from the flake
4. Inject the SSH host key from `--extra-files`
5. Reboot into the new system

**Verify:**

```bash
# SSH works
ssh root@<new-vps-ip> hostname
# Expected: "neurosys"

# sops secrets decrypted successfully
ssh root@<new-vps-ip> ls /run/secrets/ | wc -l
# Expected: 15+ files

# Quick spot-check a secret
ssh root@<new-vps-ip> test -f /run/secrets/restic-password && echo "OK" || echo "FAIL"
# Expected: "OK"
```

```bash
# Clean up local staging directory
rm -rf /tmp/host-keys
```

---

## 5. Phase 2 -- Restore Stateful Data from B2 (est. 30 min)

### Step 2.1: Set restic credentials on the VPS

After Phase 1, sops-nix should have decrypted all secrets. Use them directly:

```bash
ssh root@<new-vps-ip>
```

```bash
# Check that sops-nix decrypted the restic credentials
cat /run/secrets/restic-password
ls /run/secrets/rendered/restic-b2-env

# Source the B2 environment variables
source /run/secrets/rendered/restic-b2-env
export RESTIC_PASSWORD=$(cat /run/secrets/restic-password)
export RESTIC_REPOSITORY="s3:s3.eu-central-003.backblazeb2.com/SyncBkp"
```

If sops-nix secrets are NOT available (sops activation failed), fall back to manual credential entry using the values from Prerequisite 2.4:

```bash
export AWS_ACCESS_KEY_ID="<b2-key-id>"
export AWS_SECRET_ACCESS_KEY="<b2-application-key>"
export RESTIC_REPOSITORY="s3:s3.eu-central-003.backblazeb2.com/SyncBkp"
export RESTIC_PASSWORD="<restic-password>"
```

### Step 2.2: Verify repository integrity

```bash
restic check
# Expected: "no errors were found"

restic snapshots
# Expected: list of daily snapshots, latest should be < 24h old
```

### Step 2.3: Stop services before restore

Prevent conflicts between running services and restored files:

```bash
systemctl stop docker.service
systemctl stop home-assistant.service
systemctl stop tailscaled.service
```

### Step 2.4: Restore all stateful data

**Option A -- Full restore (recommended):**

The blanket backup includes everything on the root filesystem except ephemeral/reproducible paths. Restore it all at once:

```bash
restic restore latest --target /
```

**Option B -- Selective restore (if you only need specific paths):**

```bash
restic restore latest --target / \
  --include /var/lib/claw-swap \
  --include /var/lib/parts \
  --include /var/lib/tailscale \
  --include /var/lib/hass \
  --include /data/projects \
  --include /home/dangirsh
```

### Step 2.8: Fix ownership

Restic restores may set incorrect uid/gid. Fix ownership for user-owned paths:

```bash
chown -R dangirsh:users /home/dangirsh/
chown -R dangirsh:users /data/projects/
# Docker bind mount data should remain root-owned (containers use root inside)
```

### Step 2.9: Start services

```bash
systemctl start docker.service
systemctl start home-assistant.service
systemctl start tailscaled.service
```

**Verify:**

```bash
# Docker containers running
docker ps --format '{{.Names}}'
# Expected: claw-swap-*, parts-* containers listed

# Home Assistant active
systemctl status home-assistant.service --no-pager
# Expected: "active (running)"

# Projects restored
ls /data/projects/agent-neurosys/flake.nix
# Expected: file exists

# User home restored
ls /home/dangirsh/.config/syncthing/config.xml 2>/dev/null && echo "Syncthing OK" || echo "Syncthing not configured"
```

---

## 6. Phase 3 -- Manual Re-Authentication (est. 15 min)

### Step 3.1: Tailscale

If `/var/lib/tailscale/` was restored from a recent backup, Tailscale may reconnect automatically.

```bash
tailscale status
```

**If connected:** Skip to Step 3.2.

**If "NeedsLogin" or not connected:**

Option A -- Update sops secret and redeploy (persistent fix):

```bash
# On your LOCAL machine:
sops secrets/neurosys.yaml
# Edit the tailscale-authkey value with the fresh key from Prerequisite 2.5

git add secrets/neurosys.yaml
git commit -m "fix: update Tailscale auth key for recovery"

# Redeploy to apply the new secret
scripts/deploy.sh --target root@<new-vps-ip>
```

Option B -- Quick manual auth (immediate fix):

```bash
ssh root@<new-vps-ip> tailscale up --authkey=<fresh-auth-key>
```

**Verify:**

```bash
ssh root@<new-vps-ip> tailscale status
# Expected: shows connected peers
```

### Step 3.2: Home Assistant

If `/var/lib/hass/` was restored successfully, Home Assistant should work as-is.

```bash
ssh root@<new-vps-ip> curl -s http://localhost:8123/api/ | head -c 100
```

**If API responds:** Home Assistant is functional. No action needed.

**If onboarding screen appears (fresh install):** The restore failed or was incomplete. Device pairing must be redone manually through the Home Assistant web UI at `http://<vps-ip>:8123`.

---

## 7. Phase 4 -- Verification Checklist (est. 15 min)

Run each check and confirm the expected output:

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 1 | SSH access (user) | `ssh dangirsh@<vps-ip> whoami` | `dangirsh` |
| 2 | SSH access (root) | `ssh root@<vps-ip> whoami` | `root` |
| 3 | Secrets decrypted | `ssh root@<vps-ip> ls /run/secrets/ \| wc -l` | 15+ |
| 4 | Docker running | `ssh root@<vps-ip> docker ps --format '{{.Names}}'` | claw-swap-*, parts-* |
| 5 | claw-swap responds | `curl -sk https://claw-swap.com/` | HTTP 200 or redirect |
| 6 | PostgreSQL healthy | `ssh root@<vps-ip> docker exec claw-swap-db pg_isready` | "accepting connections" |
| 7 | Home Assistant | `ssh root@<vps-ip> curl -s http://localhost:8123/api/` | API response JSON |
| 8 | Tailscale connected | `ssh root@<vps-ip> tailscale status` | Shows connected peers |
| 9 | Restic backup timer | `ssh root@<vps-ip> systemctl status restic-backups-b2.timer` | "active (waiting)" |
| 10 | User home intact | `ssh dangirsh@<vps-ip> ls ~/Sync/ 2>/dev/null \|\| echo "No Sync dir"` | Syncthing data or expected output |

**If all 10 checks pass: recovery is complete.**

If any check fails, refer to the relevant Phase above to debug. Common issues:
- Check 3 fails: SSH host key was not restored correctly; re-run Phase 1
- Checks 4-6 fail: Docker data not restored; re-run Phase 2 Steps 2.4 and 2.9
- Check 8 fails: Tailscale needs re-auth; run Phase 3 Step 3.1

---

## 8. Appendix -- Credential Locations

| Credential | Location | How to Access |
|------------|----------|---------------|
| Admin age private key | `~/.config/sops/age/keys.txt` (local machine) | File on admin workstation -- **back this up separately** |
| Admin age public key | `age1vma7w9nqlg9da8z60a99g8wv53ufakfmzxpkdnnzw39y34grug7qklz3xz` | In `.sops.yaml` |
| Host age public key | `age1jgn7pqqf4hvalqdrzqysxtnsydd5urnuczrfm86umr7yfr8pu5gqqet2t3` | Derived from SSH host key; in `.sops.yaml` |
| Restic password | `secrets/neurosys.yaml` (encrypted) | `sops -d secrets/neurosys.yaml \| grep restic-password` |
| B2 key ID | `secrets/neurosys.yaml` (encrypted) | `sops -d secrets/neurosys.yaml \| grep b2-key-id` |
| B2 application key | `secrets/neurosys.yaml` (encrypted) | `sops -d secrets/neurosys.yaml \| grep b2-application-key` |
| Tailscale auth key | Tailscale admin console | https://login.tailscale.com/admin/settings/keys |
| All other service secrets | `secrets/neurosys.yaml` (encrypted) | Decrypted by sops-nix on server using SSH host key |

**Critical note:** The admin age private key is the **root of trust** for disaster recovery. If you lose both the server AND the admin age key, you cannot decrypt `secrets/neurosys.yaml` and must regenerate all secrets from scratch. Keep a secure backup of `~/.config/sops/age/keys.txt` outside the server (password manager, encrypted USB, etc.).

---

## 9. Appendix -- Excluded from Backup

Restic backs up the entire root filesystem (`/`) with `--one-file-system` (skips /proc, /sys, /dev, /run, /tmp automatically). The following paths are explicitly excluded in `modules/restic.nix`:

| Path | Why Excluded | Impact of Loss |
|------|-------------|----------------|
| `/nix` | Fully reproducible from `flake.lock` (50-200 GB) | Rebuilt automatically during `nixos-anywhere` deploy |
| `/var/lib/docker/overlay2` | Docker image layers, rebuilt from images (potentially huge) | `docker compose up` or NixOS activation rebuilds them |
| `/var/lib/docker/tmp` | Docker temp files | None |
| `/var/lib/docker/buildkit` | BuildKit cache | None |
| `/var/cache` | System package caches | Rebuilt automatically |
| `**/.cache` | User cache directories | Rebuilt automatically |
| `/var/lib/prometheus` | Metrics rebuilt from scratch | Lose historical graphs (accepted -- monitoring restarts clean) |
| `.git/objects` | Fetched from git remotes | `git fetch` restores them |
| `.git/config` | May contain credential tokens | Recreated by `git clone` |
| `node_modules`, `__pycache__`, `.direnv`, `result` | Language/build artifacts | Rebuilt from lockfiles |

**Ad-hoc opt-out:** Place a `.nobackup` file in any directory to exclude it from backup (uses restic's `--exclude-if-present`). Directories with a `CACHEDIR.TAG` file are also excluded (`--exclude-caches`).

---

## 10. Appendix -- Testing This Runbook

### What has been verified

- **Dry-run restore:** `restic restore latest --target /tmp/restore-test/` on the live VPS confirmed all critical files are present in backups
- **Repository integrity:** `restic check` passed (no corruption)
- **Critical file spot-checks:**
  - `/etc/ssh/ssh_host_ed25519_key` -- present, correct size
  - `/var/lib/claw-swap/pgdata/PG_VERSION` -- PostgreSQL data directory populated
  - `/var/lib/parts/` -- runtime data present
  - `/var/lib/tailscale/` -- device state present
  - `/var/lib/hass/home-assistant_v2.db` -- Home Assistant database present
  - `/home/dangirsh/` -- user home populated
  - `/data/projects/agent-neurosys/flake.nix` -- code repos present
- **nixos-anywhere deploy:** Proven in Phase 2 (2026-02-15) initial deployment and Phase 10 VPS migration (2026-02-17)
- **`--extra-files` pattern:** Used successfully during initial deployment to inject pre-generated SSH host key

### What is assumed (not tested end-to-end)

- `restic restore --target /` on a fresh NixOS install writes files to correct absolute paths (restic documentation confirms this behavior, but not tested on a clean slate for this specific server)
- Service startup after restore does not require additional configuration beyond what NixOS declares (services are declaratively configured; only stateful data needs restoration)
- Combined flow (nixos-anywhere + restic restore + service start) completes within the 2-hour RTO (individual phases are proven, combined timing is estimated)

### How to test without destroying the server

```bash
# 1. Verify restic repository is healthy
ssh root@161.97.74.121 'source /run/secrets/rendered/restic-b2-env && \
  export RESTIC_PASSWORD=$(cat /run/secrets/restic-password) && \
  export RESTIC_REPOSITORY="s3:s3.eu-central-003.backblazeb2.com/SyncBkp" && \
  restic check'

# 2. Test restore to a temporary directory (does NOT touch live system)
ssh root@161.97.74.121 'source /run/secrets/rendered/restic-b2-env && \
  export RESTIC_PASSWORD=$(cat /run/secrets/restic-password) && \
  export RESTIC_REPOSITORY="s3:s3.eu-central-003.backblazeb2.com/SyncBkp" && \
  mkdir -p /tmp/restore-test && \
  restic restore latest --target /tmp/restore-test'

# 3. Spot-check critical files
ssh root@161.97.74.121 'ls -la /tmp/restore-test/etc/ssh/ssh_host_ed25519_key'
ssh root@161.97.74.121 'ls /tmp/restore-test/var/lib/claw-swap/pgdata/PG_VERSION'
ssh root@161.97.74.121 'ls /tmp/restore-test/var/lib/tailscale/'
ssh root@161.97.74.121 'ls /tmp/restore-test/var/lib/hass/home-assistant_v2.db'
ssh root@161.97.74.121 'ls /tmp/restore-test/data/projects/agent-neurosys/flake.nix'

# 4. Clean up
ssh root@161.97.74.121 'rm -rf /tmp/restore-test'
```

### When to re-test

Re-run the dry-run restore test after:
- Adding new exclusions to `modules/restic.nix`
- Changing the sops-nix secrets structure
- Changing the VPS provider or disk layout
