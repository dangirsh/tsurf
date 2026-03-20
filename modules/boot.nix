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
