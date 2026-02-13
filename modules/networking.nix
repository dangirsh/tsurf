{ config, lib, pkgs, ... }: {
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 22000 ];
  };
}
