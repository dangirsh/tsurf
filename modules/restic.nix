# modules/restic.nix
# @decision RESTIC-01: S3-compatible B2 backend (not native B2 — restic's B2 connector is unreliable per STACK.md)
# @decision RESTIC-02: Retention policy 7 daily, 5 weekly, 12 monthly
# @decision RESTIC-03: sops.templates for B2 credentials env file, passwordFile for encryption key
# @decision RESTIC-04: Back up SSH host key (sops-nix age chain), Docker bind mounts, Tailscale state; pg_dumpall pre-hook for PostgreSQL consistency
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
      # Phase 16: disaster recovery gap closure
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/var/lib/claw-swap/"
      "/var/lib/parts/"
      "/var/lib/tailscale/"
    ];

    exclude = [
      "/nix/store"
      ".git/objects"
      ".git/config"
      "node_modules"
      "__pycache__"
      ".direnv"
      "result"
    ];

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

    backupPrepareCommand = ''
      # pg_dumpall creates a consistent logical dump inside the pgdata bind mount.
      # The dump file is backed up by restic alongside raw data (belt-and-suspenders).
      # || true ensures backup proceeds even if the DB container is stopped.
      ${pkgs.docker}/bin/docker exec claw-swap-db \
        pg_dumpall -U claw -f /var/lib/postgresql/data/backup.sql \
        2>/dev/null || true
    '';

    backupCleanupCommand = ''
      rm -f /var/lib/claw-swap/pgdata/backup.sql
    '';
  };
}
