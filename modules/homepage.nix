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
    };

    services = [
      {
        "Monitoring" = [
          {
            "Grafana" = {
              href = "http://100.127.245.9:3000";
              description = "System dashboards — CPU, memory, disk, network. Node Exporter Full pre-provisioned. Login: admin + sops secret.";
              icon = "grafana";
            };
          }
          {
            "Prometheus" = {
              href = "http://100.127.245.9:9090";
              description = "Metrics scraper — 15s interval, 90-day retention. 6 alert rules (disk, memory, CPU, systemd, instance down).";
              icon = "prometheus";
            };
          }
          {
            "Alertmanager" = {
              href = "http://100.127.245.9:9093";
              description = "Alert routing — fires through alertmanager-ntfy bridge to ntfy 'alerts' topic. Check Silences tab to mute.";
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
              description = "Push notifications — topics: alerts (system), deploys (CI), security (fail2ban). Subscribe via Android app.";
              icon = "ntfy";
            };
          }
          {
            "Syncthing" = {
              href = "http://100.127.245.9:8384";
              description = "File sync — bidirectional sync across devices. Staggered versioning. 4 devices configured.";
              icon = "syncthing";
            };
          }
        ];
      }
      {
        "Home" = [
          {
            "Home Assistant" = {
              href = "http://100.127.245.9:8123";
              description = "Home automation — native NixOS service, Tailscale-only access. ESPHome on port 6052.";
              icon = "home-assistant";
            };
          }
        ];
      }
    ];
  };
}
