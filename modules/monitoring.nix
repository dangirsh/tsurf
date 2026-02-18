# modules/monitoring.nix
# @decision MON-01: Keep monitoring components local-only and route notifications through ntfy.
# @decision MON-02: Scrape node metrics every 15s with 90-day retention for operational history.
# @decision MON-03: Route Alertmanager notifications through alertmanager-ntfy to centralize delivery policy.
# @decision MON-04: Use a shared systemd OnFailure template for critical service crash notifications.
{ config, pkgs, ... }: {

  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = [
      "systemd"
      "processes"
      "tcpstat"
    ];
  };

  services.prometheus = {
    enable = true;
    port = 9090;
    retentionTime = "90d";

    globalConfig = {
      scrape_interval = "15s";
    };

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [
          {
            targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ];
          }
        ];
      }
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = [ "127.0.0.1:${toString config.services.prometheus.port}" ];
          }
        ];
      }
    ];

    alertmanagers = [
      {
        static_configs = [
          {
            targets = [ "127.0.0.1:${toString config.services.prometheus.alertmanager.port}" ];
          }
        ];
      }
    ];

    ruleFiles = [
      (pkgs.writeText "alert-rules.json" (builtins.toJSON {
        groups = [
          {
            name = "acfs-alerts";
            rules = [
              {
                alert = "InstanceDown";
                expr = "up < 1";
                for = "2m";
                labels.severity = "critical";
                annotations = {
                  summary = "Instance down: {{ $labels.instance }}";
                  description = "Prometheus target {{ $labels.instance }} is down.";
                };
              }
              {
                alert = "DiskSpaceCritical";
                expr = ''
                  (node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|overlay"} /
                  node_filesystem_size_bytes{mountpoint="/",fstype!~"tmpfs|overlay"}) < 0.10
                '';
                for = "5m";
                labels.severity = "critical";
                annotations = {
                  summary = "Disk space critical on {{ $labels.instance }}";
                  description = "Root filesystem free space is below 10% on {{ $labels.instance }}.";
                };
              }
              {
                alert = "DiskSpaceWarning";
                expr = ''
                  (node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|overlay"} /
                  node_filesystem_size_bytes{mountpoint="/",fstype!~"tmpfs|overlay"}) < 0.20
                '';
                for = "10m";
                labels.severity = "warning";
                annotations = {
                  summary = "Disk space warning on {{ $labels.instance }}";
                  description = "Root filesystem free space is below 20% on {{ $labels.instance }}.";
                };
              }
              {
                alert = "HighMemoryUsage";
                expr = ''
                  (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.10
                '';
                for = "5m";
                labels.severity = "critical";
                annotations = {
                  summary = "High memory usage on {{ $labels.instance }}";
                  description = "Available memory is below 10% on {{ $labels.instance }}.";
                };
              }
              {
                alert = "HighCpuUsage";
                expr = ''
                  avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100 < 10
                '';
                for = "10m";
                labels.severity = "warning";
                annotations = {
                  summary = "High CPU usage on {{ $labels.instance }}";
                  description = "CPU idle is below 10% on {{ $labels.instance }}.";
                };
              }
              {
                alert = "SystemdUnitFailed";
                expr = ''
                  node_systemd_unit_state{state="failed"} == 1
                '';
                for = "1m";
                labels.severity = "critical";
                annotations = {
                  summary = "Systemd unit failed on {{ $labels.instance }}";
                  description = "Unit {{ $labels.name }} is in failed state on {{ $labels.instance }}.";
                };
              }
            ];
          }
        ];
      }))
    ];
  };

  services.prometheus.alertmanager = {
    enable = true;
    port = 9093;
    configuration = {
      route = {
        receiver = "ntfy";
        group_wait = "30s";
        group_interval = "5m";
        repeat_interval = "4h";
        routes = [
          {
            receiver = "ntfy";
            matchers = [ ''severity="critical"'' ];
            repeat_interval = "1h";
          }
        ];
      };
      receivers = [
        {
          name = "ntfy";
          webhook_configs = [
            {
              url = "http://127.0.0.1:8000/hook";
              send_resolved = true;
            }
          ];
        }
      ];
    };
  };

  services.prometheus.alertmanager-ntfy = {
    enable = true;
    settings = {
      http.addr = "127.0.0.1:8000";
      ntfy = {
        baseurl = "http://localhost:2586";
        notification = {
          topic = "alerts";
          priority = ''status == "firing" ? "high" : "default"'';
          tags = [
            {
              tag = "rotating_light";
              condition = ''status == "firing"'';
            }
            {
              tag = "+1";
              condition = ''status == "resolved"'';
            }
          ];
          templates = {
            title = ''{{ if eq .Status "resolved" }}Resolved: {{ end }}{{ index .Annotations "summary" }}'';
            description = ''{{ index .Annotations "description" }}'';
          };
        };
      };
    };
  };

  systemd.services."ntfy-failure@" = {
    description = "Send ntfy notification for failed service instance %i";
    path = [ pkgs.curl pkgs.hostname ];
    scriptArgs = "%i";
    script = ''
      curl --fail --show-error --silent \
        -H "Title: Service crashed: $1" \
        -H "Priority: urgent" \
        -H "Tags: skull" \
        -d "$1 failed on $(hostname) at $(date -Iseconds)" \
        http://localhost:2586/alerts
    '';
    serviceConfig = {
      Type = "oneshot";
    };
  };

  systemd.services.docker.unitConfig.OnFailure = "ntfy-failure@%n.service";
  systemd.services.prometheus.unitConfig.OnFailure = "ntfy-failure@%n.service";
  systemd.services.grafana.unitConfig.OnFailure = "ntfy-failure@%n.service";
}
