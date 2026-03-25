# modules/boot.nix
# GRUB bootloader config and BTRFS root subvolume rollback on boot.
# The rollback script runs in initrd postResumeCommands before root is mounted.
{ lib, ... }: {
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    configurationLimit = 10;
  };

  boot.initrd.postResumeCommands = lib.mkAfter
    (builtins.readFile ../scripts/btrfs-rollback.sh);
}
