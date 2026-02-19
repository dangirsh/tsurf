# modules/restic.nix
# @decision RESTIC-01: S3-compatible B2 backend (not native B2 — restic's B2 connector is unreliable per STACK.md)
# @decision RESTIC-02: Retention policy 7 daily, 5 weekly, 12 monthly
# @decision RESTIC-03: sops.templates for B2 credentials env file, passwordFile for encryption key
{ config, ... }: {

  services.restic.backups.b2 = {
    initialize = true;

    repository = "s3:s3.eu-central-003.backblazeb2.com/SyncBkp";

    passwordFile = config.sops.secrets."restic-password".path;
    environmentFile = config.sops.templates."restic-b2-env".path;

    paths = [
      "/data/projects/"
      "/home/dangirsh/"
      "/var/lib/hass/"
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
  };
}
