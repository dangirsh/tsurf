{ config, pkgs, inputs, lib, ... }: {
  imports = [
    ./hardware.nix
    ./disko-config.nix
    ../../modules
  ];

  networking.hostName = "neurosys";
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "C.UTF-8";

  # --- Static IP (Contabo VPS does not use DHCP) ---
  networking.useDHCP = false;
  networking.interfaces.eth0.ipv4.addresses = [{
    address = "161.97.74.121";
    prefixLength = 18;
  }];
  networking.defaultGateway = {
    address = "161.97.64.1";
    interface = "eth0";
  };
  networking.nameservers = [ "213.136.95.10" "213.136.95.11" ];

  # --- srvos overrides ---
  # Contabo VPS uses scripted networking for static IP, not systemd-networkd
  networking.useNetworkd = lib.mkForce false;
  # Dev server: agents and humans need man pages and --help
  srvos.server.docs.enable = true;
  # Helpful for interactive sessions
  programs.command-not-found.enable = true;
  # srvos does not set this today, but mkForce guards against a future srvos
  # release enabling systemd initrd before Phase 21 is ready
  boot.initrd.systemd.enable = lib.mkForce false;

  system.stateVersion = "25.11";
}
