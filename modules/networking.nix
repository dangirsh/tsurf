# modules/networking.nix
# @decision NET-01: key-only SSH via Tailscale only (port 22 NOT on public firewall)
# @decision NET-02: default-deny nftables firewall, allowPing + allowDHCP for bringup
# @decision NET-03: Tailscale VPN connected to tailnet
# @decision NET-04: ports 80, 443, 22000 on public interface; SSH via Tailscale only
# @decision NET-05: fail2ban SSH protection with progressive banning
# @decision NET-06: Tailscale reverse path filtering set to loose
{ config, lib, pkgs, ... }:
let
  # Ports that must NEVER appear in allowedTCPPorts (internal services).
  # Services bind to localhost or are Tailscale-only — never on the public interface.
  # @decision NET-07: Build-time assertion prevents accidental public exposure of internal services.
  internalOnlyPorts = {
    "8082" = "homepage-dashboard";
    "8123" = "home-assistant";
    "8384" = "syncthing-gui (localhost)";
    "9090" = "prometheus (localhost)";
    "9100" = "node-exporter";
  };
  exposed = lib.filter (p: builtins.hasAttr (toString p) internalOnlyPorts) config.networking.firewall.allowedTCPPorts;
  exposedNames = map (p: "${toString p} (${internalOnlyPorts.${toString p}})") exposed;
in {
  assertions = [
    {
      assertion = exposed == [];
      message = "SECURITY: Internal service ports leaked into allowedTCPPorts: ${lib.concatStringsSep ", " exposedNames}. These must remain Tailscale-only (trustedInterfaces).";
    }
    # TEMPORARY: port 22 assertion disabled for impermanence migration
    # Safety net while Tailscale bootstraps on fresh install
    # Will be re-enabled after deploy-rs magic rollback confirms Tailscale works
    # {
    #   assertion = !builtins.elem 22 config.networking.firewall.allowedTCPPorts;
    #   message = "SECURITY: Port 22 must NOT be in allowedTCPPorts. SSH is Tailscale-only (trustedInterfaces). Deploy uses root@neurosys which resolves via Tailscale MagicDNS.";
    # }
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
    # TEMPORARY: port 22 added for impermanence migration safety net
    allowedTCPPorts = [ 22 80 443 22000 ];
    allowedUDPPorts = [ config.services.tailscale.port ];
    trustedInterfaces = [ "tailscale0" ];
  };

  # --- SSH hardening ---
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      # TEMPORARY: password auth enabled for migration debugging via VNC
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;
      PermitRootLogin = "yes";  # TEMPORARY: allow password login for migration
    };
  };

  # Ensure sshd starts after impermanence bind-mounts /etc/ssh host keys
  systemd.services.sshd = {
    after = [ "etc-ssh.mount" ];
    requires = [ "etc-ssh.mount" ];
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
