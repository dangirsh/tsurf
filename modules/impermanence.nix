# modules/impermanence.nix
# @decision IMP-01: BTRFS subvolume rollback (not tmpfs) — server workloads need disk-backed root
# @decision IMP-02: Docker on own @docker subvolume (not impermanence bind-mount) — avoids overlay2 nested mount conflicts
# @decision IMP-03: Explicit per-path home persistence — maximally transparent about
#   what state survives reboots. New tools may require adding paths; run
#   `find /home/dev -maxdepth 2 -newer /home/dev/.bash_history -type d` to discover.
# @decision IMP-04: /var/lib/private covers DynamicUser services
{ config, lib, ... }: {
  # @decision IMP-05: Fix /etc permissions for sshd strict mode checks.
  # Impermanence file bind-mounts create parent dirs as 775 (group-writable).
  # sshd rejects authorized_keys if any parent dir in the path is group-writable.
  # This activation script runs after /etc is populated but before services start.
  # Also fix authorized_keys.d — created inside /etc/ssh after bind-mount sets 775,
  # so it inherits group-writable, causing sshd StrictModes to reject all keys in it.
  system.activationScripts.fixEtcPermissions = {
    text = ''
      chmod 755 /etc /etc/ssh /etc/ssh/authorized_keys.d 2>/dev/null || true
    '';
    deps = [ "etc" ];
  };

  # @decision IMP-06: setupSecrets must depend on persist-files.
  # @rationale: sops-nix derives the age key from /etc/ssh/ssh_host_ed25519_key.
  #   Impermanence bind-mounts this file via the persist-files activation script.
  #   Without this ordering, setupSecrets runs before persist-files, the SSH host
  #   key doesn't exist yet, age key import fails with "0 successful groups required,
  #   got 0", and all services depending on /run/secrets fail on hard reboot.
  #   Adding deps here merges with sops-nix's setupSecrets definition (text fields
  #   concatenate, dep lists append) — no text duplication, just ordering enforcement.
  system.activationScripts.setupSecrets = {
    deps = [ "persist-files" ];
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
      "/var/lib/systemd/linger"            # User linger state for dev

      # --- Service data ---
      # Add paths for your services here. Example:
      #   "/var/lib/my-service"  # My custom service state
      "/var/lib/private"                   # DynamicUser services (dashboard, etc.)
      "/var/lib/sshd-liveness-check"      # sshd liveness check failure counter + last-rollback timestamp

      # --- User home (explicit paths instead of whole /home/dev) ---
      # @decision IMP-03-R: Explicit home persistence — every stateful path is listed.
      #   Occasionally requires adding new paths when new tools are adopted.
      #   Run `diff <(find /persist/home/dev -maxdepth 2 -type d | sort) <(find /home/dev -maxdepth 2 -type d | sort)`
      #   after a session to discover paths that may need persisting.
      "/home/dev/.ssh"                    # SSH keys and known_hosts
      "/home/dev/.config/syncthing"       # Syncthing device keys and config
      "/home/dev/Sync"                    # Syncthing shared folders
      "/home/dev/.claude"                 # Claude Code state
      "/home/dev/.config/claude"          # Claude Code config
      "/home/dev/.config/git"             # Git config (global ignore, etc.)
      "/home/dev/.local/share/direnv"     # Direnv allowed envs

      # --- Agent user home (no .ssh — agent has no SSH access) ---
      # @decision IMP-115-01: Agent home persisted separately from operator home.
      "/home/agent/.claude"
      "/home/agent/.config/claude"
      "/home/agent/.config/git"
      "/home/agent/.local/share/direnv"

      # --- Root home (explicit paths instead of whole /root) ---
      "/root/.ssh"                        # SSH keys, known_hosts, authorized_keys
      "/root/.cache/restic"               # Restic chunk cache (performance)
      "/root/.config/nix"                 # Nix config/registries
      "/root/.docker"                     # Docker credentials/config

      # --- Project data ---
      "/data/projects"                    # Code repos and agent state
    ];

    files = [
      "/etc/machine-id"                    # Journal continuity across reboots
      "/var/lib/systemd/random-seed"       # Kernel entropy pool seed (32B, persisted across reboots)
      "/etc/ssh/ssh_host_ed25519_key"      # SSH host key — sops-nix age key derivation chain
      "/etc/ssh/ssh_host_ed25519_key.pub"  # SSH host key (public)
      "/home/dev/.gitconfig"               # Git identity
      "/home/dev/.bash_history"            # Shell history
      "/home/agent/.gitconfig"             # Agent git identity
      "/home/agent/.bash_history"          # Agent shell history
      "/root/.gitconfig"                   # Root git identity
    ];
  };
}
