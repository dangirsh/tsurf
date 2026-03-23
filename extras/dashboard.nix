# extras/dashboard.nix
# Frontend: ./scripts/dashboard-frontend.html (HTML/CSS/JS)
# Backend:  ./scripts/dashboard-server.py (Python HTTP server)
#
# @decision DASH-01: Custom NixOS option namespace for dashboard entries.
# @rationale: Each module self-describes via services.dashboard.entries.
#   NixOS module system merges attrsOf across public + private overlays.
#   No disabledModules needed — private modules just add entries.
#
# @decision DASH-02: Build-time JSON manifest via builtins.toJSON.
# @rationale: Manifest represents declared config, not runtime state.
#   Reproducible, cached, testable via nix eval.
#
# @decision DASH-03: Single Python stdlib HTTP server (writePython3Bin).
# @rationale: Matches restic-status-server pattern.
#   One process, one port, one systemd unit. No framework dependencies.
#
# @decision DASH-04: DynamicUser for the dashboard service.
# @rationale: Dashboard needs no persistent state and no secrets.
#   systemctl show is unprivileged. DynamicUser provides isolation.
#
# @decision DASH-05: Status via systemctl show (batch, <100ms).
# @rationale: Decision locked: systemd unit status only, no HTTP checks.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.dashboard;

  entrySort = a: b:
    if a.order == b.order then a.name < b.name else a.order < b.order;

  entryList =
    lib.mapAttrsToList (id: entry: entry // { inherit id; })
      cfg.entries;

  groupedEntries =
    builtins.groupBy (entry: entry.module)
      (builtins.sort entrySort entryList);

  moduleLabels = {
    "networking.nix" = "Networking";
    "restic.nix" = "Backup";
    "syncthing.nix" = "File Sync";
    "agent-compute.nix" = "Agent Compute";
    "dashboard.nix" = "Dashboard";
  };

  # Parse extra manifests, extract modules per remote host
  extraHosts = builtins.mapAttrs (hostName: jsonStr:
    let
      parsed = builtins.fromJSON jsonStr;
      hostData =
        if parsed ? hosts
        then parsed.hosts.${hostName} or {}
        else {};
    in {
      modules = hostData.modules or (parsed.modules or {});
    }
  ) cfg.extraManifests;

  manifestJson = builtins.toJSON {
    primary = config.networking.hostName;
    inherit moduleLabels;
    hosts = extraHosts // {
      ${config.networking.hostName} = {
        modules = groupedEntries;
      };
    };
  };

  dashboardHtml = pkgs.writeText "dashboard.html"
    (builtins.readFile ./scripts/dashboard-frontend.html);

  dashboardBin = pkgs.writers.writePython3Bin "nix-dashboard" { }
    (builtins.readFile ./scripts/dashboard-server.py);
in
{
  options.services.dashboard = {
    enable = lib.mkEnableOption "Nix-derived dynamic dashboard";

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 8082;
      description = "Port for the dashboard HTTP server";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address the dashboard binds to. Default 127.0.0.1 (localhost only). Set to 0.0.0.0 in overlay if Tailscale direct access is needed.";
    };

    entries = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Display name";
          };
          module = lib.mkOption {
            type = lib.types.str;
            description = "Module filename used for grouping";
          };
          description = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Short description";
          };
          port = lib.mkOption {
            type = lib.types.nullOr lib.types.port;
            default = null;
            description = "Optional listening port";
          };
          url = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Web URL for clickable links";
          };
          systemdUnit = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Systemd unit for status checks";
          };
          icon = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Icon identifier or emoji";
          };
          external = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "External service with no local unit";
          };
          order = lib.mkOption {
            type = lib.types.int;
            default = 50;
            description = "Sort order within module";
          };
        };
      });
      default = { };
      description = "Dashboard entries declared across modules";
    };

    # Multi-host aggregation: merge a remote host's /etc/dashboard/manifest.json
    # into this dashboard's manifest for a combined view. In your private overlay:
    #   services.dashboard.extraManifests."other-host" =
    #     builtins.readFile "${other-config}/etc/dashboard/manifest.json";
    # Note: status polling is local-only — remote host status requires querying
    # that host's own dashboard status endpoint.
    extraManifests = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "JSON manifests from remote hosts (hostname -> JSON text)";
    };
  };

  config = lib.mkMerge [
    {
      # Always generate manifest so other hosts can reference it
      # via services.dashboard.extraManifests
      environment.etc."dashboard/manifest.json".text = manifestJson;

      services.dashboard.entries.tailscale = {
        name = "Tailscale";
        description = "VPN mesh network";
        systemdUnit = "tailscaled.service";
        icon = "tailscale";
        order = 5;
        module = "networking.nix";
      };

      services.dashboard.entries.sshd = {
        name = "SSH";
        description = "Key-only, hardened (port 22)";
        systemdUnit = "sshd.service";
        order = 6;
        module = "networking.nix";
      };
    }
    (lib.mkIf cfg.enable {
    services.dashboard.entries.dashboard = {
      name = "Dashboard";
      description = "Nix-derived service tree";
      port = cfg.listenPort;
      systemdUnit = "nix-dashboard.service";
      icon = "dashboard";
      order = 99;
      module = "dashboard.nix";
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/deploy-status 0755 root root -"
    ];

    systemd.services.nix-dashboard = {
      description = "Nix-derived dynamic dashboard";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        ExecStart =
          "${dashboardBin}/bin/nix-dashboard --port "
          + "${toString cfg.listenPort} --bind ${cfg.listenAddress} --manifest "
          + "/etc/dashboard/manifest.json --html ${dashboardHtml}";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";
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
        PrivateDevices = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        MemoryDenyWriteExecute = true;
        CapabilityBoundingSet = "";
        ReadOnlyPaths = [
          "/var/lib/deploy-status"
        ];
      };
    };
    })
  ];
}
