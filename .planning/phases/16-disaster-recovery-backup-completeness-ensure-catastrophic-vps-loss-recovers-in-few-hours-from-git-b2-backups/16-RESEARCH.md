# Phase 16: Disaster Recovery & Backup Completeness - Research

**Researched:** 2026-02-19
**Domain:** NixOS disaster recovery, restic backup, operational runbooks
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Recovery scope
- "Fully recovered" = all NixOS services running, all Docker containers healthy, all secrets decrypted, SSH access working
- Recovery flow: `nixos-anywhere` deploy from git -> `restic restore` stateful data -> minimal manual re-auth -> verify services
- Target recovery time: < 2 hours total (30min deploy, 30min restore, 30min verify, 30min re-auth buffer)
- Manual re-auth list (unavoidable, document these):
  - Tailscale: generate fresh auth key in admin console
  - Home Assistant: device re-pairing only if `/var/lib/hass/` restore fails
  - No other services require external re-auth -- everything else in sops secrets or git

#### Backup coverage -- gaps to close
- ADD `/etc/ssh/ssh_host_ed25519_key*` -- without host key, sops-nix can't derive age key, no secrets decrypt
- ADD `/var/lib/docker/volumes/` -- claw-swap PostgreSQL data is not reconstructible
- ADD `/var/lib/tailscale/` -- avoids Tailscale re-auth if state survives restore
- SKIP `/var/lib/prometheus/` -- accept metrics loss on catastrophic failure, Prometheus rebuilds from scratch (saves B2 cost)
- SKIP `/var/lib/fail2ban/` -- reconstructible, low value
- Keep existing excludes: `.git/objects`, `node_modules`, `__pycache__`, `.direnv`, `result`, `/nix/store`
- RPO: 24 hours (daily backups) -- acceptable for personal server

#### Already covered (no changes needed)
- `/data/projects/` -- code repos, agent configs, secrets yaml (encrypted)
- `/home/dangirsh/` -- Syncthing config/data, home-manager state, podman storage
- `/var/lib/hass/` -- Home Assistant state/database

#### Runbook format
- Lives in git at `docs/recovery-runbook.md` (versioned with the config it documents)
- Numbered steps with verification checks after each -- detailed enough for an agent to follow
- Includes exact commands, not descriptions
- Clearly separates: what's in git (config) vs what's in B2 (state) vs what needs manual re-auth
- Lists pre-requisites (local age key, SSH access to B2, fresh Tailscale auth key)

#### Testing depth
- Dry-run restore to temporary directory on VPS + verify file integrity and completeness
- NOT a full wipe-and-rebuild (too risky on only VPS; nixos-anywhere deploy already proven)
- Run `restic check` (repo integrity) + `restic restore --target /tmp/restore-test/` + spot-check critical files
- Document what was verified vs what was assumed

### Claude's Discretion
- Exact restic path patterns for SSH host keys (glob vs explicit paths)
- Whether to add restic pre/post hooks for consistency (e.g., docker pause before backup)
- Runbook section organization and formatting
- Which files to spot-check during restore verification

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

## Summary

Phase 16 completes the disaster recovery story for the acfs VPS. The existing restic backup (quick task 7, deployed 2026-02-19) covers `/data/projects/`, `/home/dangirsh/`, and `/var/lib/hass/` but has three critical gaps: SSH host keys (which sops-nix needs to derive the age decryption key), Docker host volumes (claw-swap PostgreSQL data at `/var/lib/claw-swap/pgdata` and parts data at `/var/lib/parts/`), and Tailscale state. Closing these gaps and writing a tested recovery runbook makes the difference between a 2-hour recovery and a multi-day scramble.

The implementation is straightforward: add paths to `modules/restic.nix`, add a `backupPrepareCommand` hook for PostgreSQL consistency, write `docs/recovery-runbook.md` referencing exact commands, and validate with a dry-run restore. No new services, no infrastructure changes -- just closing gaps in what already exists and documenting the recovery procedure.

