# modules/impermanence.nix
# @decision IMP-01: BTRFS subvolume rollback (not tmpfs) — server workloads need disk-backed root
# @decision IMP-04: /var/lib/private covers DynamicUser services
# @decision IMP-138-01: Persistence declarations are colocated with their owning module.
#   Each module declares its own environment.persistence."/persist" paths; the NixOS
#   module system merges them. This file keeps only activation scripts and system-level
#   paths that have no clear owning module. Run `nix run .#persistence-audit` for the
#   merged flat list.
{ ... }: {
  # @decision IMP-05: Fix /etc permissions for sshd strict mode checks.
  system.activationScripts.fixEtcPermissions = {
    text = ''
      chmod 755 /etc /etc/ssh /etc/ssh/authorized_keys.d 2>/dev/null || true
    '';
    deps = [ "etc" ];
  };

  # @decision IMP-06: setupSecrets must depend on persist-files.
  system.activationScripts.setupSecrets = {
    deps = [ "persist-files" ];
  };

  environment.persistence."/persist" = {
    hideMounts = true;

    directories = [
      "/var/lib/nixos"                     # UID/GID maps, declarative-users/groups state
      "/var/lib/systemd/coredump"          # Core dumps
      "/var/lib/systemd/timers"            # Timer stamps for Persistent=true timers
      "/var/lib/systemd/timesync"          # NTP clock file
      "/var/lib/systemd/linger"            # User linger state for dev
      "/var/lib/private"                   # DynamicUser services (dashboard, etc.)
    ];

    files = [
      "/etc/machine-id"                    # Journal continuity across reboots
      "/var/lib/systemd/random-seed"       # Kernel entropy pool seed
    ];
  };
}
