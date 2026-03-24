# examples/private-overlay/modules/syncthing.nix
# @decision PRVSYNC-01: File sync is private-overlay only because peer topology,
#   folder layout, and any public port exposure are deployment-specific.
# @decision PRVSYNC-02: Keep the GUI localhost-only by default; public BEP remains
#   an explicit opt-in on the overlay side.
{ config, lib, ... }:
let
  cfg = config.services.syncthingStarter;
  meshCfg = config.tsurf.syncthing.mesh;
  meshDeviceNames = builtins.attrNames meshCfg.devices;
  hasMesh = meshDeviceNames != [ ];

  meshSyncthingDevices = lib.mapAttrs (_name: dev: {
    inherit (dev) id;
    addresses = dev.addresses;
  }) meshCfg.devices;

  meshSyncthingFolders = lib.mapAttrs (folderId: folder: {
    id = if folder.id != null then folder.id else folderId;
    label = if folder.label != null then folder.label else folderId;
    inherit (folder) path type;
    rescanIntervalS = folder.rescanIntervalS;
    devices = meshDeviceNames;
    versioning = folder.versioning;
  }) meshCfg.folders;
in
{
  options.services.syncthingStarter = {
    enable = lib.mkEnableOption "Syncthing file sync";
    publicBep = lib.mkEnableOption "public BEP port 22000 on the firewall (for non-Tailscale peers)";
  };

  options.tsurf.syncthing.mesh = {
    devices = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          id = lib.mkOption {
            type = lib.types.str;
            description = "Syncthing device ID (63-char, 8 groups of 7, hyphen-separated).";
          };
          addresses = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "dynamic" ];
            description = ''
              Syncthing addresses. Use Tailscale IPs for private sync:
              [ "tcp://100.x.y.z:22000" ]
            '';
          };
        };
      });
      default = { };
      description = ''
        Syncthing device registry for automatic cross-host mesh.
        All configured devices automatically peer with each other.
      '';
    };

    folders = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          path = lib.mkOption {
            type = lib.types.str;
            description = "Local path for this synced folder.";
          };
          id = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Syncthing folder ID (defaults to attrset key).";
          };
          label = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Display label (defaults to attrset key).";
          };
          type = lib.mkOption {
            type = lib.types.str;
            default = "sendreceive";
            description = "Folder type: sendreceive, sendonly, or receiveonly.";
          };
          rescanIntervalS = lib.mkOption {
            type = lib.types.int;
            default = 60;
          };
          versioning = lib.mkOption {
            type = lib.types.attrs;
            default = {
              type = "staggered";
              params = {
                cleanInterval = "3600";
                maxAge = "7776000";
              };
            };
            description = "Versioning config. Defaults to staggered with 90-day retention.";
          };
        };
      });
      default = { };
      description = ''
        Folders shared across all mesh devices.
        Each folder is automatically shared with every device in mesh.devices.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.optionals cfg.publicBep [ 22000 ];

    systemd.services.syncthing.environment = {
      STNODEFAULTFOLDER = "true";
    };

    systemd.services.syncthing.serviceConfig = {
      SystemCallArchitectures = "native";
      RestrictSUIDSGID = true;
      RestrictRealtime = true;
      LockPersonality = true;
      ProtectClock = true;
      ProtectKernelLogs = true;
    };

    systemd.tmpfiles.rules = [
      "d /home/dev/Sync 0755 dev users -"
    ];

    services.syncthing = {
      enable = true;
      user = "dev";
      group = "users";
      dataDir = "/home/dev";
      configDir = "/home/dev/.config/syncthing";
      openDefaultPorts = false;
      guiAddress = "127.0.0.1:8384";
      overrideDevices = true;
      overrideFolders = true;

      settings = {
        devices = if hasMesh then meshSyncthingDevices else { };
        folders = if hasMesh then meshSyncthingFolders else { };

        gui.insecureSkipHostcheck = false;

        options = {
          urAccepted = -1;
          globalAnnounceEnabled = false;
          localAnnounceEnabled = false;
          relaysEnabled = false;
          natEnabled = false;
        };
      };
    };

    environment.persistence."/persist".directories = [
      "/home/dev/.config/syncthing"
      "/home/dev/Sync"
    ];

    services.dashboard.entries.syncthing = {
      name = "Syncthing";
      description = "File sync across devices";
      port = 8384;
      systemdUnit = "syncthing.service";
      icon = "server";
      order = 20;
      module = "syncthing.nix";
    };
  };
}
