# hosts/hardware.nix
# Shared QEMU VPS hardware config for all hosts.
# Loads virtio drivers and BTRFS initrd support for the disko partition layout.
{ config, lib, pkgs, modulesPath, ... }: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "virtio_net"
    "ahci"
    "sd_mod"
  ];

  boot.initrd.supportedFilesystems = [ "btrfs" ];

  boot.kernelModules = [ ];
}
