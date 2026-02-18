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

  systemd.tmpfiles.rules = [
    "d /home/dangirsh/Sync 0755 dangirsh users -"
  ];

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
          id = "LYQPMIK-QXAB6PL-T64O22N-GRNCANW-JYFZJJX-J5WGGR5-R2MQ5ZO-V23ZLQU";
        };
        "Pixel 10 Pro" = {
          id = "YBHZJDE-2XWYQN2-LOONB2Z-UICZJAC-VNHP56V-LU4BPFW-KRCCPWX-AH5BXQY";
        };
      };

      folders = {
        "sync" = {
          id = "sync";
          label = "Sync";
          path = "/home/dangirsh/Sync";
          devices = [
            "MacBook-Pro.local"
            "Pixel 10 Pro"
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
