{ config, lib, pkgs, ... }: {
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "/dev/sda";
    configurationLimit = 10;
  };
}
