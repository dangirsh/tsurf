# Phase 21: Impermanence (Ephemeral Root) - Research

**Researched:** 2026-02-21
**Domain:** NixOS ephemeral root filesystem, BTRFS subvolume management, stateful path persistence
**Confidence:** HIGH (well-documented pattern, multiple verified reference implementations)

## Summary

Impermanence is a mature, well-documented NixOS pattern that wipes the root filesystem on every boot, forcing all stateful paths to be explicitly declared. The neurosys server currently runs ext4 on a single partition (`/dev/sda3`). Migration requires a full nixos-anywhere redeploy to switch to BTRFS with subvolumes (`root`, `nix`, `persist`, `log`). The root subvolume is reset to a blank state during initrd via `boot.initrd.postResumeCommands`, and the `nix-community/impermanence` module bind-mounts declared paths from `/persist` to their expected locations.

The live server audit identified 49GB of Docker data, 7GB Syncthing data, 97MB Prometheus metrics, 32MB Home Assistant state, and numerous service state directories that must be explicitly persisted. The migration is destructive (disk reprovisioning) and requires a full restic backup beforehand, nixos-anywhere redeploy with the new BTRFS disko config, then selective restoration of `/persist` contents from the backup.

**Primary recommendation:** Use BTRFS subvolume rollback (not tmpfs) for the ephemeral root, with `nix-community/impermanence` for persistence declarations. No LUKS encryption (VPS, not local disk). Separate `/var/lib/docker` onto its own BTRFS subvolume to avoid rollback complications with overlay2. Test in a local VM before touching production.

## Standard Stack

### Core
| Component | Version/Source | Purpose | Why Standard |
|-----------|---------------|---------|--------------|
| nix-community/impermanence | Latest (flake input) | `environment.persistence` declarations | De facto standard for NixOS impermanence; 1200+ stars, actively maintained |
| BTRFS | Kernel 6.12+ (in-tree) | Subvolume management, snapshots | Server workload needs disk-backed root (not tmpfs); BTRFS is the standard for NixOS impermanence |
| disko | Already in flake | Declarative BTRFS partitioning with subvolumes | Already used; supports BTRFS subvolumes natively |
| nixos-anywhere | Existing tooling | Disk reprovisioning | Only way to convert ext4 to BTRFS (destructive) |

### Supporting
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `boot.initrd.postResumeCommands` | BTRFS rollback script in initrd | Every boot -- deletes root subvolume, recreates from scratch |
| `fileSystems.*.neededForBoot` | Ensure persist/log mounted early | Critical for `/persist` and `/var/log` |
| restic (existing) | Pre-migration backup and post-migration `/persist`-only backups | Backup path changes from `/` to `/persist` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| BTRFS rollback | tmpfs root | tmpfs uses RAM (server has 96GB so feasible, but large builds/Docker would exhaust it); BTRFS is safer for server workloads |
| BTRFS rollback | ZFS snapshots | ZFS is more complex, larger footprint, license concerns; BTRFS is standard for NixOS impermanence |
| `postResumeCommands` | systemd initrd service | systemd initrd is cleaner but `postResumeCommands` is simpler and well-proven; no LUKS means no dependency ordering concerns |
| Blank snapshot rollback | Delete-and-recreate pattern | Both work; delete-and-recreate (no blank snapshot) is simpler and used by more recent guides |

## Architecture Patterns

### BTRFS Subvolume Layout

```
/dev/sda (GPT)
  sda1: 2M BIOS boot (EF02) -- GRUB legacy boot
  sda2: 512M ESP (EF00) -- /boot
  sda3: 100% BTRFS
    @root    -> /          (ephemeral, wiped every boot)
    @nix     -> /nix       (persistent, not backed up -- reproducible)
    @persist -> /persist   (persistent, backed up -- all stateful data)
    @log     -> /var/log   (persistent, backed up -- journal history)
    @docker  -> /var/lib/docker (persistent, partially backed up)
```

**Key decision: Separate `@docker` subvolume.** Docker's overlay2 creates nested mount points under `/var/lib/docker/overlay2/`. If Docker state lives inside `@root`, the initrd rollback script must handle these mounts. Putting Docker on its own subvolume avoids this entirely. This also means Docker state survives boot without an impermanence bind-mount -- it never gets wiped.

### Disko Configuration Pattern

