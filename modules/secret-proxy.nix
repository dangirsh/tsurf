# modules/secret-proxy.nix
# @decision PROXY-66-01: Generic secret placeholder proxy module.
#   Replaces the Phase 22 hardcoded Python proxy with a backend-agnostic Rust
#   binary + declarative NixOS interface. Per-service isolation: each service
#   gets its own systemd unit, user, and port.
# @decision PROXY-66-02: BASE_URL plain-HTTP approach (not CONNECT/TLS MITM).
#   Agent sets ANTHROPIC_BASE_URL=http://127.0.0.1:<port>; proxy controls
#   upstream destination. No CA certificate distribution needed.
# @decision PROXY-66-03: File path interface for secrets — backend-agnostic.
#   Module accepts secretFile paths (sops-nix, agenix, or any file provider).
#   Real keys never appear in Nix store, env vars, or CLI args.
{ config, lib, pkgs, ... }:

let
  secretProxyPkg = pkgs.callPackage ../packages/secret-proxy.nix {};

  secretDef = { ... }: {
    options = {
      headerName = lib.mkOption {
        type = lib.types.str;
        example = "x-api-key";
        description = "Request header to inject the real key into.";
      };
      secretFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to file containing the real secret value (e.g. config.sops.secrets.\"...\".path).";
      };
      allowedDomains = lib.mkOption {
        type = lib.types.nonEmptyListOf lib.types.str;
        description = "Exact domain names the proxy is allowed to forward to.";
      };
    };
  };

  serviceOpts = { name, config, ... }: {
    options = {
      port = lib.mkOption {
        type = lib.types.port;
        description = "Port the proxy listens on (127.0.0.1 only).";
      };
      placeholder = lib.mkOption {
        type = lib.types.str;
        default = "sk-placeholder-${name}";
        description = "Placeholder token injected into agent env. Mimic real key format.";
      };
      baseUrlEnvVar = lib.mkOption {
        type = lib.types.str;
        default = "ANTHROPIC_BASE_URL";
        description = "Env var set in bwrapArgs pointing to this proxy's base URL.";
      };
      secrets = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule secretDef);
        default = {};
        description = "Secrets to inject, keyed by logical name.";
      };
      bwrapArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = "bwrap args to splice into sandbox invocations.";
      };
    };
    config = {
      bwrapArgs = [
        "--setenv" config.baseUrlEnvVar "http://127.0.0.1:${toString config.port}"
      ];
    };
  };

  mkToml = name: svcCfg:
    let
      secretEntries = lib.mapAttrsToList (secretName: s:
        ''
          [[secret]]
          header = "${s.headerName}"
          name = "${secretName}"
          file = "${s.secretFile}"
          allowed_domains = [${lib.concatMapStringsSep ", " (d: ''"${d}"'') s.allowedDomains}]
        ''
      ) svcCfg.secrets;
    in
    pkgs.writeText "secret-proxy-${name}.toml" ''
      port = ${toString svcCfg.port}
      placeholder = "${svcCfg.placeholder}"
      ${lib.concatStrings secretEntries}
    '';

  mkService = name: svcCfg:
    let
      configFile = mkToml name svcCfg;
    in {
      "secret-proxy-${name}" = {
        description = "Secret placeholder proxy for ${name}";
        after = [ "network.target" "sops-nix.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${secretProxyPkg}/bin/secret-proxy --config ${configFile}";
          User = "secret-proxy-${name}";
          Restart = "on-failure";
          RestartSec = "5s";
          # @decision SEC66-01: Full systemd hardening for secret proxy.
          # MemoryDenyWriteExecute added vs Phase 22: Rust binary is safe to restrict.
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          MemoryDenyWriteExecute = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          CapabilityBoundingSet = "";
          SystemCallArchitectures = "native";
          LockPersonality = true;
          PrivateDevices = true;
        };
      };
    };

  mkUser = name: _svcCfg: {
    "secret-proxy-${name}" = {
      isSystemUser = true;
      group = "secret-proxy";
    };
  };
in {
  options.services.secretProxy.services = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule serviceOpts);
    default = {};
    description = "Per-service secret placeholder proxy declarations.";
  };

  config = lib.mkIf (config.services.secretProxy.services != {}) {
    users.groups.secret-proxy = {};
    users.users = lib.mkMerge (lib.mapAttrsToList mkUser config.services.secretProxy.services);
    systemd.services = lib.mkMerge (lib.mapAttrsToList mkService config.services.secretProxy.services);

    assertions = let
      allPorts = lib.mapAttrsToList (n: s: { name = n; port = s.port; }) config.services.secretProxy.services;
      portCounts = builtins.foldl' (acc: x:
        acc // { "${toString x.port}" = (acc."${toString x.port}" or []) ++ [ x.name ]; }
      ) {} allPorts;
      duplicates = lib.filterAttrs (_: services: builtins.length services > 1) portCounts;
    in [
      {
        assertion = duplicates == {};
        message = "services.secretProxy: duplicate ports detected: ${
          lib.concatStringsSep ", " (lib.mapAttrsToList (port: services:
            "port ${port} used by [${lib.concatStringsSep ", " services}]"
          ) duplicates)
        }";
      }
    ];
  };
}
