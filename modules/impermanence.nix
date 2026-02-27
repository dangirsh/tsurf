# modules/impermanence.nix
# @decision IMP-01: BTRFS subvolume rollback (not tmpfs) — server workloads need disk-backed root
# @decision IMP-02: Docker on own @docker subvolume (not impermanence bind-mount) — avoids overlay2 nested mount conflicts
# @decision IMP-03: Persist whole /home/dangirsh (not per-file) — simpler for server, covers Syncthing data + config
# @decision IMP-04: /var/lib/private covers DynamicUser services (ESPHome, future services)
{ config, lib, ... }: {
  # @decision IMP-05: Fix /etc permissions for sshd strict mode checks.
  # Impermanence file bind-mounts create parent dirs as 775 (group-writable).
  # sshd rejects authorized_keys if any parent dir in the path is group-writable.
  # This activation script runs after /etc is populated but before services start.
  system.activationScripts.fixEtcPermissions = {
    text = ''
      chmod 755 /etc /etc/ssh 2>/dev/null || true
    '';
    deps = [ "etc" ];
  };

  environment.persistence."/persist" = {
    hideMounts = true;

    directories = [
      # --- Critical infrastructure ---
      # NOTE: /etc/ssh is NOT a persisted directory — only individual host key files are persisted (see files below).
      # Persisting the whole /etc/ssh directory hides NixOS-managed sshd_config symlink and breaks sshd startup.
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
      "/var/lib/mautrix-telegram"          # mautrix-telegram bridge state + registration.yaml
      "/var/lib/mautrix-whatsapp"          # mautrix-whatsapp bridge state + session DB
      "/var/lib/mautrix-signal"            # mautrix-signal bridge state + signal-cli data
      "/var/lib/prometheus2"               # 90-day metrics history
      "/var/lib/prometheus-node-exporter"  # Textfile collector .prom files (restic timestamp)
      "/var/lib/acme"                      # Let's Encrypt ACME certs + account keys (rate limit protection)
      "/var/lib/postgresql"                # PostgreSQL data (claw-swap DB)
      "/var/lib/parts"                     # Session logs, runtime data
      "/var/lib/spacebot"                  # Spacebot: config.toml, SQLite DB, LanceDB embeddings
      "/var/lib/openclaw-mark"               # OpenClaw gateway state — mark instance
      "/var/lib/openclaw-lou"                # OpenClaw gateway state — lou instance
      "/var/lib/openclaw-alexia"             # OpenClaw gateway state — alexia instance
      "/var/lib/openclaw-ari"                # OpenClaw gateway state — ari instance
      "/var/lib/openclaw-nginx-ssl"          # Self-signed TLS cert for mark's Tailscale HTTPS proxy

      # --- User data ---
      "/home/dangirsh"                     # Full home dir: .config/syncthing, Sync/, .claude.json, .bash_history, .ssh
      "/root"                              # .cache/restic, .config/nix, .ssh/known_hosts, .gitconfig, .docker

      # --- Code repos ---
      "/data"                              # /data/projects/ — claw-swap, parts, sandbox-test, .agent-audit
    ];

    files = [
      "/etc/machine-id"                    # Journal continuity across reboots
      "/var/lib/systemd/random-seed"       # Kernel entropy pool seed (32B, persisted across reboots)
      "/etc/ssh/ssh_host_ed25519_key"      # SSH host key — sops-nix age key derivation chain
      "/etc/ssh/ssh_host_ed25519_key.pub"  # SSH host key (public)
    ];
  };
}