```nix
# hosts/neurosys/disko-config.nix
{ ... }: {
  disko.devices = {
    disk.main = {
      device = "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "2M";
            type = "EF02";  # BIOS boot
          };
          ESP = {
            name = "ESP";
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/root" = {
                  mountpoint = "/";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "/persist" = {
                  mountpoint = "/persist";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "/log" = {
                  mountpoint = "/var/log";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "/docker" = {
                  mountpoint = "/var/lib/docker";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
              };
            };
          };
        };
      };
    };
  };

  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/log".neededForBoot = true;
}
```

### Initrd Rollback Script Pattern

```nix
# No LUKS, so postResumeCommands is simplest
boot.initrd.postResumeCommands = lib.mkAfter ''
  mkdir /btrfs_tmp
  mount /dev/disk/by-partlabel/disk-main-root /btrfs_tmp
  if [[ -e /btrfs_tmp/root ]]; then
    mkdir -p /btrfs_tmp/old_roots
    timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
    mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
  fi

  delete_subvolume_recursively() {
    IFS=$'\n'
    for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
      delete_subvolume_recursively "/btrfs_tmp/$i"
    done
    btrfs subvolume delete "$1"
  }

  for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
    delete_subvolume_recursively "$i"
  done

  btrfs subvolume create /btrfs_tmp/root
  umount /btrfs_tmp
'';
```

**This pattern (from multiple guides) moves old roots to timestamped dirs, deletes those older than 30 days, and creates a fresh root. The 30-day retention allows forensic inspection of old roots if needed.**

### Impermanence Module Integration

```nix
# In flake.nix inputs:
impermanence.url = "github:nix-community/impermanence";

# In module list:
impermanence.nixosModules.impermanence

# In a new modules/impermanence.nix:
{ inputs, lib, ... }: {
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/etc/ssh"
      "/var/lib/nixos"
      "/var/lib/tailscale"
      "/var/lib/systemd/coredump"
      "/var/lib/systemd/timers"
      "/var/lib/systemd/timesync"
      "/var/lib/systemd/linger"
      "/var/lib/fail2ban"
      "/var/lib/hass"
      "/var/lib/esphome"
      "/var/lib/prometheus2"
      "/var/lib/prometheus-node-exporter"
      "/var/lib/claw-swap"
      "/var/lib/parts"
      "/var/lib/private"
      "/var/lib/nftables"
      "/home/dangirsh"
      "/root"
      "/data"
    ];
    files = [
      "/etc/machine-id"
    ];
  };
}
```

### Anti-Patterns to Avoid
- **Persisting all of `/var/lib`:** Too broad. Defeats the purpose of impermanence. Persist only what services actually need.
- **Persisting `/etc/nixos`:** On a flake-based system, there is no `/etc/nixos` to persist (config lives in the git repo).
- **Using tmpfs for root on a server:** 96GB RAM sounds like enough, but Docker builds, large Nix builds, and Syncthing transfers can exhaust it. BTRFS is safer.
- **Forgetting `neededForBoot = true`:** Without this on `/persist` and `/var/log`, bind-mounts fail during early boot, causing hangs.
- **Persisting `/var/lib/docker` via impermanence bind-mount:** Docker's overlay2 creates nested mounts that conflict with bind-mounts. Use a separate BTRFS subvolume instead.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Persistence declarations | Manual bind-mount scripts in activation | `nix-community/impermanence` module | Handles permissions, ownership, parent dir creation, hideMounts |
| BTRFS rollback | Custom systemd service | `boot.initrd.postResumeCommands` | Standard pattern, runs before root mount, well-tested |
| Disk partitioning | Manual `parted`/`mkfs` | disko declarative config | Already in use, reproducible, works with nixos-anywhere |
| Stateful path discovery | Manual inspection | This research + iterative `diff` after reboots | The audit below covers the known paths; unknown paths surface as breakage after boot |

## Common Pitfalls

### Pitfall 1: Nested BTRFS Subvolumes Under Root
**What goes wrong:** `btrfs subvolume delete /mnt/root` fails because NixOS creates `/var/lib/portables` and `/var/lib/machines` as nested BTRFS subvolumes automatically (systemd-nspawn/machined).
**Why it happens:** systemd creates these subvolumes during normal operation.
**How to avoid:** The initrd script MUST recursively delete nested subvolumes before deleting the parent. The `delete_subvolume_recursively` function in the rollback script handles this.
**Warning signs:** Boot hangs at "deleting root subvolume" step.