**Primary recommendation:** Add the three missing backup paths (SSH host keys, Docker volumes, Tailscale state), add a `pg_dump` pre-backup hook for PostgreSQL consistency, write the recovery runbook, and validate with a partial restore test.

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| restic | NixOS 25.11 default | Encrypted incremental backup | Already deployed, S3-compatible B2 backend |
| sops-nix | Latest (flake input) | Secrets management | Age key derived from SSH host key -- the critical chain |
| nixos-anywhere | Latest | OS provisioning | Already proven in Phase 2 deployment |
| disko | Latest (flake input) | Disk partitioning | Declarative disk layout for nixos-anywhere |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| pg_dump (from postgres:16-alpine) | 16.x | PostgreSQL logical dump | Pre-backup hook for claw-swap DB consistency |
| docker exec | System | Run commands in containers | Execute pg_dump inside claw-swap-db container |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Backing up raw Docker volumes | pg_dump only (no volume backup) | pg_dump is better for consistency but volumes capture non-DB state too (Caddy certs, parts data) |
| docker pause before backup | pg_dump pre-hook | pg_dump gives application-consistent dump; docker pause disrupts service availability |

## Architecture Patterns

### Current Backup Architecture
```
modules/restic.nix
  services.restic.backups.b2
    repository = "s3:s3.eu-central-003.backblazeb2.com/SyncBkp"
    passwordFile = config.sops.secrets."restic-password".path
    environmentFile = config.sops.templates."restic-b2-env".path
    paths = [
      "/data/projects/"      # Code repos, agent configs
      "/home/dangirsh/"      # User home, Syncthing, podman
      "/var/lib/hass/"       # Home Assistant state
    ]
    timerConfig.OnCalendar = "daily"
    pruneOpts: 7 daily, 5 weekly, 12 monthly
```

### Target Backup Architecture (After Phase 16)
```
modules/restic.nix
  services.restic.backups.b2
    paths = [
      "/data/projects/"           # (existing) Code repos, agent configs
      "/home/dangirsh/"           # (existing) User home, Syncthing, podman
      "/var/lib/hass/"            # (existing) Home Assistant state
      "/etc/ssh/ssh_host_ed25519_key"      # (NEW) sops-nix age key source
      "/etc/ssh/ssh_host_ed25519_key.pub"  # (NEW) public key for .sops.yaml
      "/var/lib/claw-swap/"       # (NEW) PostgreSQL data + Caddy certs/config
      "/var/lib/parts/"           # (NEW) Parts data + sessions
      "/var/lib/tailscale/"       # (NEW) Tailscale state (avoids re-auth)
    ]
    backupPrepareCommand = "docker exec claw-swap-db pg_dumpall ..."
    backupCleanupCommand = "rm /var/lib/claw-swap/pgdata/backup.sql"
```

### Recovery Architecture
```
Phase 1: Deploy NixOS from git (30 min)
  1. Pre-generate or restore SSH host key
  2. nixos-anywhere --extra-files (host key) --flake .#acfs root@<new-ip>
  3. Verify: SSH works, sops secrets decrypt

Phase 2: Restore stateful data from B2 (30 min)
  1. restic restore latest --target / --include /var/lib/claw-swap
  2. restic restore latest --target / --include /var/lib/parts
  3. restic restore latest --target / --include /var/lib/hass
  4. restic restore latest --target / --include /var/lib/tailscale
  5. restic restore latest --target / --include /data/projects
  6. restic restore latest --target / --include /home/dangirsh
  7. Verify: files exist, ownership correct

Phase 3: Re-auth and verify (30 min + buffer)
  1. Tailscale: generate key, update sops secret, nixos-rebuild
  2. Verify all services: docker ps, systemctl status, curl endpoints
```

