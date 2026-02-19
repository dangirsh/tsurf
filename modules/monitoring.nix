# modules/monitoring.nix
# @decision MON-02: Scrape node metrics every 15s with 90-day retention for operational history.
# @decision MON-05: Alertmanager, ntfy, Grafana removed — agents query Prometheus /api/v1/alerts directly.
# @decision MON-06: Prometheus localhost-only — no web dashboard, agents query API from localhost.
# @decision MON-07: Textfile collector exposes restic backup timestamp for staleness alerting.
{ config, pkgs, ... }: {

  # Directory for node_exporter textfile collector .prom files
  systemd.tmpfiles.rules = [
    "d /var/lib/prometheus-node-exporter 0755 root root -"
  ];

  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = [
      "systemd"
      "processes"
      "tcpstat"
      "textfile"
    ];
    extraFlags = [
      "--collector.textfile.directory=/var/lib/prometheus-node-exporter"
    ];
  };

  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
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
              {
                alert = "BackupStale";
                expr = ''
                  (time() - restic_backup_last_run_timestamp) > 36 * 3600
                '';
                for = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "Restic backup stale on {{ $labels.instance }}";
                  description = "Last restic backup is older than 36 hours on {{ $labels.instance }}.";
                };
              }
            ];
          }
        ];
      }))
    ];
  };
}
