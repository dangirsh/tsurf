# modules/agent-egress-proxy.nix
# Iron-backed egress and credential proxy for sandboxed agent workloads.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.agentEgressProxy;
  launcherCfg = config.services.agentLauncher;
  yaml = pkgs.formats.yaml { };
  credentialServices = import ./lib/credential-services.nix { inherit lib; };
  inherit (credentialServices)
    credentialDefaultsFor
    urlHost
    ironProxyTokenNameFor
    ;

  stateDir = "/var/lib/tsurf-agent-egress-proxy";
  caCertPath = "${stateDir}/ca.crt";
  caKeyPath = "${stateDir}/ca.key";
  tokenFile = "${stateDir}/credential-tokens.env";
  runtimeConfigFile = "${stateDir}/iron-proxy.yaml";
  proxyUrl = "http://127.0.0.1:${toString cfg.tunnelPort}";

  ironAgents = launcherCfg.agents;

  credentialRecords = lib.concatLists (
    lib.mapAttrsToList (
      agentName: agentDef:
      map (
        svc:
        let
          defaults = credentialDefaultsFor agentDef svc;
        in
        {
          inherit agentName svc;
          envVar = defaults.envVar;
          secretName = defaults.secretName;
          hosts = defaults.hosts or [ (urlHost defaults.upstream) ];
          matchHeaders = defaults.matchHeaders;
          proxyTokenName = ironProxyTokenNameFor svc defaults;
        }
      ) agentDef.credentialServices
    ) ironAgents
  );

  # Deduplicate by service/env/secret so one shared proxy config can serve
  # several wrappers without duplicating transform entries.
  credentialRecordAttrs = lib.listToAttrs (
    map (
      record: lib.nameValuePair "${record.svc}:${record.envVar}:${record.secretName}" record
    ) credentialRecords
  );
  uniqueCredentialRecords = builtins.attrValues credentialRecordAttrs;

  credentialEnvLines = map (
    record: "${record.envVar}=${config.sops.placeholder."${record.secretName}"}"
  ) uniqueCredentialRecords;
  credentialTokenNames = map (record: record.proxyTokenName) uniqueCredentialRecords;

  credentialHosts = lib.concatMap (record: record.hosts) uniqueCredentialRecords;
  agentAllowedHosts = lib.concatLists (
    lib.mapAttrsToList (_: agentDef: agentDef.egress.allowedHosts) ironAgents
  );
  agentAllowedCIDRs = lib.concatLists (
    lib.mapAttrsToList (_: agentDef: agentDef.egress.allowedCIDRs) ironAgents
  );
  allowedHosts = lib.unique (cfg.extraAllowedHosts ++ credentialHosts ++ agentAllowedHosts);
  allowedCIDRs = lib.unique (cfg.extraAllowedCIDRs ++ agentAllowedCIDRs);

  secretTransformEntries = map (record: {
    source = {
      type = "env";
      var = record.envVar;
    };
    replace = {
      proxy_value = "@${record.proxyTokenName}@";
      match_headers = record.matchHeaders;
      require = false;
    };
    rules = map (host: { inherit host; }) record.hosts;
  }) uniqueCredentialRecords;

  transforms = [
    {
      name = "allowlist";
      config = {
        domains = allowedHosts;
        cidrs = allowedCIDRs;
      };
    }
  ]
  ++ lib.optionals (secretTransformEntries != [ ]) [
    {
      name = "secrets";
      config.secrets = secretTransformEntries;
    }
  ];

  ironConfig = {
    dns.enabled = false;
    proxy = {
      http_listen = "127.0.0.1:${toString cfg.httpPort}";
      https_listen = "127.0.0.1:${toString cfg.httpsPort}";
      tunnel_listen = "127.0.0.1:${toString cfg.tunnelPort}";
      max_request_body_bytes = cfg.maxRequestBodyBytes;
      max_response_body_bytes = cfg.maxResponseBodyBytes;
      upstream_response_header_timeout = cfg.upstreamResponseHeaderTimeout;
    }
    // lib.optionalAttrs (cfg.upstreamDenyCIDRs != null) {
      upstream_deny_cidrs = cfg.upstreamDenyCIDRs;
    };
    tls = {
      mode = "mitm";
      ca_cert = caCertPath;
      ca_key = caKeyPath;
      cert_cache_size = cfg.certCacheSize;
      leaf_cert_expiry_hours = cfg.leafCertExpiryHours;
    };
    metrics.listen = "127.0.0.1:${toString cfg.metricsPort}";
    inherit transforms;
    log.level = cfg.logLevel;
  };

  configFile = yaml.generate "tsurf-iron-proxy.yaml" ironConfig;
  credentialTokenSetup = lib.concatMapStringsSep "\n" (tokenName: ''
    if ! grep -Eq '^${tokenName}=' "$token_file"; then
      printf '%s=%s\n' '${tokenName}' "$(${pkgs.openssl}/bin/openssl rand -hex 32)" >> "$token_file"
    fi
  '') credentialTokenNames;
  credentialTokenSubstitutions = lib.concatMapStringsSep "\n" (tokenName: ''
    token_value="$(grep -E '^${tokenName}=' "$token_file" | tail -n 1 | cut -d= -f2-)"
    if [ -z "$token_value" ]; then
      echo "missing generated Iron proxy credential token ${tokenName}" >&2
      exit 1
    fi
    escaped_token_value="$(printf '%s' "$token_value" | ${pkgs.gnused}/bin/sed 's/[\/&]/\\&/g')"
    ${pkgs.gnused}/bin/sed "s/@${tokenName}@/$escaped_token_value/g" "$runtime_config" > "$runtime_config.next"
    chmod 0600 "$runtime_config.next"
    mv -f "$runtime_config.next" "$runtime_config"
  '') credentialTokenNames;