### Pattern 1: NixOS Restic Pre-Backup Hook
**What:** Use `backupPrepareCommand` to run `pg_dump` before restic starts backing up files
**When to use:** When backing up raw database files that may be inconsistent during active writes
**Implementation:**
```nix
# Source: NixOS restic module (services/backup/restic.nix)
# backupPrepareCommand runs as preStart in the systemd service
# backupCleanupCommand runs as postStop
services.restic.backups.b2 = {
  backupPrepareCommand = ''
    # Dump PostgreSQL for application-consistent backup
    ${pkgs.docker}/bin/docker exec claw-swap-db \
      pg_dumpall -U claw -f /var/lib/postgresql/data/backup.sql \
      2>/dev/null || true
  '';
  backupCleanupCommand = ''
    # Clean up dump file after backup completes
    rm -f /var/lib/claw-swap/pgdata/backup.sql
  '';
};
```

### Pattern 2: SSH Host Key in Extra Files for nixos-anywhere
**What:** Pre-stage SSH host key so sops-nix can derive age key on first boot
**When to use:** During disaster recovery -- the host key is the root of the trust chain
**Implementation:**
```bash
# Create temporary directory structure for --extra-files
mkdir -p /tmp/host-keys/etc/ssh
# Copy host key from backup (restic restore or local backup)
cp /path/to/restored/ssh_host_ed25519_key /tmp/host-keys/etc/ssh/
cp /path/to/restored/ssh_host_ed25519_key.pub /tmp/host-keys/etc/ssh/
chmod 600 /tmp/host-keys/etc/ssh/ssh_host_ed25519_key
chmod 644 /tmp/host-keys/etc/ssh/ssh_host_ed25519_key.pub

nixos-anywhere --extra-files /tmp/host-keys \
  --flake .#acfs root@<target-ip>
```

### Anti-Patterns to Avoid
- **Backing up /nix/store:** Massive, fully reproducible from flake -- never back up
- **Backing up Docker overlay2 filesystem:** Use host-mounted volumes instead, they survive container recreation
- **Relying on Docker named volumes:** The claw-swap module uses host bind mounts (`/var/lib/claw-swap/pgdata:/var/lib/postgresql/data`), which is correct -- named volumes would require `docker cp` or volume backup plugins
- **Skipping pg_dump and backing up raw pgdata only:** Active PostgreSQL writes make raw file backups potentially inconsistent; pg_dump gives a clean logical dump
- **Generating new SSH host key during recovery:** This changes the age key, which means .sops.yaml needs updating and all secrets need re-encrypting -- a multi-hour detour

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Database backup consistency | Custom file locking | `pg_dumpall` via `backupPrepareCommand` | PostgreSQL guarantees consistency of logical dumps |
| Backup scheduling | Custom cron scripts | NixOS `services.restic.backups` with `timerConfig` | Built-in retry, persistence, systemd journal logging |
| Secrets re-encryption | Manual key rotation scripts | sops-nix age key derivation from SSH host key | Existing chain: restore host key -> sops works automatically |
| OS deployment | Manual install + configure | nixos-anywhere + flake | Proven, reproducible, < 30 minutes from scratch |

**Key insight:** The entire recovery procedure leverages existing infrastructure (nixos-anywhere, restic, sops-nix) -- no new tooling needed. The work is in closing backup gaps and documenting the exact sequence.

## Common Pitfalls

### Pitfall 1: SSH Host Key Not in Backup
**What goes wrong:** After VPS loss, nixos-anywhere generates a new SSH host key. The new key produces a different age public key. sops-nix cannot decrypt secrets because `.sops.yaml` references the old age key. All services fail to start because secrets are unavailable.
**Why it happens:** SSH host keys live in `/etc/ssh/` which is outside the standard backup paths (`/data/projects/`, `/home/dangirsh/`, `/var/lib/hass/`).
**How to avoid:** Explicitly add `/etc/ssh/ssh_host_ed25519_key` and `/etc/ssh/ssh_host_ed25519_key.pub` to restic backup paths. Use `--extra-files` during nixos-anywhere to inject the restored key before first boot.
**Warning signs:** After recovery, `systemctl status sops-nix-activation` fails, `/run/secrets/` is empty.

