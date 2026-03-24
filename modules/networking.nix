# modules/networking.nix
# @decision NET-01: port 22 open on public interface with key-only auth (srvos SSH hardening defaults).
#   fail2ban is disabled; brute-force mitigation via MaxAuthTries 3 + key-only auth.
#   Deliberate: Tailscale-preferred deploy, but public SSH enables bootstrap/recovery when
#   Tailscale is unavailable (e.g., first boot, Tailscale misconfiguration).
# @decision NET-122-01: No trustedInterfaces — localhost-first network model. Internal
#   services bind 127.0.0.1 by default. Tailnet access via SSH tunnel, Tailscale Serve,
#   or overlay adding ports to networking.firewall.interfaces.tailscale0.allowedTCPPorts.
#   See SECURITY.md "Network Model" section.
{ config, lib, pkgs, ... }:
let
  # @decision NET-07: Build-time assertion prevents accidental public exposure of internal services.
  # Manual port-to-label map — kept in sync with UI-visible internal services.
  internalOnlyPorts = {
    "8082" = "Dashboard";
    "9200" = "Restic status server";
  };
  exposed = lib.filter (p: builtins.hasAttr (toString p) internalOnlyPorts) config.networking.firewall.allowedTCPPorts;
  exposedNames = map (p: "${toString p} (${internalOnlyPorts.${toString p}})") exposed;
in {
  assertions = [
    {
      assertion = exposed == [];
      message = "SECURITY: Internal service ports leaked into allowedTCPPorts: ${lib.concatStringsSep ", " exposedNames}. These must remain localhost-only. Use networking.firewall.interfaces.tailscale0.allowedTCPPorts in overlay if tailnet access is needed.";
    }
    # --- Remote access safety assertions ---
    {
      assertion = config.services.openssh.enable;
      message = "LOCKOUT PREVENTION: sshd must be enabled — disabling it removes all remote access.";
    }
    {
      assertion = config.services.openssh.settings.PermitRootLogin != "no";
      message = "LOCKOUT PREVENTION: PermitRootLogin must not be 'no' — deploy-rs uses root SSH. Use 'prohibit-password'.";
    }
    {
      assertion = builtins.elem 22 config.networking.firewall.allowedTCPPorts
        || config.services.openssh.openFirewall;
      message = "LOCKOUT PREVENTION: SSH port 22 must be reachable — add to allowedTCPPorts or set services.openssh.openFirewall = true.";
    }
    {
      assertion = config.services.tailscale.enable;
      message = "LOCKOUT PREVENTION: Tailscale must be enabled — it provides the primary remote access path.";
    }
    {
      assertion = builtins.any (k: lib.hasInfix "break-glass-emergency" k)
        config.users.users.root.openssh.authorizedKeys.keys;
      message = "LOCKOUT PREVENTION: root must have break-glass emergency SSH key. Import modules/break-glass-ssh.nix.";
    }
  ];

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
    allowedTCPPorts = [ 22 ] ++ lib.optionals config.services.nginx.enable [ 80 443 ];
    allowedUDPPorts = [ config.services.tailscale.port ];
    trustedInterfaces = [ ];
  };

  # --- fail2ban: temporarily disabled (caused lockout during active dev sessions) ---
  services.fail2ban.enable = false;

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
      X11Forwarding = false;
      MaxAuthTries = 3;
      LoginGraceTime = 30;
      ClientAliveInterval = 300;
      ClientAliveCountMax = 3;
    };
    # @decision NET-14: Check .ssh/authorized_keys BEFORE /etc/ssh/authorized_keys.d/%u.
    # Impermanence fallback: if activation fails, persisted /root/.ssh/ keys still work.
    # NOTE: must use authorizedKeysFiles (extraConfig mkAfter is ignored by OpenSSH).
    authorizedKeysFiles = lib.mkForce [ ".ssh/authorized_keys" "/etc/ssh/authorized_keys.d/%u" ];
  };

  # --- Tailscale VPN ---
  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."tailscale-authkey".path;
    useRoutingFeatures = "client";   # auto-sets checkReversePath = "loose"
    extraUpFlags = [ ];
  };

  # --- Persistence: network identity + SSH host keys ---
  environment.persistence."/persist".directories = [
    "/var/lib/tailscale"                 # Device keys, auth state, node identity
  ];
  environment.persistence."/persist".files = [
    "/etc/ssh/ssh_host_ed25519_key"      # SSH host key — sops-nix age key derivation chain
    "/etc/ssh/ssh_host_ed25519_key.pub"  # SSH host key (public)
  ];
}
