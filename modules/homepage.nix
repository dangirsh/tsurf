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
            "Grafana" = {
              href = "http://100.127.245.9:3000";
              siteMonitor = "http://localhost:3000/api/health";
              description = "System dashboards — CPU, memory, disk, network. Node Exporter Full pre-provisioned.";
              icon = "grafana";
            };
          }
          {
            "Prometheus" = {
              href = "http://100.127.245.9:9090";
              siteMonitor = "http://localhost:9090/-/healthy";
              description = "Metrics scraper — 15s interval, 90-day retention. Alerts for disk, memory, CPU, systemd failures.";
              icon = "prometheus";
            };
          }
          {
            "Alertmanager" = {
              href = "http://100.127.245.9:9093";
              siteMonitor = "http://localhost:9093/-/healthy";
              description = "Alert routing — forwards to ntfy via alertmanager-ntfy bridge. Use Silences tab to mute.";
              icon = "alertmanager";
            };
          }
        ];
      }
      {
        "Notifications & Sync" = [
          {
            "ntfy" = {
              href = "http://100.127.245.9:2586";
              siteMonitor = "http://localhost:2586/v1/health";
              description = "Push notifications — topics: alerts, deploys, security. Subscribe via Android app.";
              icon = "ntfy";
            };
          }
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
