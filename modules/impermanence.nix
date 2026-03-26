# modules/impermanence.nix
# @decision IMP-01: BTRFS subvolume rollback (not tmpfs) — server workloads need disk-backed root
#
# Modules add their own persist paths via the impermanence API, e.g.:
#   environment.persistence."/persist".directories = [ "/var/lib/myservice" ];
#   environment.persistence."/persist".files = [ "/var/lib/myservice/config.json" ];
# See networking.nix (SSH host keys), users.nix (root home), and agent-launcher.nix
# (agent state) for real examples.
{ ... }:
{
  # @decision IMP-05: Fix /etc permissions for sshd StrictModes.
  # OpenSSH StrictModes (enabled by default, confirmed in srvos) requires /etc, /etc/ssh,
  # and /etc/ssh/authorized_keys.d to be owned by root with no group/world write (mode 755
  # or stricter). On impermanent roots, bind-mount layering from nix-community/impermanence
  # can leave these directories with unexpected ownership or permissions, causing sshd to
  # reject authorized_keys files. This activation script runs after /etc is assembled and
  # ensures the permissions are correct. There are no security implications: 755 is the
  # standard permission for these directories on any Linux system.
  system.activationScripts.fixEtcPermissions = {
    text = ''
      chmod 755 /etc /etc/ssh /etc/ssh/authorized_keys.d 2>/dev/null || true
    '';
    deps = [ "etc" ];
  };

  # @decision IMP-06: setupSecrets must depend on persist-files.
  # sops-nix decrypts secrets using the SSH host key, which lives in /persist.
  # The persist-files activation must bind-mount it before setupSecrets runs.
  system.activationScripts.setupSecrets = {
    deps = [ "persist-files" ];
  };

  environment.persistence."/persist" = {
    hideMounts = true;

    directories = [
      "/var/lib/nixos" # UID/GID maps, declarative-users/groups state
      "/var/lib/systemd/timers" # Timer stamps for Persistent=true timers
      "/var/lib/systemd/timesync" # NTP clock file
      "/var/lib/private" # DynamicUser services
    ];

    files = [
      "/etc/machine-id" # Journal continuity across reboots
      "/var/lib/systemd/random-seed" # Kernel entropy pool seed
    ];
  };
}
