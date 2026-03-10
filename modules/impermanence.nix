# modules/impermanence.nix
# @decision IMP-01: BTRFS subvolume rollback (not tmpfs) — server workloads need disk-backed root
# @decision IMP-02: Docker on own @docker subvolume (not impermanence bind-mount) — avoids overlay2 nested mount conflicts
# @decision IMP-03: Persist whole /home/dev (not per-file) — simpler for server, covers Syncthing data + config
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
      "/var/lib/fail2ban"                  # Ban database (regenerated if lost)
      "/var/lib/private"                   # DynamicUser services (dashboard, etc.)
      "/var/lib/hass"                      # Home Assistant: .storage/, config-repo/, integrations
      "/var/lib/ssh-canary"               # SSH canary failure counter + last-rollback timestamp

      # --- User data ---
      "/home/dev"                       # Full home dir: .config/syncthing, Sync/, .claude.json, .bash_history, .ssh
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
