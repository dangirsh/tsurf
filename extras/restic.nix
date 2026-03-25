# extras/restic.nix
# @decision RESTIC-01: S3-compatible B2 backend (not native B2 — restic's B2 connector is unreliable per STACK.md)
{ config, lib, ... }:
let
  cfg = config.services.resticStarter;
in
{
  options.services.resticStarter.enable = lib.mkEnableOption "Restic B2 backup";

  config = lib.mkIf cfg.enable {

  services.restic.backups.b2 = {
    initialize = true;

    # Backblaze B2: create a bucket, then an application key with read/write access.
    # The S3-compatible endpoint region (eu-central-003) must match your bucket's region.
    # Credentials go in sops secrets (restic-b2-key-id, restic-b2-app-key) rendered
    # via sops.templates."restic-b2-env" in secrets.nix.
    repository = "s3:s3.eu-central-003.backblazeb2.com/your-bucket-name";

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
      true
    '';
  };

  # --- Persistence: restic chunk cache ---
  environment.persistence."/persist".directories = [
    "/root/.cache/restic"
  ];

  }; # end lib.mkIf
}
