# modules/networking.nix
# @decision NET-01: key-only SSH; port 22 open on public interface (temporary, pending Tailscale bootstrap fix)
# @decision NET-02: default-deny nftables firewall, allowPing + allowDHCP for bringup
# @decision NET-03: Tailscale VPN connected to tailnet
# @decision NET-04: ports 22, 80, 443, 22000 on public interface
# @decision NET-06: Tailscale reverse path filtering set to loose
# @decision NET-08: Only ed25519 host key — matches injected key, avoids ephemeral RSA/ECDSA regeneration
{ config, lib, pkgs, ... }:
let
  # Ports that must NEVER appear in allowedTCPPorts (internal services).
  # Services bind to localhost or are Tailscale-only — never on the public interface.
  # @decision NET-07: Build-time assertion prevents accidental public exposure of internal services.
  internalOnlyPorts = {
    "3000" = "claw-swap app (localhost, nginx-proxied)";
    "8082" = "homepage-dashboard";
    "8123" = "home-assistant";
    "8384" = "syncthing-gui (localhost)";
    "9090" = "prometheus (localhost)";
    "9091" = "anthropic-secret-proxy";
    "9100" = "node-exporter";
    "19898" = "spacebot api/web";
  };
  exposed = lib.filter (p: builtins.hasAttr (toString p) internalOnlyPorts) config.networking.firewall.allowedTCPPorts;
  exposedNames = map (p: "${toString p} (${internalOnlyPorts.${toString p}})") exposed;
in {
  assertions = [
    {
      assertion = exposed == [];
      message = "SECURITY: Internal service ports leaked into allowedTCPPorts: ${lib.concatStringsSep ", " exposedNames}. These must remain Tailscale-only (trustedInterfaces).";
    }
  ];

  programs.mosh.enable = true;

  # --- nftables backend ---
  networking.nftables.enable = true;
  networking.nftables.tables.agent-metadata-block = {
    family = "ip";
    content = ''
      chain output {
        type filter hook output priority 0; policy accept;
        ip daddr 169.254.169.254 drop
      }
    '';
  };

  # --- Firewall: per-interface trust ---
  networking.firewall = {
    enable = true;
    allowPing = true;
    allowedTCPPorts = [ 22 80 443 22000 ];
    allowedUDPPorts = [ config.services.tailscale.port ];
    trustedInterfaces = [ "tailscale0" ];
  };

  # --- SSH hardening ---
  services.openssh = {
    enable = true;
    openFirewall = false;
    hostKeys = [
      { type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }
    ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";  # key-only root access for deploy pipeline
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
}
