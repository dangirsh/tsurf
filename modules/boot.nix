# modules/boot.nix
# GRUB bootloader config and BTRFS root subvolume rollback on boot.
# The rollback script runs in systemd initrd before root is mounted.
{ pkgs, ... }:
{
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    configurationLimit = 10;
  };

  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.services.tsurf-btrfs-rollback = {
    description = "Reset the ephemeral BTRFS root subvolume";
    wantedBy = [ "initrd-root-fs.target" ];
    requires = [ "initrd-root-device.target" ];
    after = [ "initrd-root-device.target" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig.Type = "oneshot";
    path = with pkgs; [
      btrfs-progs
      coreutils
      findutils
      util-linux
    ];
    script = builtins.readFile ../scripts/btrfs-rollback.sh;
  };
}
