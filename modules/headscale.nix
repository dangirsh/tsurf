# modules/headscale.nix
# Self-hosted headscale coordination server for Tailscale clients.
# @decision HS-01: Headscale replaces commercial Tailscale control plane for self-hosted mesh coordination.
# @decision HS-02: nginx reverse proxy for TLS termination (standard tsurf pattern). WebSocket support required for TS2021 control protocol.
# @decision HS-03: Embedded DERP enabled with STUN on UDP 3478. Default Tailscale DERP servers disabled for full self-hosting.
# @decision HS-04: SQLite database (default). Suitable for small fleet; /var/lib/headscale persisted under impermanence.
{ config, lib, pkgs, ... }:
let
  cfg = config.tsurf.headscale;
in
{
  options.tsurf.headscale = {
    enable = lib.mkEnableOption "self-hosted Tailscale coordination server (headscale)";
    domain = lib.mkOption {
      type = lib.types.str;
      default = "hs.example.com"; # REPLACE in private overlay
      description = "FQDN for the headscale server (nginx vhost + server_url).";
    };
    baseDomain = lib.mkOption {
      type = lib.types.str;
      default = "ts.net";
      description = "MagicDNS suffix for machine names (e.g. machine 'services' becomes 'services.ts.net'). Distinct from the server FQDN in 'domain'.";
    };
    publicIPv4 = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0"; # REPLACE in private overlay
      description = "Public IPv4 address for the embedded DERP server.";
    };
    acmeEmail = lib.mkOption {
      type = lib.types.str;
      default = "admin@example.com"; # REPLACE in private overlay
      description = "Email address for ACME certificate registration.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.headscale = {
      enable = true;
      address = "127.0.0.1";
      port = 8080;
      settings = {
        server_url = "https://${cfg.domain}";
        database.type = "sqlite";
        database.sqlite.path = "/var/lib/headscale/db.sqlite";
        database.sqlite.write_ahead_log = true;
        prefixes.v4 = "100.64.0.0/10";
        prefixes.v6 = "fd7a:115c:a1e0::/48";
        prefixes.allocation = "sequential";
        derp.server = {
          enabled = true;
          region_id = 999;
          region_code = "tsurf";
          region_name = "tsurf DERP";
          stun_listen_addr = "0.0.0.0:3478";
          ipv4 = cfg.publicIPv4;
          verify_clients = true;
        };
        derp.urls = [ ];
        derp.auto_update_enabled = false;
        dns.magic_dns = true;
        dns.base_domain = cfg.baseDomain; # MagicDNS suffix; distinct from server FQDN.
        dns.nameservers.global = [
          "1.1.1.1"
          "9.9.9.9"
        ];
        dns.override_local_dns = true;
        policy.mode = "file";
        policy.path = "/etc/headscale/acl.json";
        log.level = "info";
        log.format = "text";
        logtail.enabled = false;
        disable_check_updates = true;
        ephemeral_node_inactivity_timeout = "30m";
      };
    };

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      virtualHosts.${cfg.domain} = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8080";
          proxyWebsockets = true;
        };
      };
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.acmeEmail;
    };

    networking.firewall.allowedUDPPorts = [ 3478 ];

    # Default allow-all policy for bootstrap only; private overlays should tighten this ACL.
    environment.etc."headscale/acl.json" = {
      text = builtins.toJSON {
        acls = [
          {
            action = "accept";
            src = [ "*" ];
            dst = [ "*:*" ];
          }
        ];
      };
      mode = "0644";
    };

    environment.persistence."/persist".directories = [
      {
        directory = "/var/lib/headscale";
        user = "headscale";
        group = "headscale";
        mode = "0750";
      }
    ];
  };
}
