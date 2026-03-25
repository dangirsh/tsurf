# extras/cost-tracker.nix
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
      label = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional display label used in the emitted JSON payload.";
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
    lib.mapAttrs (_: p:
      {
        inherit (p) type extraConfig;
        key_file = p.keyFile;
      }
      // lib.optionalAttrs (p.label != null) {
        label = p.label;
      }
    ) cfg.providers
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

  };
}
