# modules/networking.nix
# @decision NET-01: port 22 open on public interface with key-only auth.
#   Brute-force mitigation via MaxAuthTries 3 + key-only auth (fail2ban disabled).
# @decision NET-122-01: No trustedInterfaces — localhost-first network model. Internal
#   services bind 127.0.0.1. Tailnet access via overlay firewall.interfaces rules.
#
# srvos provides: PasswordAuthentication=false, KbdInteractiveAuthentication=false,
# X11Forwarding=false, firewall.enable=true, allowPing=true, openssh.enable=true.
# We only set values that differ from srvos defaults.
{ config, lib, ... }:
let
  agentCfg = config.tsurf.agent;
  egressCfg = config.tsurf.agentEgress;
  # @decision NET-07: Build-time assertion prevents accidental public exposure of internal services.
  internalOnlyPorts = {
  };
  exposed = lib.filter (p: builtins.hasAttr (toString p) internalOnlyPorts) config.networking.firewall.allowedTCPPorts;
  exposedNames = map (p: "${toString p} (${internalOnlyPorts.${toString p}})") exposed;
  allowedAgentTcpPorts = lib.concatStringsSep ", " (map toString egressCfg.allowedTCPPorts);
  blockedAgentIpv4Cidrs = lib.concatStringsSep ", " egressCfg.blockedIPv4Cidrs;
  blockedAgentIpv6Cidrs = lib.concatStringsSep ", " egressCfg.blockedIPv6Cidrs;
in {
  options.tsurf.agentEgress = {
    enable = lib.mkEnableOption "host-level egress allowlist for the dedicated agent user" // {
      default = true;
    };

    allowedTCPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ 22 80 443 ];
      description = "TCP destination ports agents may reach (Git SSH + HTTPS API).";
    };

    allowDns = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow outbound DNS (TCP/UDP 53) for the agent user.";
    };

    blockPrivateRanges = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Drop agent traffic to RFC1918, tailnet, link-local, and ULA ranges.";
    };

    blockedIPv4Cidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "10.0.0.0/8"
        "172.16.0.0/12"
        "192.168.0.0/16"
        "100.64.0.0/10"
        "169.254.0.0/16"
      ];
      description = "IPv4 CIDRs blocked for the agent user when blockPrivateRanges is enabled.";
    };

    blockedIPv6Cidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "fc00::/7"
        "fe80::/10"
      ];
      description = "IPv6 CIDRs blocked for the agent user when blockPrivateRanges is enabled.";
    };
  };

  config = {
    assertions = [
      {
        assertion = exposed == [];
        message = "SECURITY: Internal service ports leaked into allowedTCPPorts: ${lib.concatStringsSep ", " exposedNames}. These must remain localhost-only.";
      }
      {
        assertion = config.services.openssh.settings.PermitRootLogin != "no";
        message = "LOCKOUT PREVENTION: PermitRootLogin must not be 'no' — deploy-rs uses root SSH. Use 'prohibit-password'.";
      }
      {
        assertion = builtins.elem 22 config.networking.firewall.allowedTCPPorts
          || config.services.openssh.openFirewall;
        message = "LOCKOUT PREVENTION: SSH port 22 must be reachable.";
      }
      {
        assertion = builtins.any (k: lib.hasInfix "break-glass-emergency" k)
          config.users.users.root.openssh.authorizedKeys.keys;
        message = "LOCKOUT PREVENTION: root must have break-glass emergency SSH key. Import modules/break-glass-ssh.nix.";
      }
    ];

    # --- nftables ---
    networking.nftables.enable = true;
    networking.nftables.tables =
      {
        agent-metadata-block = {
          family = "ip";
          content = ''
            chain output {
              type filter hook output priority 0; policy accept;
              ip daddr 169.254.169.254 drop
            }
          '';
        };
      }
      // lib.optionalAttrs egressCfg.enable {
        # @decision NET-144-01: Agent egress enforced at host firewall by UID.
        agent-egress = {
          family = "inet";
          content = ''
            set tsurf_agent_egress_tcp_ports {
              type inet_service;
              elements = { ${allowedAgentTcpPorts} }
            }

            chain output {
              type filter hook output priority 0; policy accept;
              meta skuid ${toString agentCfg.uid} oifname "lo" accept
            ${lib.optionalString egressCfg.allowDns ''
              meta skuid ${toString agentCfg.uid} udp dport 53 accept
              meta skuid ${toString agentCfg.uid} tcp dport 53 accept
            ''}
            ${lib.optionalString egressCfg.blockPrivateRanges ''
              meta skuid ${toString agentCfg.uid} ip daddr { ${blockedAgentIpv4Cidrs} } drop
              meta skuid ${toString agentCfg.uid} ip6 daddr { ${blockedAgentIpv6Cidrs} } drop
            ''}
              meta skuid ${toString agentCfg.uid} tcp dport @tsurf_agent_egress_tcp_ports accept
              meta skuid ${toString agentCfg.uid} drop
            }
          '';
        };
      };

    # --- Firewall ---
    # srvos sets enable=true and allowPing=true; we only add our port policy.
    networking.firewall = {
      allowedTCPPorts = [ 22 ] ++ lib.optionals config.services.nginx.enable [ 80 443 ];
      trustedInterfaces = [ ];
    };

    # --- SSH hardening ---
    # srvos sets: enable, PasswordAuthentication=false, KbdInteractiveAuthentication=false,
    # X11Forwarding=false. We add: host key restriction, session limits, root login policy.
    services.openssh = {
      openFirewall = false;
      hostKeys = [
        { type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }
      ];
      settings = {
        PermitRootLogin = "prohibit-password";
        MaxAuthTries = 3;
        LoginGraceTime = 30;
        ClientAliveInterval = 300;
        ClientAliveCountMax = 3;
      };
      # @decision NET-14: Check .ssh/authorized_keys BEFORE /etc/ssh/authorized_keys.d/%u.
      # Impermanence fallback: if activation fails, persisted /root/.ssh/ keys still work.
      authorizedKeysFiles = lib.mkForce [ ".ssh/authorized_keys" "/etc/ssh/authorized_keys.d/%u" ];
    };

    # --- Persistence: SSH host keys ---
    environment.persistence."/persist".files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };
}
