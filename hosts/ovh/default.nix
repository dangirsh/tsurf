{ config, inputs, lib, pkgs, ... }: {
  imports = [
    ./hardware.nix
    ./disko-config.nix
    ../../modules
  ];

  networking.hostName = "neurosys-prod";
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "C.UTF-8";

  # OVH uses DHCP for static assignment.
  networking.useDHCP = true;

  # --- Host-specific shared module settings ---
  boot.loader.grub.device = "/dev/sda";
  networking.nat.externalInterface = "ens3";
  sops.defaultSopsFile = ../../secrets/ovh.yaml;
  sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  # --- srvos overrides ---
  networking.useNetworkd = lib.mkForce false;
  srvos.server.docs.enable = true;
  programs.command-not-found.enable = true;
  boot.initrd.systemd.enable = lib.mkForce false;

  system.stateVersion = "25.11";
}