### Pitfall 2: Inconsistent PostgreSQL Backup
**What goes wrong:** Restic captures raw PostgreSQL data files (`/var/lib/claw-swap/pgdata/`) while the database is actively writing. The restored database has corruption or is in crash-recovery mode.
**Why it happens:** PostgreSQL maintains WAL (Write-Ahead Logging) state that requires consistent snapshots. File-level backups during writes can capture partial transactions.
**How to avoid:** Use `backupPrepareCommand` to run `pg_dumpall` before the backup. The dump file (`backup.sql`) is a consistent logical snapshot. Back up BOTH the dump file AND the raw data directory (belt-and-suspenders).
**Warning signs:** After restore, `docker logs claw-swap-db` shows "database system was not properly shut down" or corruption errors.

### Pitfall 3: Restic Restore Overwrites Active System
**What goes wrong:** Running `restic restore --target /` on a live system overwrites active configuration and state files, causing service disruption or data loss.
**Why it happens:** `restic restore` writes files to the target directory, potentially conflicting with running services.
**How to avoid:** During recovery on a fresh system, restore before starting services (or during the nixos-anywhere deployment window). For testing, always use a temporary target: `restic restore latest --target /tmp/restore-test/ --include /path`.
**Warning signs:** Services crash after restore, file permissions wrong, systemd journal shows access errors.

### Pitfall 4: Forgetting Tailscale Re-Auth After Fresh Deploy
**What goes wrong:** The server deploys successfully but is unreachable via Tailscale. The `sops.secrets."tailscale-authkey"` contains an expired or one-time-use auth key.
**Why it happens:** Tailscale auth keys expire. If `/var/lib/tailscale/` was not backed up or the backup is too old, the device needs fresh authentication.
**How to avoid:** Back up `/var/lib/tailscale/` to preserve device identity. If the backup is stale, document the exact steps to generate a fresh auth key and update the sops secret.
**Warning signs:** `systemctl status tailscaled` shows connected but `tailscale status` shows "not logged in" or "needs re-auth".

### Pitfall 5: Docker Volume Paths vs Docker Named Volumes
**What goes wrong:** Planner adds `/var/lib/docker/volumes/` to backup paths, but claw-swap uses host bind mounts not named volumes.
**Why it happens:** Confusion between Docker named volumes (in `/var/lib/docker/volumes/`) and host bind mounts (explicit paths like `/var/lib/claw-swap/pgdata`).
**How to avoid:** Audit actual container volume mounts. Claw-swap uses host bind mounts: `/var/lib/claw-swap/pgdata`, `/var/lib/claw-swap/caddy-data`, `/var/lib/claw-swap/caddy-config`. Parts uses: `/var/lib/parts/data`, `/var/lib/parts/sessions`. Back up these specific paths, NOT `/var/lib/docker/volumes/`.
**Warning signs:** Backup includes empty `/var/lib/docker/volumes/` directory while actual data in `/var/lib/claw-swap/` is not backed up.

## Code Examples

### Example 1: Updated restic.nix with All Backup Paths
```nix
# modules/restic.nix
{ config, pkgs, ... }: {
  services.restic.backups.b2 = {
    initialize = true;
    repository = "s3:s3.eu-central-003.backblazeb2.com/SyncBkp";
    passwordFile = config.sops.secrets."restic-password".path;
    environmentFile = config.sops.templates."restic-b2-env".path;

    paths = [
      "/data/projects/"
      "/home/dangirsh/"
      "/var/lib/hass/"
      # Phase 16 additions:
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/var/lib/claw-swap/"
      "/var/lib/parts/"
      "/var/lib/tailscale/"
    ];

    exclude = [
      "/nix/store"
      ".git/objects"
      "node_modules"
      "__pycache__"
      ".direnv"
      "result"
    ];

    # Pre-backup: dump PostgreSQL for consistency
    backupPrepareCommand = ''
      # pg_dumpall creates a consistent logical dump of all databases.
      # The dump file lands inside the pgdata bind mount, so restic
      # backs it up alongside the raw data files (belt-and-suspenders).
      ${pkgs.docker}/bin/docker exec claw-swap-db \
        pg_dumpall -U claw -f /var/lib/postgresql/data/backup.sql \
        2>/dev/null || true
    '';

    # Post-backup: clean up the dump file
    backupCleanupCommand = ''
      rm -f /var/lib/claw-swap/pgdata/backup.sql
    '';

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
    ];

    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
```

