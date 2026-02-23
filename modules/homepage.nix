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
      { openmeteo = { label = config.networking.hostName; timezone = "Europe/Berlin"; }; }
      { greeting = { text = "All services are Tailscale-only"; }; }
    ];

    services = [
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
        "Applications" = [
          {
            "claw-swap" = {
              href = "https://claw-swap.com";
              description = "Trading platform — nginx + Node.js + PostgreSQL.";
              server = "local";
              container = "claw-swap-app";
              icon = "nginx";
            };
          }
          {
            "dangirsh.org" = {
              href = "https://dangirsh.org";
              description = "Personal website — Hakyll static site served by nginx.";
              icon = "nginx";
            };
          }
          {
            "Parts Tools" = {
              description = "Telegram bot toolkit — API integrations, data pipelines.";
              server = "local";
              container = "parts-tools";
              icon = "docker";
            };
          }
          {
            "Parts Agent" = {
              description = "Autonomous agent — runs tasks via Telegram bot.";
              server = "local";
              container = "parts-agent";
              icon = "docker";
            };
          }
        ];
      }
      {
        "Home" = [
          {
            "Home Assistant" = {
              href = "http://${config.networking.hostName}:8123";
              siteMonitor = "http://localhost:8123";
              description = "Home automation — native NixOS service. ESPHome on port 6052.";
              icon = "home-assistant";
            };
          }
        ];
      }
    ];
  };
}
