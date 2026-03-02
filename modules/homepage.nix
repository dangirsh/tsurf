# modules/homepage.nix
# @decision HP-01: Use NixOS-native homepage-dashboard service; listen on 0.0.0.0 for Tailscale reachability.
{ config, ... }: {
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    allowedHosts = "*";

    settings = {
      title = config.networking.hostName;
      theme = "dark";
      color = "slate";
      headerStyle = "clean";
      statusStyle = "dot";
    };

    docker = {
      local.socket = "/var/run/docker.sock";
    };

    widgets = [
      { openmeteo = {
          label = config.networking.hostName;
          # timezone = "Europe/Berlin"; # set timezone to your locale
        };
      }
      { greeting = { text = "All services are Tailscale-only"; }; }
    ];

    services = [
      {
        "Home" = [
          {
            "Sun Schedule" = {
              href = "http://neurosys:8085";
              siteMonitor = "http://localhost:8085";
              description = "Circadian light schedule editor — Hue lights via Home Assistant.";
              icon = "home-assistant";
            };
          }
        ];
      }
      {
        "Infrastructure" = [
          {
            "Prometheus" = {
              siteMonitor = "http://localhost:9090/-/healthy";
              description = "Metrics + alerts — localhost-only, agents query /api/v1/alerts.";
              icon = "prometheus";
            };
          }
          {
            "Syncthing" = {
              siteMonitor = "http://localhost:8384";
              description = "File sync — localhost-only, agents interact via filesystem.";
              icon = "syncthing";
            };
          }
          {
            "Restic B2" = {
              href = "https://secure.backblaze.com/b2_buckets.htm";
              description = "Daily backups — 7 daily, 5 weekly, 12 monthly retention.";
              icon = "backblaze-b2";
              widget = {
                type = "customapi";
                url = "http://localhost:9090/api/v1/query?query=time()-restic_backup_last_run_timestamp";
                mappings = [
                  {
                    field = "data.result.0.value.1";
                    label = "Last Backup";
                    format = "duration";
                    scale = 1;
                    suffix = " ago";
                  }
                ];
              };
            };
          }
        ];
      }
      {
        "Parts" = [
          {
            "Parts Tools" = {
              siteMonitor = "http://localhost:8080";
              description = "Gateway + Telegram bot — tool execution, policy, approvals.";
              icon = "node-js";
            };
          }
          {
            "Parts Agent" = {
              siteMonitor = "http://localhost:3001";
              description = "Session management + LLM dispatch.";
              icon = "node-js";
            };
          }
        ];
      }
    ];
  };
}