### Example 2: Restic Restore Commands for Recovery
```bash
# Set up restic environment (same as the NixOS service uses)
export AWS_ACCESS_KEY_ID="<from-sops-or-local-credential>"
export AWS_SECRET_ACCESS_KEY="<from-sops-or-local-credential>"
export RESTIC_REPOSITORY="s3:s3.eu-central-003.backblazeb2.com/SyncBkp"
export RESTIC_PASSWORD="<restic-repo-password>"

# Verify repository integrity first
restic check

# List available snapshots
restic snapshots

# Restore SSH host key (CRITICAL -- must be first)
restic restore latest --target / \
  --include /etc/ssh/ssh_host_ed25519_key \
  --include /etc/ssh/ssh_host_ed25519_key.pub

# Restore Docker volume data
restic restore latest --target / \
  --include /var/lib/claw-swap \
  --include /var/lib/parts

# Restore Tailscale state
restic restore latest --target / \
  --include /var/lib/tailscale

# Restore Home Assistant
restic restore latest --target / \
  --include /var/lib/hass

# Restore user data and projects
restic restore latest --target / \
  --include /data/projects \
  --include /home/dangirsh
```

### Example 3: Dry-Run Restore Verification
```bash
# Test restore to temporary directory (does NOT touch live system)
RESTORE_DIR="/tmp/restore-test"
mkdir -p "$RESTORE_DIR"

restic restore latest --target "$RESTORE_DIR"

# Spot-check critical files:
# 1. SSH host key exists and has correct permissions
ls -la "$RESTORE_DIR/etc/ssh/ssh_host_ed25519_key"

# 2. PostgreSQL data directory is populated
ls "$RESTORE_DIR/var/lib/claw-swap/pgdata/" | head

# 3. PostgreSQL dump file exists (if backup ran with hook)
ls -la "$RESTORE_DIR/var/lib/claw-swap/pgdata/backup.sql" 2>/dev/null

# 4. Parts data directory has content
ls "$RESTORE_DIR/var/lib/parts/data/"

# 5. Home Assistant database exists
ls "$RESTORE_DIR/var/lib/hass/home-assistant_v2.db" 2>/dev/null

# 6. Tailscale state directory exists
ls "$RESTORE_DIR/var/lib/tailscale/"

# 7. User home directory
ls "$RESTORE_DIR/home/dangirsh/.config/syncthing/config.xml" 2>/dev/null

# 8. Projects directory
ls "$RESTORE_DIR/data/projects/"

# Clean up
rm -rf "$RESTORE_DIR"
```

## Codebase Findings

### Current Stateful Path Inventory

Based on complete audit of all NixOS modules and flake inputs:

