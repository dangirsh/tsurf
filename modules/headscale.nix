# modules/headscale.nix
# Self-hosted Tailscale control plane via headscale.
# Opt-in module: enable with tsurf.headscale.enable = true in your host config or private overlay.
# @decision HS-01: Headscale replaces commercial Tailscale control plane for self-hosted mesh coordination.
# @decision HS-02: nginx reverse proxy for TLS termination (standard tsurf pattern). WebSocket support required for TS2021 control protocol.
# @decision HS-03: Embedded DERP enabled with STUN on UDP 3478. Default Tailscale DERP servers disabled for full self-hosting.
# @decision HS-04: SQLite database (default). Suitable for small fleet; /var/lib/headscale persisted under impermanence.
# @decision HS-05: Default ACL fails closed. Private overlays must declare mesh policy explicitly.
{
  config,
  lib,
  ...
}:
let
  cfg = config.tsurf.headscale;
  domain = if cfg.domain != null then cfg.domain else "invalid.example";
  publicIPv4 = if cfg.publicIPv4 != null then cfg.publicIPv4 else "0.0.0.0";
  acmeEmail = if cfg.acmeEmail != null then cfg.acmeEmail else "invalid@example.invalid";
in
{
  options.tsurf.headscale = {
    enable = lib.mkEnableOption "self-hosted Tailscale coordination server (headscale)";
    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "FQDN for the headscale server (nginx vhost + server_url).";
    };
    baseDomain = lib.mkOption {
      type = lib.types.str;
      default = "ts.net";
      description = "MagicDNS suffix for machine names (e.g. machine 'services' becomes 'services.ts.net'). Distinct from the server FQDN in 'domain'.";
    };
    publicIPv4 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Public IPv4 address for the embedded DERP server.";
    };
    acmeEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Email address for ACME certificate registration.";
    };
    nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "1.1.1.1"
        "9.9.9.9"
      ];
      description = "Recursive DNS resolvers advertised by headscale.";
    };
    aclPolicy = lib.mkOption {
      type = lib.types.attrs;
      default = {
        acls = [ ];
        ssh = [ ];
      };
      description = "Headscale policy written to /etc/headscale/acl.json. Defaults to deny-all.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.domain != null;
        message = "tsurf.headscale.domain must be set when headscale is enabled.";
      }
      {
        assertion = cfg.publicIPv4 != null;
        message = "tsurf.headscale.publicIPv4 must be set when headscale is enabled.";
      }
      {
        assertion = cfg.acmeEmail != null;
        message = "tsurf.headscale.acmeEmail must be set when headscale is enabled.";
      }
      {
        assertion = cfg.nameservers != [ ];
        message = "tsurf.headscale.nameservers must be set when headscale is enabled.";
      }
    ];

    services.headscale = {
      enable = true;
      address = "127.0.0.1";
      port = 8080;
      settings = {
        server_url = "https://${domain}";
        database = {
          type = "sqlite";
          sqlite = {
            path = "/var/lib/headscale/db.sqlite";
            write_ahead_log = true;
          };
        };
        prefixes = {
          v4 = "100.64.0.0/10";
          v6 = "fd7a:115c:a1e0::/48";
          allocation = "sequential";
        };
        derp = {
          server = {
            enabled = true;
            region_id = 999;
            region_code = "tsurf";
            region_name = "tsurf DERP";
            stun_listen_addr = "0.0.0.0:3478";
            ipv4 = publicIPv4;
            verify_clients = true;
          };
          urls = [ ];
          auto_update_enabled = false;
        };
        dns = {
          magic_dns = true;
          base_domain = cfg.baseDomain; # MagicDNS suffix -- distinct from server FQDN
          nameservers.global = cfg.nameservers;
          override_local_dns = true;
        };
        policy = {
          mode = "file";
          path = "/etc/headscale/acl.json";
        };
        log = {
          level = "info";
          format = "text";
        };
        logtail = {
          enabled = false;
        };
        disable_check_updates = true;
        ephemeral_node_inactivity_timeout = "30m";
      };
    };

    # nginx reverse proxy with TLS (standard tsurf pattern)
    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      virtualHosts.${domain} = {
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
      defaults.email = acmeEmail;
    };

    # STUN port for embedded DERP server
    networking.firewall.allowedUDPPorts = [ 3478 ];

    # ACL policy via environment.etc with deny-all default.
    # Private overlays should set tsurf.headscale.aclPolicy or force this file.
    environment.etc."headscale/acl.json" = {
      text = builtins.toJSON cfg.aclPolicy;
      mode = "0644";
    };

    # Impermanence: persist headscale state (colocated with owning module)
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
