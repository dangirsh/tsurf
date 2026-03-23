# extras/syncthing.nix
# @decision SVC-02: Syncthing runs as user dev with fully declarative devices/folders.
# @decision SVC-03: GUI binds 127.0.0.1 — access via Tailscale Serve or SSH tunnel only.
# @decision SYNC-84-01: openDefaultPorts disabled to avoid exposing LAN discovery ports on VPS hosts.
# @decision SYNC-116-01: Disable global announce, local announce, relays, and NAT by default.
#   Tailnet-only mesh is the intended deployment model. Opt-in to public discovery via
#   services.syncthingStarter.publicBep = true.
# @decision SYNC-93-01: tsurf.syncthing.mesh option for cross-host sync via device registry.
#   When mesh.devices is populated, peer devices and shared folders are auto-wired.
#   Placeholder devices/folders only appear when mesh is empty (unconfigured template).
#
# --- Mesh usage ---
# 1. On each host, get the device ID: `syncthing -device-id` (or Syncthing GUI > Actions > Show ID)
# 2. In your private overlay (or host config), set:
#      tsurf.syncthing.mesh.devices = {
#        "tsurf" = { id = "XXXXXXX-..."; addresses = [ "tcp://100.x.y.z:22000" ]; };
#        "tsurf-dev" = { id = "YYYYYYY-..."; addresses = [ "tcp://100.a.b.c:22000" ]; };
#      };
#      tsurf.syncthing.mesh.folders.sync = {
#        path = "/home/dev/Sync";
#      };
# 3. Deploy to all hosts — each host automatically peers with all others in the registry.
{ config, lib, ... }:
let
  cfg = config.services.syncthingStarter;
  meshCfg = config.tsurf.syncthing.mesh;
  meshDeviceNames = builtins.attrNames meshCfg.devices;
  hasMesh = meshDeviceNames != [ ];

  # Convert mesh devices to syncthing device format
  meshSyncthingDevices = lib.mapAttrs (_name: dev: {
    inherit (dev) id;
    addresses = dev.addresses;
  }) meshCfg.devices;

  # Convert mesh folders to syncthing folder format, auto-populating device list
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
              Syncthing addresses. Use Tailscale IPs for VPS-to-VPS sync:
              [ "tcp://100.x.y.z:22000" ]
              Default "dynamic" uses global discovery (requires openDefaultPorts).
            '';
          };
        };
      });
      default = { };
      description = ''
        Syncthing device registry for automatic cross-host mesh.
        Each entry maps a device name to its ID and network addresses.
        All mesh devices automatically peer with each other.
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
                maxAge = "7776000"; # 90 days
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
      # @decision SYNC-125-01: ProtectHome/ProtectSystem/PrivateDevices omitted.
      #   Syncthing needs filesystem access for sync operations.
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
        # When mesh is configured, use mesh devices.
        # When unconfigured, show placeholder examples.
        # When mesh is configured, devices/folders are auto-wired.
        # When unconfigured, no devices/folders are registered (configure via
        # tsurf.syncthing.mesh or private overlay).
        devices = if hasMesh then meshSyncthingDevices else { };
        folders = if hasMesh then meshSyncthingFolders else { };

        gui = {
          # @decision SEC47-21: Host check re-enabled (default)
          # @rationale: Only localhost access (homepage siteMonitor). 
          insecureSkipHostcheck = false;
        };

        options = {
          urAccepted = -1;
          globalAnnounceEnabled = false;
          localAnnounceEnabled = false;
          relaysEnabled = false;
          natEnabled = false;
        };
      };
    };

    # --- Persistence: syncthing device keys + sync folders ---
    environment.persistence."/persist".directories = [
      "/home/dev/.config/syncthing"
      "/home/dev/Sync"
    ];

    services.dashboard.entries.syncthing = {
      name = "Syncthing";
      description = "File sync across devices";
      port = 8384;
      systemdUnit = "syncthing.service";
      icon = "syncthing";
      order = 20;
      module = "syncthing.nix";
    };
  };
}
