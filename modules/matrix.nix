# modules/matrix.nix
# Matrix messaging hub: Conduit homeserver + mautrix bridges
#
# @decision MTX-01: Single module for Conduit + all mautrix bridges.
# @rationale: Matrix services are tightly coupled, so bridge and homeserver
#   settings stay co-located in one module for simpler operations.
#
# @decision MTX-02: Federation disabled, Tailscale-only access.
# @rationale: This hub is private and internal. Services bind to local/internal
#   interfaces and are protected by the internal-only port policy in networking.nix.
{ config, lib, ... }:
let
  # Permanent Matrix server name for this deployment.
  serverName = "neurosys.local";
  isNeurosys = config.networking.hostName == "neurosys";
in
lib.mkIf isNeurosys
{
  # mautrix-telegram currently depends on olm, which is marked insecure in nixpkgs.
  # Keep this allow-list narrow and local to the neurosys Matrix stack.
  nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ];

  # --- Conduit Matrix homeserver ---
  services.matrix-conduit = {
    enable = true;
    secretFile = config.sops.templates."matrix-conduit-env".path;
    settings.global = {
      server_name = serverName;
      address = "0.0.0.0";
      port = 6167;
      database_backend = "rocksdb";
      allow_registration = true;
      allow_federation = false;
      allow_encryption = true;
      trusted_servers = [ ];
    };
  };

  # --- mautrix-telegram bridge ---
  services.mautrix-telegram = {
    enable = true;
    serviceDependencies = [ "conduit.service" ];
    environmentFile = config.sops.templates."mautrix-telegram-env".path;
    settings = {
      homeserver = {
        address = "http://localhost:6167";
        domain = serverName;
      };
      appservice = {
        address = "http://localhost:29317";
        hostname = "127.0.0.1";
        port = 29317;
        database = "sqlite:////var/lib/mautrix-telegram/mautrix-telegram.db";
      };
      bridge.permissions = {
        "*" = "relaybot";
        "@admin:${serverName}" = "admin";
      };
    };
  };

  # --- Sops templates for runtime secrets ---
  sops.templates."matrix-conduit-env" = {
    content = ''
      CONDUIT_REGISTRATION_TOKEN=${config.sops.placeholder."matrix-registration-token"}
    '';
    mode = "0400";
  };

  sops.templates."mautrix-telegram-env" = {
    content = ''
      MAUTRIX_TELEGRAM_TELEGRAM_API_ID=${config.sops.placeholder."telegram-api-id"}
      MAUTRIX_TELEGRAM_TELEGRAM_API_HASH=${config.sops.placeholder."telegram-api-hash"}
    '';
    owner = "mautrix-telegram";
    mode = "0400";
  };
}
