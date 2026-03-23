# extras/cost-tracker.nix
# @decision COST-01: Separate module from dashboard — cost fetching needs
#   network + secrets access; dashboard is DynamicUser with no secrets.
# @decision COST-02: Provider-agnostic config — each provider is an attrset
#   entry with type + keyFile. Private overlay adds admin keys to sops.
# @decision COST-03: Write JSON to /run/ — ephemeral, dashboard reads it.
#   Timer repopulates daily. Manual refresh via systemctl restart.
# @decision COST-04: Multi-period costs (24h, 7d, 30d, 365d, 730d).
#   Each provider fetched once per period. OpenAI supports project_ids filter.
# @decision COST-05: DynamicUser=true — runs as ephemeral UID. CAP_DAC_READ_SEARCH
#   is granted via AmbientCapabilities + CapabilityBoundingSet so the service can
#   read configured secret files without running as root.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.costTracker;

  providerType = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = lib.types.enum [
          "anthropic"
          "openai"
        ];
        description = "API provider type";
      };
      keyFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to sops-decrypted API key file";
      };
      extraConfig = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Extra config (e.g. project_ids as comma-separated)";
      };
    };
  };

  providerJson = builtins.toJSON (
    lib.mapAttrs (_: p: {
      inherit (p) type extraConfig;
      key_file = p.keyFile;
    }) cfg.providers
  );

  costTrackerScript = pkgs.writers.writePython3Bin "tsurf-cost-tracker" {
    libraries = [ ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./scripts/cost-tracker.py);

  configFile = pkgs.writeText "cost-tracker-config.json" providerJson;
in
{
  options.services.costTracker = {
    enable = lib.mkEnableOption "API cost tracker";

    providers = lib.mkOption {
      type = lib.types.attrsOf providerType;
      default = { };
      description = "Provider configurations for cost tracking";
    };

    outputPath = lib.mkOption {
      type = lib.types.str;
      default = "/run/tsurf-cost.json";
      description = "Path to write cost JSON";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 06:00:00";
      description = "Systemd calendar spec for cost fetch timer";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.tsurf-cost-tracker = {
      description = "Fetch API provider costs";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      environment = {
        COST_TRACKER_CONFIG = "${configFile}";
        COST_TRACKER_OUTPUT = cfg.outputPath;
      };

      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        ExecStart = "${costTrackerScript}/bin/tsurf-cost-tracker";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        SystemCallArchitectures = "native";
        RestrictNamespaces = true;
        LockPersonality = true;
        # @decision SEC-116-05: Hardening baseline applied. MemoryDenyWriteExecute omitted
        #   (Python runtime may need W+X pages for imports).
        PrivateDevices = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        RestrictSUIDSGID = true;
        RestrictRealtime = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        UMask = "0077";
        AmbientCapabilities = [ "CAP_DAC_READ_SEARCH" ];
        CapabilityBoundingSet = [ "CAP_DAC_READ_SEARCH" ];
        RuntimeDirectory = "tsurf-cost-tracker";
        ReadWritePaths = [ (builtins.dirOf cfg.outputPath) ];
        ReadOnlyPaths = [ "/run/secrets" ];
      };
    };

    systemd.timers.tsurf-cost-tracker = {
      description = "Daily API cost fetch";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        OnBootSec = "2min";
        Persistent = true;
      };
    };

    services.dashboard.entries.cost-tracker = lib.mkIf config.services.dashboard.enable {
      name = "Cost Tracker";
      module = "cost-tracker.nix";
      description = "Daily API provider spend";
      systemdUnit = "tsurf-cost-tracker.service";
      icon = "cost";
      order = 90;
    };
  };
}
