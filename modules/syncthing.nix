# modules/syncthing.nix
# @decision SVC-02: Syncthing runs as user dangirsh with fully declarative devices/folders.
# GUI security model:
# - Syncthing GUI listens on 0.0.0.0:8384 to avoid startup ordering issues with tailscale0.
# - Port 8384 is intentionally not in firewall.allowedTCPPorts.
# - tailscale0 is a trusted interface in networking.nix, so GUI access is effectively tailnet-only.
{ ... }: {
  systemd.services.syncthing.environment = {
    STNODEFAULTFOLDER = "true";
  };

  services.syncthing = {
    enable = true;
    user = "dangirsh";
    group = "users";
    dataDir = "/home/dangirsh";
    configDir = "/home/dangirsh/.config/syncthing";
    openDefaultPorts = true;
    guiAddress = "0.0.0.0:8384";
    overrideDevices = true;
    overrideFolders = true;

    settings = {
      devices = {
        "MacBook-Pro.local" = {
          id = "DEVICE-ID-PLACEHOLDER-1";
        };
        "DC-1" = {
          id = "DEVICE-ID-PLACEHOLDER-2";
        };
        "Pixel 10 Pro" = {
          id = "DEVICE-ID-PLACEHOLDER-3";
        };
        "MacBook-Pro-von-Theda.local" = {
          id = "DEVICE-ID-PLACEHOLDER-4";
        };
      };

      folders = {
        "sync" = {
          id = "sync";
          label = "Sync";
          path = "/home/dangirsh/Sync";
          devices = [
            "MacBook-Pro.local"
            "DC-1"
            "Pixel 10 Pro"
            "MacBook-Pro-von-Theda.local"
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

      options = {
        urAccepted = -1;
      };
    };
  };
}
