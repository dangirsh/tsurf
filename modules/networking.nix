# modules/networking.nix
# @decision NET-01: key-only SSH via Tailscale only, no root login
# @decision NET-02: default-deny nftables firewall, allowPing + allowDHCP for bringup
# @decision NET-03: Tailscale VPN connected to tailnet
# @decision NET-04: ports 80, 443, 22000 on public interface; SSH via Tailscale only
# @decision NET-05: fail2ban SSH protection with progressive banning
# @decision NET-06: Tailscale reverse path filtering set to loose
{ config, lib, pkgs, ... }: {

  # --- nftables backend ---
  networking.nftables.enable = true;

  # --- Firewall: per-interface trust ---
  networking.firewall = {
    enable = true;
    allowPing = true;
    allowedTCPPorts = [ 80 443 22000 ];
    allowedUDPPorts = [ config.services.tailscale.port ];
    trustedInterfaces = [ "tailscale0" ];
  };

  # --- SSH hardening ---
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";  # root SSH fully disabled; emergency access via Contabo VNC
    };
  };

  # --- Tailscale VPN ---
  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."tailscale-authkey".path;
    useRoutingFeatures = "client";   # auto-sets checkReversePath = "loose"
    extraUpFlags = [
      "--accept-routes"
    ];
  };

  # Force tailscaled to use native nftables (avoid iptables-compat issues)
  # See: https://github.com/NixOS/nixpkgs/issues/285676
  systemd.services.tailscaled.serviceConfig.Environment = [
    "TS_DEBUG_FIREWALL_MODE=nftables"
  ];

  # --- fail2ban SSH protection ---
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "10m";

    ignoreIP = [
      "127.0.0.0/8"
      "100.64.0.0/10"    # Tailscale CGNAT range
    ];

    bantime-increment = {
      enable = true;
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "168h";     # Max 1 week ban
      overalljails = true;
    };
  };
}
