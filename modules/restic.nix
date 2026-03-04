# modules/restic.nix
# @decision RESTIC-01: S3-compatible B2 backend (not native B2 — restic's B2 connector is unreliable per STACK.md)
# @decision RESTIC-02: Retention policy 7 daily, 5 weekly, 12 monthly
# @decision RESTIC-03: sops.templates for B2 credentials env file, passwordFile for encryption key
# @decision RESTIC-04: Public template keeps backupPrepareCommand as a no-op; private overlay can add service-specific dump hooks.
# @decision RESTIC-05: Back up /persist subvolume (all stateful data). Ephemeral root, /nix, Docker subvolume excluded by design.
# @decision RESTIC-06: Backup timestamp served on localhost:9200 (python3 http.server) for homepage widget — no Prometheus dependency.
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
      # Private overlay: add service-specific pre-backup hooks here if needed.
      true
    '';

    backupCleanupCommand = ''
      # Private overlay: add service-specific post-backup hooks here if needed.
      mkdir -p /var/lib/restic-status
      echo "{\"timestamp\": $(date +%s), \"date\": \"$(date -Iseconds)\"}" \
        > /var/lib/restic-status/status.json
    '';
  };

  systemd.tmpfiles.rules = [ "d /var/lib/restic-status 0755 root root -" ];

  # Minimal HTTP server so homepage can display last backup time without Prometheus.
  systemd.services.restic-status-server = {
    description = "Restic backup status server for homepage widget";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 -m http.server 9200 --bind 127.0.0.1 --directory /var/lib/restic-status";
      Restart = "always";
      StandardOutput = "null";
      StandardError = "null";
    };
  };

  services.dashboard.entries.restic-backup = {
    name = "Restic B2 Backup";
    module = "restic.nix";
    description = "Daily backups — 7 daily, 5 weekly, 12 monthly retention";
    systemdUnit = "restic-backups-b2.service";
    icon = "backblaze-b2";
    order = 15;
  };

  services.dashboard.entries.restic-status = {
    name = "Backup Status Server";
    module = "restic.nix";
    description = "HTTP status endpoint for dashboard widgets";
    port = 9200;
    systemdUnit = "restic-status-server.service";
    order = 16;
  };

  services.dashboard.entries.backblaze-b2 = {
    name = "Backblaze B2";
    module = "restic.nix";
    description = "Cloud backup storage";
    url = "https://secure.backblaze.com/b2_buckets.htm";
    icon = "backblaze-b2";
    external = true;
    order = 17;
  };
}
