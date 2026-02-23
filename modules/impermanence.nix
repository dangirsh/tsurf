# modules/impermanence.nix
# @decision IMP-01: BTRFS subvolume rollback (not tmpfs) — server workloads need disk-backed root
# @decision IMP-02: Docker on own @docker subvolume (not impermanence bind-mount) — avoids overlay2 nested mount conflicts
# @decision IMP-03: Persist whole /home/dangirsh (not per-file) — simpler for server, covers Syncthing data + config
# @decision IMP-04: /var/lib/private covers DynamicUser services (ESPHome, future services)
{ config, lib, ... }: {
  environment.persistence."/persist" = {
    hideMounts = true;

    directories = [
      # --- Critical infrastructure ---
      "/etc/ssh"                           # SSH host keys — sops-nix age key derivation chain
      "/var/lib/nixos"                     # UID/GID maps, declarative-users/groups state

      # --- Network identity ---
      "/var/lib/tailscale"                 # Device keys, auth state, node identity

      # --- Systemd state ---
      "/var/lib/systemd/coredump"          # Core dumps (currently empty, but systemd expects it)
      "/var/lib/systemd/timers"            # Timer stamps for Persistent=true timers
      "/var/lib/systemd/timesync"          # NTP clock file
      "/var/lib/systemd/linger"            # User linger state for dangirsh

      # --- Service data ---
      "/var/lib/fail2ban"                  # Ban database (nice-to-have; regenerated if lost)
      "/var/lib/hass"                      # Home Assistant state, automations, history DB
      "/var/lib/private"                   # DynamicUser services: ESPHome (/var/lib/private/esphome)
      "/var/lib/prometheus2"               # 90-day metrics history
      "/var/lib/prometheus-node-exporter"  # Textfile collector .prom files (restic timestamp)
      "/var/lib/acme"                      # Let's Encrypt ACME certs + account keys (rate limit protection)
      "/var/lib/claw-swap"                 # PostgreSQL data
      "/var/lib/parts"                     # Session logs, runtime data

      # --- User data ---
      "/home/dangirsh"                     # Full home dir: .config/syncthing, Sync/, .claude.json, .bash_history, .ssh
      "/root"                              # .cache/restic, .config/nix, .ssh/known_hosts, .gitconfig, .docker

      # --- Code repos ---
      "/data"                              # /data/projects/ — claw-swap, parts, sandbox-test, .agent-audit
    ];

    files = [
      "/etc/machine-id"                    # Journal continuity across reboots
      "/var/lib/systemd/random-seed"       # Kernel entropy pool seed (32B, persisted across reboots)
    ];
  };
}
