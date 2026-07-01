{
  config,
  lib,
  ...
}:
let
  cfg = config.tsurf.harmoniaCache;
  cacheUrl = lib.optionalString (cfg.host != null) "http://${cfg.host}:${toString cfg.port}";
  allowedClientIPv4s = lib.concatStringsSep ", " cfg.allowedClientIPv4s;
in
{
  options.tsurf.harmoniaCache = {
    enable = lib.mkEnableOption "Harmonia binary cache client";

    enableServer = lib.mkEnableOption "serving a Harmonia binary cache";

    host = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Host or address where the Harmonia binary cache is served.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "TCP port for the Harmonia binary cache.";
    };

    publicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Trusted public key for the Harmonia binary cache.";
    };

    signingKeySopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "SOPS file containing the harmonia-signing-key secret for the cache host.";
    };

    allowedClientIPv4s = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Public IPv4 addresses allowed to fetch from the Harmonia cache port.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.host != null;
          message = "tsurf.harmoniaCache.host must be set when the Harmonia cache client is enabled.";
        }
        {
          assertion = cfg.publicKey != null;
          message = "tsurf.harmoniaCache.publicKey must be set when the Harmonia cache client is enabled.";
        }
      ];

      nix.settings.extra-substituters = lib.optional (cfg.host != null) cacheUrl;
      nix.settings.extra-trusted-public-keys = lib.optional (cfg.publicKey != null) cfg.publicKey;
    })

    (lib.mkIf cfg.enableServer {
      assertions = [
        {
          assertion = cfg.signingKeySopsFile != null;
          message = "tsurf.harmoniaCache.signingKeySopsFile must be set when enableServer is true.";
        }
      ];

      sops.secrets."harmonia-signing-key" = lib.mkIf (cfg.signingKeySopsFile != null) {
        sopsFile = cfg.signingKeySopsFile;
      };

      services.harmonia = {
        enable = true;
        signKeyPaths = lib.optional (
          cfg.signingKeySopsFile != null
        ) config.sops.secrets."harmonia-signing-key".path;
        settings = {
          bind = "0.0.0.0:${toString cfg.port}";
          workers = 4;
          max_connection_rate = 256;
          priority = 35;
        };
      };

      networking.nftables.tables.harmonia-cache-ingress = {
        family = "inet";
        content = ''
          chain input {
            type filter hook input priority -5; policy accept;
            iifname "lo" tcp dport ${toString cfg.port} accept
            ${lib.optionalString (cfg.allowedClientIPv4s != [ ]) ''
              ip saddr { ${allowedClientIPv4s} } tcp dport ${toString cfg.port} accept
            ''}
            tcp dport ${toString cfg.port} drop
          }
        '';
      };
    })
  ];
}
