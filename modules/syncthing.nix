# modules/syncthing.nix
# @decision SVC-02: Syncthing runs as user dev with fully declarative devices/folders.
# @decision SVC-03: GUI/API binds 0.0.0.0 — NixOS firewall restricts access to Docker bridges and Tailscale.
{ config, ... }: {
  systemd.services.syncthing.environment = {
    STNODEFAULTFOLDER = "true";
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
    openDefaultPorts = true;
    guiAddress = "0.0.0.0:8384";
    overrideDevices = true;
    overrideFolders = true;

    settings = {
      devices = {
        "my-laptop" = {
          id = "REPLACE-WITH-YOUR-DEVICE-ID-A";
        };
        "my-phone" = {
          id = "REPLACE-WITH-YOUR-DEVICE-ID-B";
        };
      };

      folders = {
        "sync" = {
          id = "sync";
          label = "Sync";
          path = "/home/dev/Sync";
          devices = [
            "my-laptop"
            "my-phone"
          ];
          type = "sendreceive";
          rescanIntervalS = 60;
          versioning = {
            type = "staggered";
            params = {
              cleanInterval = "3600";
              maxAge = "7776000";
            };
          };
        };
      };

      gui = {
        # @decision SEC47-21: Host check re-enabled (default)
        # @rationale: Only localhost access (homepage siteMonitor). Docker bridge not used.
        insecureSkipHostcheck = false;
      };

      options = {
        urAccepted = -1;
      };
    };
  };

  services.dashboard.entries.syncthing = {
    name = "Syncthing";
    module = "syncthing.nix";
    description = "File sync across devices";
    port = 8384;
    url = "http://${config.networking.hostName}:8384";
    systemdUnit = "syncthing.service";
    icon = "syncthing";
    order = 20;
  };
}
