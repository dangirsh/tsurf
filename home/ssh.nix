{ config, pkgs, ... }: {
  programs.ssh = {
    enable = true;
    controlMaster = "auto";
    controlPersist = "10m";
    serverAliveInterval = 60;
    hashKnownHosts = true;
  };
}