| Path | Service | Module | Currently Backed Up | Gap? |
|------|---------|--------|--------------------:|------|
| `/data/projects/` | Code repos, agent configs | `modules/repos.nix` | Yes | No |
| `/home/dangirsh/` | User home, Syncthing, podman | `modules/users.nix` | Yes | No |
| `/var/lib/hass/` | Home Assistant state/DB | `modules/home-assistant.nix` | Yes | No |
| `/etc/ssh/ssh_host_ed25519_key*` | sops-nix age key source | `modules/secrets.nix` | **No** | **CRITICAL** |
| `/var/lib/claw-swap/pgdata/` | PostgreSQL data (claw-swap) | claw-swap `nix/module.nix` | **No** | **HIGH** |
| `/var/lib/claw-swap/caddy-data/` | Caddy TLS certs | claw-swap `nix/module.nix` | **No** | **MEDIUM** |
| `/var/lib/claw-swap/caddy-config/` | Caddy config state | claw-swap `nix/module.nix` | **No** | **LOW** |
| `/var/lib/parts/data/` | Parts tools runtime data | parts `nix/module.nix` | **No** | **HIGH** |
| `/var/lib/parts/sessions/` | Parts agent sessions | parts `nix/module.nix` | **No** | **MEDIUM** |
| `/var/lib/parts/session-log.jsonl` | Parts agent session log | parts `nix/module.nix` | **No** | **LOW** |
| `/var/lib/tailscale/` | Tailscale device state | `modules/networking.nix` | **No** | **MEDIUM** |
| `/var/lib/prometheus/` | Metrics time-series | `modules/monitoring.nix` | No (SKIP per user) | Accepted |
| `/var/lib/fail2ban/` | Ban history | `modules/networking.nix` | No (SKIP per user) | Accepted |
| `/var/lib/syncthing/` | Syncthing index (under /home) | `modules/syncthing.nix` | Yes (via /home) | No |
| `/var/lib/esphome/` | ESPHome configs | `modules/home-assistant.nix` | **No** | **LOW** |

### Docker Volume Mapping (Critical Detail)
The CONTEXT says "ADD `/var/lib/docker/volumes/`" but claw-swap and parts do NOT use Docker named volumes. They use host bind mounts:

- **claw-swap-db:** `/var/lib/claw-swap/pgdata:/var/lib/postgresql/data`
- **claw-swap-caddy:** `/var/lib/claw-swap/caddy-data:/data`, `/var/lib/claw-swap/caddy-config:/config`
- **parts-tools:** `/var/lib/parts/data:/app/data`, `/home/dangirsh/Sync:/app/data/sync`
- **parts-agent:** `/var/lib/parts/sessions:/data/sessions`, `/var/lib/parts/session-log.jsonl:/data/session-log.jsonl`

**Recommendation:** Back up `/var/lib/claw-swap/` and `/var/lib/parts/` (the host mount roots) rather than `/var/lib/docker/volumes/`. The latter would be empty or contain only Docker internal state.

### sops-nix Trust Chain
```
/etc/ssh/ssh_host_ed25519_key
    |
    v  (ssh-to-age derives public age key)
age1jgn7pqqf4hvalqdrzqysxtnsydd5urnuczrfm86umr7yfr8pu5gqqet2t3
    |
    v  (referenced in .sops.yaml as &host_acfs)
secrets/acfs.yaml (encrypted with both admin + host keys)
    |
    v  (sops-nix decrypts at activation time)
/run/secrets/*  (15+ secrets: API keys, B2 creds, Tailscale auth, etc.)
    |
    v  (consumed by services)
Docker containers (env files), restic (credentials), Tailscale (auth key)
```

If the SSH host key is lost, the entire chain breaks. The admin key (`age1vma7w9...`) on the local workstation can still decrypt secrets.yaml, but sops-nix on the server cannot. Recovery requires either: (a) restoring the exact same host key, or (b) generating a new key, updating `.sops.yaml`, re-encrypting all secrets, and redeploying -- adding 30+ minutes to recovery.

### Key Sizing Estimates
Based on first backup snapshot: 407 files, 16.9 MiB raw, 5.1 MiB stored. With the additional paths:
- `/var/lib/claw-swap/pgdata/`: Typically 50-200 MB for a small PostgreSQL database
- `/var/lib/parts/`: Likely < 100 MB (session data, runtime state)
- `/var/lib/tailscale/`: < 5 MB (device identity and state)
- `/etc/ssh/ssh_host_ed25519_key*`: < 1 KB
- `/var/lib/esphome/`: < 10 MB

