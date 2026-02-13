{ config, pkgs, inputs, ... }: {
  imports = [
    ./hardware.nix
    ./disko-config.nix
    ../../modules
  ];

  networking.hostName = "acfs";
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "C.UTF-8";

  system.stateVersion = "25.11";
}