### Pitfall 2: Docker overlay2 on BTRFS
**What goes wrong:** Docker's overlay2 storage driver works on BTRFS (kernel 5.19+, our kernel is 6.12), but overlay mounts inside `/var/lib/docker/overlay2/` create complexities if Docker state is on the root subvolume.
**Why it happens:** overlay2 creates active mount points that interfere with subvolume operations.
**How to avoid:** Put `/var/lib/docker` on a separate BTRFS subvolume (not inside `@root`). Docker state persists across boots without any impermanence bind-mount needed. Keep `overlay2` as the storage driver (don't switch to `btrfs` driver -- it was removed in Docker 23.0 and `overlay2` performs better).
**Warning signs:** Boot failures with "device busy" errors, or Docker failing to start after reboot.

### Pitfall 3: Missing `neededForBoot = true`
**What goes wrong:** System hangs during boot waiting for filesystem mount.
**Why it happens:** `/persist` and `/var/log` must be available before the impermanence module tries to create bind-mounts. Without `neededForBoot`, they mount too late.
**How to avoid:** Always set `fileSystems."/persist".neededForBoot = true;` and `fileSystems."/var/log".neededForBoot = true;`.
**Warning signs:** Boot timeout errors, "waiting for device" messages in console.

### Pitfall 4: sops-nix Age Key Path
**What goes wrong:** Secrets fail to decrypt after reboot because `/etc/ssh/ssh_host_ed25519_key` no longer exists (root was wiped).
**Why it happens:** The SSH host key lives on root filesystem. With impermanence, it's bind-mounted from `/persist/etc/ssh/ssh_host_ed25519_key`, but sops-nix's `age.sshKeyPaths` must point to the bind-mounted path which is still `/etc/ssh/ssh_host_ed25519_key` -- so this actually works transparently IF the impermanence bind-mount is in place.
**How to avoid:** Ensure `/etc/ssh` is in `environment.persistence."/persist".directories`. The sops-nix config (`age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"]`) does NOT need to change -- the bind-mount makes the file appear at its original path.
**Warning signs:** `sops-nix` activation errors in `systemctl status sops-nix`.

### Pitfall 5: /etc/machine-id Regeneration
**What goes wrong:** systemd journal history disconnects across reboots (new machine-id = new journal namespace).
**Why it happens:** `/etc/machine-id` is regenerated on every boot if not persisted.
**How to avoid:** Add `/etc/machine-id` to `environment.persistence."/persist".files`. The impermanence module handles this as a file (not directory) bind-mount.
**Warning signs:** `journalctl --boot=-1` shows no logs from previous boot.

### Pitfall 6: Forgetting a Stateful Path
**What goes wrong:** A service loses state after reboot (e.g., Tailscale logs out, fail2ban loses ban database, Syncthing loses device certificates).
**Why it happens:** The service writes state to a path not listed in `environment.persistence`.
**How to avoid:** Use the exhaustive audit below. After first boot with impermanence, do a `diff` of running state vs blank root to catch anything missed.
**Warning signs:** Service errors after reboot, re-authentication prompts, missing data.

### Pitfall 7: Home Directory Persistence with home-manager
**What goes wrong:** home-manager symlinks break because the target home directory is empty.
**Why it happens:** `/home/dangirsh` is on the ephemeral root and gets wiped.
**How to avoid:** Persist `/home/dangirsh` as a whole directory in `environment.persistence`. Do NOT use the `home.persistence` sub-module (it's designed for per-file granularity in desktop environments). For a server, persisting the whole home dir is simpler and sufficient.
**Warning signs:** Broken symlinks after boot, home-manager activation failures.

### Pitfall 8: Deploy Lock Files Lost on Reboot
**What goes wrong:** Remote deploy lock at `/var/lock/neurosys-deploy.lock` disappears (which is actually correct -- locks should not persist). But if the server reboots mid-deploy, the lock is already gone.
**Why it happens:** `/var/lock` is on tmpfs (already ephemeral even without impermanence). No change needed.
**How to avoid:** No action needed. This is already correct behavior.

## Live Server State Audit

### Current Disk Layout (BEFORE migration)

```
/dev/sda (GPT, 350 GB NVMe)
  sda1: 2M   BIOS boot (EF02)
  sda2: 512M ESP (vfat) -> /boot
  sda3: 343G ext4 -> / (and /nix/store as ro bind mount)

Filesystem: ext4
No swap configured
No BTRFS, no LVM, no LUKS
```

### Running Services (27 total)

```
dbus, docker, docker-claw-swap-{app,caddy,db}, docker-parts-{agent,tools},
esphome, fail2ban, getty@tty1, home-assistant, homepage-dashboard,
nix-daemon, nscd, prometheus-node-exporter, prometheus, sshd, syncthing,
systemd-journald, systemd-logind, systemd-machined, systemd-oomd,
systemd-timesyncd, systemd-udevd, tailscaled, user@0, user@1000
```

### Service-by-Service Persistence Analysis

| Service | State Path | Size | Persist? | Notes |
|---------|-----------|------|----------|-------|
| SSH host keys | `/etc/ssh/ssh_host_ed25519_key`, `ssh_host_rsa_key` (+ .pub) | 28K | YES (critical) | sops-nix age key derivation depends on ed25519 key |
| machine-id | `/etc/machine-id` | 33B | YES | Journal continuity, service identity |
| Tailscale | `/var/lib/tailscale/` | 40K | YES (critical) | Node identity, device keys, auth state |
| Docker engine | `/var/lib/docker/` | 49G | Own subvolume | overlay2 (48G), images (165M), containers (192K), network (92K) |
| Docker: claw-swap | `/var/lib/claw-swap/` (pgdata, caddy-data, caddy-config) | 47M | YES | PostgreSQL data, Caddy TLS state |
| Docker: parts | `/var/lib/parts/` (data, sessions, session-log.jsonl) | 1.4M | YES | Session logs, runtime data |
| Prometheus | `/var/lib/prometheus2/` | 97M | YES | 90-day metrics history |
| prometheus-node-exporter | `/var/lib/prometheus-node-exporter/` | 8K | YES | Textfile collector `.prom` files |
| Home Assistant | `/var/lib/hass/` | 32M | YES | Device configs, automations, history DB |
| ESPHome | `/var/lib/esphome/` (via `/var/lib/private/esphome`) | 1.6M | YES | Device configs |
| fail2ban | `/var/lib/fail2ban/` | 144K | YES (nice-to-have) | Ban database; not critical, regenerated |
| Syncthing | `/home/dangirsh/.config/syncthing/` | 27M | YES | Device certs, sync state (runs as user dangirsh) |
| Syncthing data | `/home/dangirsh/Sync/` | 6.9G | YES | Synced files |
| systemd timers | `/var/lib/systemd/timers/` | stamps | YES | Timer stamps for Persistent=true timers |
| systemd timesync | `/var/lib/systemd/timesync/` | clock file | YES | NTP clock file |
| systemd linger | `/var/lib/systemd/linger/` | empty files | YES | User linger state for dangirsh |
| systemd random-seed | `/var/lib/systemd/random-seed` | 32B | YES | Entropy pool |
| systemd coredump | `/var/lib/systemd/coredump/` | empty | Optional | Core dumps (currently empty) |
| NixOS UID/GID maps | `/var/lib/nixos/` | 24K | YES (critical) | uid-map, gid-map, declarative-users, declarative-groups |
| nftables | `/var/lib/nftables/` | 8K | Optional | Saved ruleset (regenerated by NixOS activation) |
| Homepage dashboard | `/var/lib/homepage-dashboard/` (via private) | empty | NO | Stateless; config is declarative in Nix |
| Grafana (orphan) | `/var/lib/grafana/` | 52M | NO | Removed service, can be cleaned up |
| Alertmanager (orphan) | `/var/lib/private/alertmanager/` | empty | NO | Removed service |
| ntfy-sh (orphan) | `/var/lib/private/ntfy-sh/` | small | NO | Removed service |
| User home: dangirsh | `/home/dangirsh/` | 7G | YES | .claude.json, .bash_history, .cache, .local, .ssh, Sync |
| User home: root | `/root/` | small | YES | .cache/restic, .config/nix, .ssh/known_hosts, .gitconfig, .docker |
| Code repos | `/data/projects/` | 674M | YES | claw-swap, parts, sandbox-test, .agent-audit |
| Agent audit log | `/data/projects/.agent-audit/` | small | YES | spawn.log |
| CASS indexer | `/home/dangirsh/.local/share/coding-agent-search/` | 148K | YES | SQLite DB + tantivy index |
| Journal logs | `/var/log/journal/` | 215M | Own subvolume | Persisted via `/var/log` subvolume |
| Nix profiles | `/nix/var/nix/profiles/` | links | On @nix subvolume | System generations; survives via @nix subvolume |
| Restic cache | `/root/.cache/restic/` | 344K | Optional | Rebuilt automatically |

### Docker Container Bind Mounts (verified from live server)

| Container | Host Mount | Container Mount | Mode |
|-----------|-----------|----------------|------|
| parts-agent | `/var/lib/parts/sessions` | `/data/sessions` | rw |
| parts-agent | `/var/lib/parts/session-log.jsonl` | `/data/session-log.jsonl` | rw |
| parts-tools | `/var/lib/parts/data` | `/app/data` | rw |
| parts-tools | `/home/dangirsh/Sync` | `/app/data/sync` | rw |
| parts-tools | `/data/projects/parts` | `/app/source` | ro |
| claw-swap-caddy | `/run/secrets/claw-swap-cf-origin-cert` | `/etc/caddy/tls/cert.pem` | ro |
| claw-swap-caddy | `/run/secrets/claw-swap-cf-origin-key` | `/etc/caddy/tls/key.pem` | ro |
| claw-swap-caddy | `/var/lib/claw-swap/caddy-data` | `/data` | rw |
| claw-swap-caddy | `/var/lib/claw-swap/caddy-config` | `/config` | rw |
| claw-swap-caddy | Nix store Caddyfile | `/etc/caddy/Caddyfile` | ro |
| claw-swap-db | `/var/lib/claw-swap/pgdata` | `/var/lib/postgresql/data` | rw |
| claw-swap-app | (none) | - | - |

**All `/run/secrets/*` mounts are in ramfs -- no persistence needed (regenerated by sops-nix on each boot).**
**All Nix store mounts are on the `@nix` subvolume -- no persistence needed.**

### Paths That Do NOT Need Persistence (ephemeral by design)

| Path | Why Ephemeral |
|------|--------------|
| `/run/` | tmpfs, regenerated every boot |
| `/run/secrets/`, `/run/secrets.d/` | ramfs, sops-nix regenerates on activation |
| `/tmp/` | Already ephemeral |
| `/var/cache/` | Caches, rebuilt automatically |
| `/var/lock/` | Lock files, ephemeral by design |
| `/etc/resolv.conf` | Symlink to `/etc/static/`, regenerated |
| `/etc/passwd`, `/etc/group`, `/etc/shadow` | Regenerated by NixOS with `mutableUsers = false` |
| `/etc/nix/`, `/etc/static/` | Nix store links, regenerated |
| `/var/lib/homepage-dashboard/` | Stateless service |
| `/var/lib/grafana/` | Orphan from removed service |
| `/var/lib/private/alertmanager/` | Orphan from removed service |
| `/var/lib/private/ntfy-sh/` | Orphan from removed service |

## Migration Strategy

### Phase 1: Preparation (Before Touching Production)

1. **Full restic backup verified:** `restic check` + `restic snapshots` confirm latest is < 24h old
2. **Local VM test:** Build the new config with BTRFS+impermanence in a QEMU VM, verify all services start, reboot, verify persistence
3. **Extract SSH host key from backup:** `restic restore latest --target /tmp/host-keys --include /etc/ssh/ssh_host_ed25519_key`
4. **Prepare `/persist` seed data:** Script to copy current stateful paths into `/persist/` layout
5. **Commit all config changes:** New disko-config.nix, impermanence module, initrd rollback script, updated restic paths

### Phase 2: Destructive Migration (nixos-anywhere)

1. **nixos-anywhere redeploy:**
   ```bash
   nixos-anywhere --extra-files /tmp/host-keys --flake .#neurosys root@161.97.74.121
   ```
   This wipes the disk, creates BTRFS subvolumes via disko, installs NixOS.

2. **Static IP is critical:** Contabo VPS uses static IP (no DHCP). The existing `hosts/neurosys/default.nix` already declares `161.97.74.121` -- no change needed. nixos-anywhere uses the IP directly (not Tailscale).

3. **SSH host key injection via `--extra-files`:** The pre-generated SSH host key goes into `/etc/ssh/` so sops-nix can derive the age key and decrypt secrets on first boot.

### Phase 3: State Restoration

1. **sops-nix decrypts secrets automatically** (SSH host key is in place from --extra-files)
2. **Restore stateful data from restic:**
   ```bash
   # On the new server, after first boot:
   source /run/secrets/rendered/restic-b2-env
   export RESTIC_PASSWORD=$(cat /run/secrets/restic-password)
   export RESTIC_REPOSITORY="s3:s3.eu-central-003.backblazeb2.com/SyncBkp"

   # Restore to /persist layout
   restic restore latest --target /tmp/restore

   # Copy stateful paths to /persist
   cp -a /tmp/restore/etc/ssh/* /persist/etc/ssh/
   cp -a /tmp/restore/etc/machine-id /persist/etc/machine-id
   cp -a /tmp/restore/var/lib/tailscale /persist/var/lib/tailscale
   cp -a /tmp/restore/var/lib/claw-swap /persist/var/lib/claw-swap
   cp -a /tmp/restore/var/lib/parts /persist/var/lib/parts
   cp -a /tmp/restore/var/lib/hass /persist/var/lib/hass
   cp -a /tmp/restore/var/lib/esphome /persist/var/lib/esphome
   cp -a /tmp/restore/var/lib/prometheus2 /persist/var/lib/prometheus2
   cp -a /tmp/restore/var/lib/prometheus-node-exporter /persist/var/lib/prometheus-node-exporter
   cp -a /tmp/restore/var/lib/fail2ban /persist/var/lib/fail2ban
   cp -a /tmp/restore/var/lib/nixos /persist/var/lib/nixos
   cp -a /tmp/restore/var/lib/systemd/timers /persist/var/lib/systemd/timers
   cp -a /tmp/restore/var/lib/systemd/timesync /persist/var/lib/systemd/timesync
   cp -a /tmp/restore/var/lib/systemd/linger /persist/var/lib/systemd/linger
   cp -a /tmp/restore/var/lib/systemd/random-seed /persist/var/lib/systemd/random-seed
   cp -a /tmp/restore/home/dangirsh /persist/home/dangirsh
   cp -a /tmp/restore/root /persist/root
   mkdir -p /persist/data
   cp -a /tmp/restore/data/projects /persist/data/projects

   # Docker data goes to its own subvolume (already mounted at /var/lib/docker)
   # Restore Docker non-overlay2 state:
   cp -a /tmp/restore/var/lib/docker/image /var/lib/docker/image
   cp -a /tmp/restore/var/lib/docker/containers /var/lib/docker/containers
   cp -a /tmp/restore/var/lib/docker/network /var/lib/docker/network
   cp -a /tmp/restore/var/lib/docker/volumes /var/lib/docker/volumes

   # Reboot to activate bind-mounts
   reboot
   ```

3. **Docker images rebuild automatically** from the NixOS activation (OCI image declarations in parts and claw-swap modules). The overlay2 layers do NOT need to be restored.

### Phase 4: Verification

Same checklist as recovery runbook Phase 4, plus:
- Reboot again and verify all services survive the second boot
- Check `journalctl --boot=-1` shows previous boot logs (machine-id persisted)
- Verify Tailscale reconnects automatically (state persisted)
- Verify all Docker containers start (bind mount data persisted)

### Rollback Plan

If impermanence breaks the server:
1. Have Contabo rescue console access ready
2. From rescue: mount BTRFS, examine `/persist` for state
3. Worst case: nixos-anywhere redeploy with the OLD config (ext4 disko) + restic restore = back to pre-migration state within 2 hours (existing DR runbook)

## Code Examples

### New Flake Input

```nix
# In flake.nix inputs:
impermanence = {
  url = "github:nix-community/impermanence";
};
```

No `inputs.nixpkgs.follows` needed -- impermanence is a pure Nix module with no binary dependencies. Optionally strip dev inputs:
```nix
impermanence.inputs.nixpkgs.follows = "";
```

### Module Integration

```nix
# In flake.nix modules list:
impermanence.nixosModules.impermanence
```

### sops-nix with Impermanence (No Change Needed)

```nix
# modules/secrets.nix -- UNCHANGED
sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
# This works because impermanence bind-mounts /persist/etc/ssh -> /etc/ssh
```

### Restic Backup Path Change

```nix
# modules/restic.nix -- CHANGE paths from ["/"] to ["/persist"]
services.restic.backups.b2 = {
  paths = [ "/persist" ];
  # Remove --one-file-system (persist is one subvolume)
  # Remove /nix exclusion (not under /persist)
  # Keep Docker-specific exclusions for the /var/lib/docker subvolume
  extraBackupArgs = [
    "--exclude-caches"
    "--exclude-if-present" ".nobackup"
  ];
  exclude = [
    # Docker ephemeral layers (on Docker subvolume, not backed up by default
    # since it's not under /persist. But add explicit excludes in case of
    # future path changes)
    "**/.cache"
    ".git/objects"
    ".git/config"
    "node_modules"
    "__pycache__"
    ".direnv"
    "result"
  ];
};
```

### Updated Restic With Docker Subvolume Backup

If Docker bind mount data needs backing up separately (claw-swap pgdata, parts data), those are persisted via impermanence under `/persist/var/lib/claw-swap` and `/persist/var/lib/parts` -- they are included in the `/persist` backup automatically.

The Docker subvolume (`/var/lib/docker`) itself does NOT need full backup. Images are pulled, overlay2 layers are rebuilt. Only the bind-mount directories matter, and those are under `/persist`.

### Boot Configuration Update

```nix
# modules/boot.nix or hosts/neurosys/default.nix
boot.initrd.supportedFilesystems = [ "btrfs" ];
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ZFS snapshots (Graham Christensen's blog, 2020) | BTRFS subvolumes (standard in 2024+) | ~2023 | BTRFS is simpler, lighter, better NixOS/disko integration |
| `boot.initrd.postDeviceCommands` | `boot.initrd.postResumeCommands` | NixOS 23.11+ | postResumeCommands runs after resume from hibernation, more reliable |
| Blank snapshot rollback | Delete-and-recreate (no snapshot needed) | ~2024 | Simpler, no need to maintain a blank snapshot; just create fresh subvolume |
| Docker `btrfs` storage driver | Docker `overlay2` on BTRFS | Docker 23.0 (2023) | Docker removed btrfs driver; overlay2 works fine on BTRFS with modern kernels |
| `boot.initrd.systemd` rollback service | `postResumeCommands` for non-LUKS | Ongoing | systemd approach is cleaner for LUKS (dependency ordering); postResumeCommands is simpler for non-LUKS |

## Deploy-rs Interaction

**NixOS system profiles are stored in `/nix/var/nix/profiles/system`** -- this is on the `@nix` subvolume, NOT on `@root`. Therefore:

- System generations survive root wipes (they're on `@nix`)
- deploy-rs magic rollback works correctly: if a deploy fails and rolls back, the rollback target (previous generation) is still available in `/nix/var/nix/profiles/system`
- `nixos-rebuild switch --rollback` works correctly
- The deploy-rs canary mechanism (inotify + confirmation) is unaffected by impermanence since it operates in `/run/` (tmpfs)
- **No changes needed to deploy-rs configuration or scripts/deploy.sh**

**One consideration:** After a deploy that changes the impermanence persistence list (adds/removes paths), the bind-mounts change on the next boot but NOT during the current session. This means a deploy-rs activation that adds a new persistence path will work (the directory exists on root), but the persistence will only take effect after reboot. This is fine -- activation creates the directory, and impermanence ensures it persists after reboot.

## Open Questions

1. **Docker subvolume vs. bind-mount approach**
   - What we know: A separate `@docker` subvolume avoids overlay2/bind-mount conflicts and is simpler
   - What's unclear: Whether disko handles this cleanly during nixos-anywhere, or if Docker needs to be pre-created
   - Recommendation: Test in VM first. If disko creates the subvolume and mounts it at `/var/lib/docker`, Docker should just work. HIGH confidence this works.

2. **ESPHome private directory**
   - What we know: ESPHome uses DynamicUser=true (systemd), placing state in `/var/lib/private/esphome/`
   - What's unclear: Whether persisting `/var/lib/private/esphome` works with impermanence or needs special handling due to DynamicUser
   - Recommendation: Persist `/var/lib/private` as a directory (covers esphome and any future DynamicUser services). Test after migration.

3. **Syncthing configDir on impermanence**
   - What we know: Syncthing config is at `/home/dangirsh/.config/syncthing/` (27MB), data at `/home/dangirsh/Sync/` (6.9GB)
   - What's unclear: If persisting all of `/home/dangirsh` is sufficient or if Syncthing needs special handling
   - Recommendation: Persisting `/home/dangirsh` as a directory covers both config and data. HIGH confidence.

4. **Contabo kernel BTRFS support**
   - What we know: `modprobe btrfs` succeeds on the live server (kernel 6.12.69). BTRFS is in-tree.
   - What's unclear: Whether Contabo's kernel has any BTRFS-related patches or limitations
   - Recommendation: Verified working. HIGH confidence. The initrd needs `boot.initrd.supportedFilesystems = ["btrfs"]` to load the module early.

5. **Home-manager activation order with impermanence**
   - What we know: home-manager activates after system activation; impermanence bind-mounts happen during boot
   - What's unclear: Whether home-manager's activation scripts run correctly on bind-mounted home dirs
   - Recommendation: Should work because bind-mount makes `/persist/home/dangirsh` appear at `/home/dangirsh` before home-manager runs. Test in VM.

## Sources

### Primary (HIGH confidence)
- [nix-community/impermanence GitHub README](https://github.com/nix-community/impermanence) -- module API, options, examples
- [nix-community/disko BTRFS subvolumes example](https://github.com/nix-community/disko/blob/master/example/btrfs-subvolumes.nix) -- official disko BTRFS config
- [Docker docs: OverlayFS storage driver](https://docs.docker.com/engine/storage/drivers/overlayfs-driver/) -- overlay2 on BTRFS support
- [Docker docs: Select a storage driver](https://docs.docker.com/engine/storage/drivers/select-storage-driver/) -- overlay2 is recommended on BTRFS

### Secondary (MEDIUM confidence)
- [notashelf.dev: Full Disk Encryption and Impermanence](https://notashelf.dev/posts/impermanence) -- BTRFS layout, initrd rollback service, persistence examples
- [guekka.github.io: NixOS as a server, part 1](https://guekka.github.io/nixos-server-1/) -- server-focused impermanence guide
- [tsawyer87: BTRFS Impermanence](https://tsawyer87.github.io/posts/btrfs_impermanence/) -- delete-and-recreate rollback pattern
- [NixOS Discourse: Setting up Impermanence with disko and BTRFS](https://discourse.nixos.org/t/setting-up-impermanence-with-disko-and-luks-with-btrfs-and-also-nuking-everything-on-reboot/69423) -- complete disko+impermanence config
- [NixOS Discourse: OCI containers and impermanence](https://discourse.nixos.org/t/oci-containers-and-impermanence/50190) -- Docker persistence patterns
- [NixOS Discourse: Impermanence /etc/machine-id](https://discourse.nixos.org/t/impermanence-a-file-already-exists-at-etc-machine-id/20267) -- machine-id gotchas
- [Misterio77/nix-config](https://github.com/Misterio77/nix-config) -- reference impermanence + BTRFS + sops-nix + deploy-rs config
- [mich-murphy.com: NixOS Impermanence](https://mich-murphy.com/nixos-impermanence/) -- Tailscale persistence fix
- [lantian.pub: NixOS Stateless OS](https://lantian.pub/en/article/modify-computer/nixos-impermanence.lantian/) -- nix-daemon TMPDIR, server patterns

### Tertiary (LOW confidence)
- [mt-caret.github.io: Opt-in State on NixOS](https://mt-caret.github.io/blog/posts/2020-06-29-optin-state.html) -- original BTRFS impermanence blog post (2020, pattern still valid)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- impermanence + BTRFS is the dominant pattern, well-documented
- Architecture: HIGH -- disko BTRFS config, initrd rollback script, persistence declarations all have multiple verified sources
- Pitfalls: HIGH -- nested subvolumes, Docker overlay2, neededForBoot, sops-nix key path all documented in multiple sources
- Migration strategy: MEDIUM -- nixos-anywhere + restic restore is proven for this server, but combined with impermanence is untested
- Service persistence paths: HIGH -- exhaustive live server audit with `du`, `ls`, `docker inspect`

**Research date:** 2026-02-21
**Valid until:** 2026-04-21 (stable domain, slow-moving ecosystem)