**Estimated total after Phase 16:** ~200-400 MiB raw, ~50-100 MiB stored (restic deduplication)

### Interaction with Phase 17
Phase 17 Plan 02 adds `.git/config` to the restic exclude list (to prevent backing up tokens leaked via the old clone mechanism). This is compatible with Phase 16 -- the `.git/config` exclude should remain even after Phase 16 adds new paths. Phase 16 should preserve existing excludes and only ADD new paths.

## Discretion Recommendations

### SSH Host Key Backup Pattern
**Recommendation: Use explicit file paths, not globs.**

```nix
paths = [
  "/etc/ssh/ssh_host_ed25519_key"
  "/etc/ssh/ssh_host_ed25519_key.pub"
];
```

Rationale: Globs like `/etc/ssh/ssh_host_*` would also capture RSA, ECDSA, and DSA keys (which are not needed for sops-nix) and potentially future keys. Only the ed25519 key pair is used for age derivation. Explicit paths are clearer and match the sops-nix configuration in `modules/secrets.nix` which references exactly `"/etc/ssh/ssh_host_ed25519_key"`.

### Pre/Post Backup Hooks
**Recommendation: Add pg_dump pre-hook and cleanup post-hook.**

The `backupPrepareCommand` approach is the right one because:
1. It runs as `preStart` in the systemd service (before restic backup starts)
2. `pg_dumpall` produces a complete, consistent SQL dump
3. The dump file lands inside `/var/lib/claw-swap/pgdata/` (the bind mount), so restic captures it automatically
4. `backupCleanupCommand` runs as `postStop` to remove the dump file
5. `|| true` on the docker exec ensures backup still proceeds if the DB container is stopped

**Do NOT use `docker pause`:** It would freeze all claw-swap containers (including Caddy serving HTTP traffic), creating visible downtime for a personal server backup. pg_dump achieves consistency without service disruption.

### Restore Verification Spot-Check Files
**Recommendation: Check these specific files during dry-run restore:**

1. `/etc/ssh/ssh_host_ed25519_key` -- Most critical file; must exist and be non-empty
2. `/var/lib/claw-swap/pgdata/PG_VERSION` -- Confirms PostgreSQL data directory is populated
3. `/var/lib/claw-swap/pgdata/backup.sql` -- Confirms pg_dump hook ran (may not exist if first backup after hook is added)
4. `/var/lib/parts/data/` -- Non-empty directory confirms parts runtime data
5. `/var/lib/tailscale/tailscaled.state` -- Tailscale device identity
6. `/var/lib/hass/home-assistant_v2.db` -- Home Assistant database
7. `/home/dangirsh/.config/syncthing/config.xml` -- Syncthing configuration
8. `/data/projects/neurosys/flake.nix` -- Confirms code repos are in backup

### Runbook Section Organization
**Recommendation:**

