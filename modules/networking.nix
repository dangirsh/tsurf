# modules/networking.nix
# @decision NET-01: key-only SSH, no root login
# @decision NET-02: default-deny nftables firewall
# @decision NET-04: ports 22, 80, 443, 22000 only
{ config, lib, pkgs, ... }: {
  # NET-02: Use nftables backend (modern replacement for iptables)
  networking.nftables.enable = true;

  # NET-02 + NET-04: Default-deny firewall with explicit allowlist
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22     # SSH (NET-01)
      80     # HTTP
      443    # HTTPS
      22000  # Syncthing (NET-04)
    ];
  };

  # NET-01: SSH server — key-only authentication, no root login
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}
