# modules/restic.nix
# @decision RESTIC-01: S3-compatible B2 backend (not native B2 — restic's B2 connector is unreliable per STACK.md)
# @decision RESTIC-02: Retention policy 7 daily, 5 weekly, 12 monthly
# @decision RESTIC-03: sops.templates for B2 credentials env file, passwordFile for encryption key
# @decision RESTIC-04: pg_dumpall pre-hook for PostgreSQL consistency
# @decision RESTIC-05: Back up /persist subvolume (all stateful data). Ephemeral root, /nix, Docker subvolume excluded by design.
{ config, pkgs, ... }: {

  services.restic.backups.b2 = {
    initialize = true;

    repository = "s3:s3.eu-central-003.backblazeb2.com/SyncBkp";

    passwordFile = config.sops.secrets."restic-password".path;
    environmentFile = config.sops.templates."restic-b2-env".path;

    paths = [ "/persist" ];

    extraBackupArgs = [
      "--exclude-caches"
      "--exclude-if-present" ".nobackup"
    ];

    exclude = [
      # User/build caches within persisted paths
      "**/.cache"

      # Git internals — objects fetched from remotes, config may contain tokens
      ".git/objects"
      ".git/config"

      # Language/build artifacts — reproducible
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
      # Write timestamp for node_exporter textfile collector (BackupStale alert + homepage widget)
      echo "restic_backup_last_run_timestamp $(date +%s)" > /var/lib/prometheus-node-exporter/restic.prom
    '';
  };
}
