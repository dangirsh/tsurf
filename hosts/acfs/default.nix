{ config, pkgs, inputs, ... }: {
  imports = [
    ./hardware.nix
    ./disko-config.nix
    ../../modules
  ];

  networking.hostName = "acfs";
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "C.UTF-8";

  # --- Static IP (Contabo VPS does not use DHCP) ---
  networking.useDHCP = false;
  networking.interfaces.eth0.ipv4.addresses = [{
    address = "62.171.134.33";
    prefixLength = 19;
  }];
  networking.defaultGateway = {
    address = "62.171.128.1";
    interface = "eth0";
  };
  networking.nameservers = [ "213.136.95.10" "213.136.95.11" ];

  system.stateVersion = "25.11";
}
