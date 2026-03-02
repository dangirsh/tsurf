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
#
# @decision MTX-03: mautrix-signal MemoryDenyWriteExecute=false (libsignal JIT).
# @rationale: libsignal v0.62.0+ uses JIT compilation requiring W+X memory pages.
#   This relaxes one systemd sandbox constraint for mautrix-signal only.
#   Other hardening (dedicated user, state isolation) remains in place.
#   Documented upstream requirement, not a neurosys-specific weakness.
#
# @decision MTX-04: E2E encryption breaks at bridge boundary (by design).
# @rationale: mautrix bridges decrypt messages from the source platform and
#   re-encrypt for Matrix (if E2E is enabled). Messages are briefly plaintext
#   in bridge memory. Self-hosted on Tailscale-only server mitigates trust
#   concern. This is inherent to all Matrix bridges, not avoidable.
#
# @decision MTX-05: WhatsApp account ban risk accepted.
# @rationale: mautrix-whatsapp uses unofficial WA Web protocol. Meta may
#   detect and ban/disconnect the account. Mitigation: keep WhatsApp backup
#   of chat history. Re-linking is possible if disconnected. Personal
#   single-user usage has lower detection risk than bot-like behavior.
#
# @decision MTX-06: Provisioning API enabled with placeholder shared_secret.
# @rationale: Guide page (dm-guide.nix) uses provisioning API for QR code
#   login flows. Public template uses "disable"; private overlay overrides
#   with sops-injected secrets.
#
# @decision MTX-07: Single shared provisioning secret for all three bridges.
# @rationale: All three bridges run on the same host, accessed only by the
#   dm-guide service (also on the same host). A per-bridge secret adds
#   complexity without security benefit for this internal-only MVP.
{ config, lib, ... }:
let
  # Permanent Matrix server name for this deployment.
  serverName = "neurosys.local";
in
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
      appservice.provisioning = {
        enabled = true;
        shared_secret = "disable";
      };
      bridge.permissions = {
        "*" = "relaybot";
        "@admin:${serverName}" = "admin";
      };
    };
  };

  # --- mautrix-whatsapp bridge ---
  services.mautrix-whatsapp = {
    enable = true;
    serviceDependencies = [ "conduit.service" ];
    settings = {
      homeserver = {
        address = "http://localhost:6167";
        domain = serverName;
      };
      appservice = {
        address = "http://localhost:29318";
        hostname = "127.0.0.1";
        port = 29318;
        # No appservice.database — bridgev2 uses top-level `database` key (set by module)
      };
      bridge = {
        permissions = {
          "*" = "relay";
          "@admin:${serverName}" = "admin";
        };
        history_sync = {
          create_portals = true;
        };
      };
      provisioning = {
        shared_secret = "disable";  # public default; private overlay overrides
      };
    };
  };

  # --- mautrix-signal bridge ---
  services.mautrix-signal = {
    enable = true;
    serviceDependencies = [ "conduit.service" ];
    settings = {
      homeserver = {
        address = "http://localhost:6167";
        domain = serverName;
      };
      appservice = {
        address = "http://localhost:29328";
        hostname = "127.0.0.1";
        port = 29328;
        # No appservice.database — bridgev2 uses top-level `database` key (set by module)
      };
      bridge.permissions = {
        "*" = "relay";
        "@admin:${serverName}" = "admin";
      };
      provisioning = {
        shared_secret = "disable";
      };
    };
  };

  # libsignal JIT requires W+X memory pages (see MTX-03)
  # Guard with mkIf: when enable=false, omit the override entirely so no bare unit is generated.
  # A bare unit (only MemoryDenyWriteExecute, no ExecStart) causes systemd to refuse activation.
  systemd.services.mautrix-signal = lib.mkIf config.services.mautrix-signal.enable {
    serviceConfig.MemoryDenyWriteExecute = false;
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

  # --- Matrix secret declarations for public repo eval ---
  sops.secrets."matrix-registration-token" = {
    sopsFile = ../secrets/neurosys.yaml;
  };
  sops.secrets."telegram-api-id" = {
    sopsFile = ../secrets/neurosys.yaml;
  };
  sops.secrets."telegram-api-hash" = {
    sopsFile = ../secrets/neurosys.yaml;
  };
  sops.secrets."dm-provisioning-secret" = {
    sopsFile = ../secrets/neurosys.yaml;
  };
}