in
{
  options.services.agentEgressProxy = {
    enable = lib.mkEnableOption "Iron-backed egress and credential proxy for sandboxed agents";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.iron-proxy;
      description = "iron-proxy package to run for sandboxed agent egress.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "iron-proxy";
      description = "System user that runs the agent egress proxy.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "iron-proxy";
      description = "System group that runs the agent egress proxy.";
    };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 20280;
      description = "Loopback HTTP listener port for iron-proxy.";
    };

    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 20243;
      description = "Loopback HTTPS listener port for iron-proxy.";
    };

    tunnelPort = lib.mkOption {
      type = lib.types.port;
      default = 20208;
      description = "Loopback CONNECT/SOCKS5 tunnel listener port exposed to agents.";
    };

    metricsPort = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Loopback metrics and health listener port for iron-proxy.";
    };

    extraAllowedHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "github.com"
        "api.github.com"
        "objects.githubusercontent.com"
        "raw.githubusercontent.com"
        "codeload.github.com"
        "registry.npmjs.org"
        "pypi.org"
        "files.pythonhosted.org"
        "crates.io"
        "index.crates.io"
      ];
      description = "Additional host globs allowed through the Iron proxy for all agents.";
    };

    extraAllowedCIDRs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional CIDRs allowed through the Iron proxy for all agents.";
    };

    upstreamDenyCIDRs = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      description = "CIDRs iron-proxy must not dial upstream. null keeps Iron's secure default.";
    };

    maxRequestBodyBytes = lib.mkOption {
      type = lib.types.int;
      default = 1048576;
      description = "Maximum request body bytes buffered by Iron transforms.";
    };

    maxResponseBodyBytes = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = "Maximum response body bytes buffered by Iron transforms; 0 means uncapped.";
    };

    upstreamResponseHeaderTimeout = lib.mkOption {
      type = lib.types.str;
      default = "5m";
      description = "Iron upstream response header timeout.";
    };

    certCacheSize = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Iron leaf certificate cache size.";
    };

    leafCertExpiryHours = lib.mkOption {
      type = lib.types.int;
      default = 72;
      description = "Iron generated leaf certificate lifetime in hours.";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [
        "debug"
        "info"
        "warn"
        "error"
      ];
      default = "info";
      description = "Iron JSON log level.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = launcherCfg.enable;
        message = "services.agentEgressProxy requires services.agentLauncher.enable.";
      }
    ]
    ++ map (record: {
      assertion = builtins.hasAttr record.secretName config.sops.secrets;
      message = "services.agentEgressProxy needs sops.secrets.${record.secretName} for ${record.svc}.";
    }) uniqueCredentialRecords;

    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = stateDir;
    };

    services.agentLauncher.egressProxy = {
      url = lib.mkDefault proxyUrl;
      caCert = lib.mkDefault caCertPath;
      noProxy = lib.mkDefault "127.0.0.1,localhost";
      credentialTokenFile = lib.mkDefault tokenFile;
      credentialTokenGroup = lib.mkDefault cfg.group;
    };

    tsurf.agentEgress = {
      mediatedOnly = lib.mkDefault true;
      allowedLoopbackTCPPorts = [
        cfg.httpPort
        cfg.httpsPort
        cfg.tunnelPort
      ];
    };

    environment.systemPackages = [ cfg.package ];
    environment.persistence."/persist".directories = [ stateDir ];
    systemd.tmpfiles.rules = [
      "z ${tokenFile} 0440 ${cfg.user} ${cfg.group} -"
    ];

    sops.templates = lib.optionalAttrs (credentialEnvLines != [ ]) {
      "iron-agent-egress-env" = {
        owner = cfg.user;
        group = cfg.group;
        mode = "0400";
        content = lib.concatStringsSep "\n" credentialEnvLines + "\n";
      };
    };

    systemd.services.tsurf-agent-egress-proxy = {
      description = "Iron egress and credential proxy for sandboxed agents";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "sops-nix.service"
      ];
      path = [
        cfg.package
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
        pkgs.openssl
      ];
      preStart = ''
        set -euo pipefail
        umask 077
        token_file=${lib.escapeShellArg tokenFile}
        runtime_config=${lib.escapeShellArg runtimeConfigFile}
        if [ ! -s ${lib.escapeShellArg caCertPath} ] || [ ! -s ${lib.escapeShellArg caKeyPath} ]; then
          rm -f ${lib.escapeShellArg caCertPath} ${lib.escapeShellArg caKeyPath}
          iron-proxy generate-ca \
            --outdir ${lib.escapeShellArg stateDir} \
            --name "tsurf agent egress proxy CA" \
            --expiry-hours 8760 \
            --alg ed25519 >/dev/null
        fi
        chmod 0444 ${lib.escapeShellArg caCertPath}
        chmod 0400 ${lib.escapeShellArg caKeyPath}
        touch "$token_file"
        if [ "$(stat -c %G -- "$token_file")" != ${lib.escapeShellArg cfg.group} ]; then
          echo "Iron credential token file has an unexpected group" >&2
          exit 1
        fi
        chmod 0640 "$token_file"
        ${credentialTokenSetup}
        chmod 0440 "$token_file"
        if [ -e "$runtime_config" ]; then
          chmod 0600 "$runtime_config"
        fi
        cp ${configFile} "$runtime_config"
        chmod 0600 "$runtime_config"
        ${credentialTokenSubstitutions}
        chmod 0400 "$runtime_config"
      '';
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = "tsurf-agent-egress-proxy";
        StateDirectoryMode = "0750";
        EnvironmentFile = lib.optionals (credentialEnvLines != [ ]) [
          config.sops.templates."iron-agent-egress-env".path
        ];
        ExecStart = "${cfg.package}/bin/iron-proxy -config ${runtimeConfigFile}";
        Restart = "on-failure";
        RestartSec = "5s";
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
      };
    };
  };
}
