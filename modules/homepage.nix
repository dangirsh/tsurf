# modules/homepage.nix
# @decision HP-01: Use NixOS-native homepage-dashboard service; listen on 0.0.0.0 for Tailscale reachability.
{ config, pkgs, ... }: {
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    allowedHosts = "100.127.245.9:8082,100.127.245.9,acfs,localhost";

    settings = {
      title = "acfs";
      theme = "dark";
      color = "slate";
      headerStyle = "clean";
      statusStyle = "dot";
    };

    docker = {
      local.socket = "/var/run/docker.sock";
    };

    widgets = [
      { openmeteo = { label = "acfs"; timezone = "Europe/Berlin"; }; }
      { greeting = { text = "All services are Tailscale-only"; }; }
    ];

    services = [
      {
        "Monitoring" = [
          {
            "Prometheus" = {
              href = "http://100.127.245.9:9090";
              siteMonitor = "http://localhost:9090/-/healthy";
              description = "Metrics + alerts — 15s scrape, 90d retention. Agents query /api/v1/alerts.";
              icon = "prometheus";
            };
          }
        ];
      }
      {
        "Sync" = [
          {
            "Syncthing" = {
              href = "http://100.127.245.9:8384";
              siteMonitor = "http://localhost:8384";
              description = "File sync — bidirectional sync across devices with staggered versioning.";
              icon = "syncthing";
            };
          }
        ];
      }
      {
        "Applications" = [
          {
            "claw-swap" = {
              href = "https://claw-swap.com";
              siteMonitor = "http://localhost:80";
              description = "Trading platform — Caddy + Node.js + PostgreSQL.";
              server = "local";
              container = "claw-swap-app";
              icon = "caddy";
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
              href = "http://100.127.245.9:8123";
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