```
1. Prerequisites (what you need before starting)
2. Decision: Fresh Deploy vs IP Change
3. Phase 1: Deploy NixOS (nixos-anywhere)
   - Substep: Restore SSH host key from backup
4. Phase 2: Restore Stateful Data (restic)
   - Order matters: SSH key first, then services data
5. Phase 3: Manual Re-Authentication
   - Tailscale (always needed on fresh deploy)
   - Home Assistant (only if restore fails)
6. Phase 4: Verification Checklist
   - Service-by-service health checks
7. Appendix: Credential Locations
   - What's in git, what's in B2, what needs manual setup
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual rsync to external disk | restic to S3-compatible B2 | Phase 7 (2026-02-19) | Encrypted, deduplicated, versioned offsite backup |
| nixos-anywhere with new host key | nixos-anywhere with `--extra-files` restored key | Phase 2 deployment pattern | Preserves sops-nix trust chain on redeploy |
| Backing up Docker named volumes | Backing up host bind mount paths | claw-swap module design | Direct filesystem access, no Docker volume driver dependencies |

## Open Questions

1. **ESPHome state location**
   - What we know: ESPHome service is enabled in `modules/home-assistant.nix` with `services.esphome.enable = true`. NixOS typically stores ESPHome state in `/var/lib/esphome/`.
   - What's unclear: Whether ESPHome state is critical (device configs can likely be recreated). The CONTEXT.md did not mention ESPHome.
   - Recommendation: LOW priority -- do not add to backup. ESPHome configs are typically small YAML files that can be recreated. If the user wants them backed up, it is trivial to add `/var/lib/esphome/` to the paths list.

2. **Restic credentials during recovery**
   - What we know: The restic password and B2 credentials are in sops-nix secrets. During recovery, sops-nix may not be functional yet (if SSH host key isn't restored).
   - What's unclear: Does the recovery operator have these credentials stored separately?
   - Recommendation: The runbook must document that the recovery operator needs: (1) the restic repo password, (2) B2 API credentials -- stored locally on the admin workstation or in a separate password manager. The admin age key can decrypt `secrets/acfs.yaml` locally to extract these.

3. **Caddy TLS certificates**
   - What we know: Caddy stores TLS certs in `/var/lib/claw-swap/caddy-data/`. claw-swap uses Cloudflare origin certificates (not Let's Encrypt), stored as sops secrets (`claw-swap-cf-origin-cert`, `claw-swap-cf-origin-key`).
   - What's unclear: Whether the caddy-data directory contains anything beyond the injected origin certs.
   - Recommendation: Back up `/var/lib/claw-swap/` as a whole (includes caddy-data). Even if the only valuable data is the sops-managed origin certs, the directory is small and backing it up costs nothing.

## Sources

### Primary (HIGH confidence)
- `/data/projects/neurosys/modules/restic.nix` -- Current backup configuration
- `/data/projects/neurosys/modules/secrets.nix` -- sops-nix configuration with age key path
- `/data/projects/neurosys/.sops.yaml` -- Age key references (admin + host_acfs)
- `/data/projects/claw-swap/nix/module.nix` -- Docker volume mounts (host bind paths)
- `/data/projects/parts/nix/module.nix` -- Docker volume mounts (host bind paths)
- [NixOS restic module source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/backup/restic.nix) -- backupPrepareCommand/backupCleanupCommand implementation
- [services.restic.backups options](https://mynixos.com/nixpkgs/options/services.restic.backups.%3Cname%3E) -- Full option reference
- `.planning/quick/7-configure-restic-backups-to-backblaze-b2/7-SUMMARY.md` -- Deployment verification of existing backup

### Secondary (MEDIUM confidence)
- [Restic restore documentation](https://restic.readthedocs.io/en/latest/050_restore.html) -- --target and --include flags
- [NixOS restic wiki](https://wiki.nixos.org/wiki/Restic) -- General patterns
- [Automated backup of NixOS server](https://codewitchbella.com/blog/2024-nixos-automated-backup) -- backupPrepareCommand example

### Tertiary (LOW confidence)
- [restic-pg-dump-docker patterns](https://github.com/ixc/restic-pg-dump-docker) -- pg_dump before restic pattern (Docker-specific, adapted for NixOS)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools are already deployed and proven in this codebase
- Architecture: HIGH -- patterns derived directly from codebase audit (module sources, volume mappings)
- Pitfalls: HIGH -- based on documented deployment experience (Phase 2, Phase 10, Quick Task 7)
- Recovery procedure: MEDIUM -- nixos-anywhere + restic restore is proven individually but not tested as a combined DR flow
- Pre-backup hooks: MEDIUM -- `backupPrepareCommand` is well-documented in NixOS, pg_dump via docker exec is standard, but the specific command has not been tested on this server

**Research date:** 2026-02-19
**Valid until:** 2026-03-19 (30 days -- stable infrastructure, no fast-moving dependencies)
