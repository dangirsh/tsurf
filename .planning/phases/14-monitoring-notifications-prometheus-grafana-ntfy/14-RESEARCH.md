# Phase 14: Monitoring + Notifications - Research

**Researched:** 2026-02-18
**Domain:** NixOS declarative monitoring (Prometheus, Grafana, ntfy-sh, Alertmanager)
**Confidence:** HIGH

## Summary

This phase adds a declarative monitoring and notification stack to the acfs NixOS server. All four core components -- Prometheus, node_exporter, Grafana, and ntfy-sh -- have first-class NixOS modules in nixpkgs with well-documented configuration options. Additionally, Alertmanager and alertmanager-ntfy are both available as NixOS modules, providing a complete pipeline from metric collection through alerting to push notification delivery.

The architecture follows a layered approach: node_exporter scrapes system metrics, Prometheus stores time-series data and evaluates alert rules, Alertmanager routes alerts to ntfy via the alertmanager-ntfy bridge (which is a NixOS module in nixpkgs), and ntfy delivers notifications to Android (via WebSocket instant delivery) and email (via SMTP). Grafana provides dashboards accessible only via Tailscale, following the same trustedInterfaces security pattern already used by Syncthing and Home Assistant.

For non-Prometheus notification sources (deploy script, fail2ban, future restic backups), ntfy is called directly via curl POST -- no Alertmanager needed. This dual-path design keeps things simple: structured metric-based alerts go through Prometheus/Alertmanager, while event-based notifications go direct to ntfy.

**Primary recommendation:** Deploy all components as native NixOS services in a single `modules/monitoring.nix` module. Use the existing trustedInterfaces pattern for Grafana/ntfy access control. Start with 5 critical alert rules only, add more based on actual incidents.

## Standard Stack

### Core
| Component | NixOS Module | Purpose | Why Standard |
|-----------|-------------|---------|--------------|
| Prometheus | `services.prometheus` | Time-series metrics storage + alert evaluation | First-class NixOS module, ecosystem standard |
| node_exporter | `services.prometheus.exporters.node` | System metrics (CPU, memory, disk, systemd) | Built into Prometheus NixOS module |
| Grafana | `services.grafana` | Dashboard visualization | First-class NixOS module, declarative provisioning |
| ntfy-sh | `services.ntfy-sh` | Push notifications (Android + email) | First-class NixOS module, HTTP API |
| Alertmanager | `services.prometheus.alertmanager` | Alert routing and deduplication | First-class NixOS module |
| alertmanager-ntfy | `services.prometheus.alertmanager-ntfy` | Bridge: Alertmanager webhook -> ntfy topics | In nixpkgs as NixOS module (no external flake needed) |

### Supporting
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `sops.secrets."grafana-admin-password"` | Secure Grafana admin password | Always -- avoid Nix store exposure |
| `sops.secrets."ntfy-smtp-password"` | SMTP credentials for email delivery | When email notifications are configured |
| `environment.etc."grafana-dashboards/"` | Provisioned dashboard JSON files | Always -- ship Node Exporter Full dashboard |
| systemd `OnFailure` units | Direct ntfy notification for service crashes | For services not monitored by Prometheus |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Prometheus | VictoriaMetrics | Lower memory; escape hatch if Prometheus overhead is surprising (unlikely with 96GB RAM) |
| alertmanager-ntfy bridge | Direct Alertmanager webhook_configs to ntfy | Simpler but loses ntfy-specific formatting (priority, tags, templates) |
| Grafana dashboard provisioning | Manual Grafana UI setup | Non-declarative; would not survive rebuild |

### Installation

All components are NixOS modules -- no package installation needed. Just enable the services:

```nix
# All in modules/monitoring.nix -- no flake inputs required
services.prometheus.enable = true;
services.prometheus.exporters.node.enable = true;
services.grafana.enable = true;
services.ntfy-sh.enable = true;
services.prometheus.alertmanager.enable = true;
services.prometheus.alertmanager-ntfy.enable = true;
```

## Architecture Patterns

### Recommended Module Structure

```
modules/
  monitoring.nix          # Prometheus + node_exporter + Alertmanager + alertmanager-ntfy + alert rules
  grafana.nix             # Grafana server + provisioned datasources + dashboards
  ntfy.nix                # ntfy-sh server + access control
  networking.nix          # (existing) -- no changes needed, trustedInterfaces already covers
  secrets.nix             # (existing) -- add grafana-admin-password, ntfy-smtp-password
scripts/
  deploy.sh              # (existing) -- add ntfy notification on success/failure
```

Alternative: single `modules/monitoring.nix` for all monitoring. Splitting into 3 files is better for readability since each component has distinct configuration.

### Pattern 1: Tailscale-Only Service Access (existing pattern)
**What:** Services bind to 0.0.0.0 but ports are NOT in `firewall.allowedTCPPorts`. Since `tailscale0` is a trustedInterface, services are only accessible via Tailscale IP.
**When to use:** For all monitoring web UIs (Grafana, ntfy).
**Already proven by:** Syncthing (port 8384), Home Assistant (port 8123).

```nix
# Grafana: bind 0.0.0.0 but don't open firewall port
services.grafana.settings.server = {
  http_addr = "0.0.0.0";  # Required -- tailscale0 may not exist at boot
  http_port = 3000;
};
# Port 3000 is NOT in networking.firewall.allowedTCPPorts
# tailscale0 is already a trustedInterface in networking.nix
```

### Pattern 2: Prometheus Alert Rules as Nix Expressions
**What:** Alert rules written as Nix attribute sets, converted to JSON via `builtins.toJSON`, referenced via `ruleFiles`.
**When to use:** For all Prometheus alerting rules.

```nix
# Source: https://cs-syd.eu/posts/2025-07-20-highly-available-monitoring-with-prometheus-and-alertmanager-on-nixos
services.prometheus.ruleFiles = [
  (pkgs.writeText "alert-rules.json" (builtins.toJSON {
    groups = [{
      name = "system";
      rules = [
        {
          alert = "InstanceDown";
          expr = "up < 1";
          for = "2m";
          labels = { severity = "critical"; };
          annotations = {
            summary = "Instance {{ $labels.instance }} is down";
          };
        }
        {
          alert = "DiskSpaceLow";
          expr = ''(node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 10'';
          for = "5m";
          labels = { severity = "critical"; };
          annotations = {
            summary = "Disk space below 10% on {{ $labels.instance }}";
          };
        }
      ];
    }];
  }))
];
```

### Pattern 3: Grafana Dashboard Provisioning with fetchurl
**What:** Download community dashboard JSON from Grafana API, provision via `environment.etc`.
**When to use:** For the Node Exporter Full dashboard (ID 1860).

```nix
# Source: https://blog.gk.wtf/posts/nixos-monitoring/
services.grafana.provision = {
  enable = true;
  datasources.settings.datasources = [{
    name = "Prometheus";
    type = "prometheus";
    url = "http://localhost:${toString config.services.prometheus.port}";
    isDefault = true;
    editable = false;
  }];
  dashboards.settings.providers = [{
    name = "default";
    disableDeletion = true;
    options.path = "/etc/grafana-dashboards";
    options.foldersFromFilesStructure = true;
  }];
};

environment.etc."grafana-dashboards/node-exporter-full.json".source =
  builtins.fetchurl {
    url = "https://grafana.com/api/dashboards/1860/revisions/37/download";
    sha256 = "FIXME";  # Compute with: nix-prefetch-url <url>
  };
```

### Pattern 4: Dual-Path Notification Architecture
**What:** Metric-based alerts flow through Prometheus -> Alertmanager -> alertmanager-ntfy -> ntfy. Event-based notifications go direct to ntfy via curl.
**When to use:** Always -- this separates concerns cleanly.

```
Metric alerts (threshold-based):
  node_exporter -> Prometheus -> Alertmanager -> alertmanager-ntfy -> ntfy -> Android/email

Event notifications (one-shot):
  deploy.sh ---curl POST---> ntfy -> Android/email
  fail2ban  ---curl POST---> ntfy -> Android/email
  restic    ---curl POST---> ntfy -> Android/email
  systemd OnFailure ---------> ntfy -> Android/email
```

### Pattern 5: systemd OnFailure for Service Crash Notifications
**What:** Templated systemd service that sends ntfy notification when any monitored service fails.
**Source:** https://discourse.nixos.org/t/how-to-setup-a-notification-in-case-of-systemd-service-failure/51706

```nix
# Reusable notification service template
systemd.services."ntfy-failure@" = {
  description = "Failure notification for %i";
  serviceConfig.Type = "oneshot";
  scriptArgs = "%i";
  script = ''
    ${pkgs.curl}/bin/curl \
      --fail --show-error --silent \
      --max-time 10 --retry 3 \
      -H "Title: Service failed: $1" \
      -H "Priority: high" \
      -H "Tags: rotating_light" \
      -d "$1 exited with errors on $(hostname)" \
      http://localhost:2586/alerts
  '';
};

# Attach to any critical service:
systemd.services.docker.unitConfig.OnFailure = [ "ntfy-failure@docker.service" ];
```

### Pattern 6: Grafana Admin Password via sops-nix
**What:** Use Grafana's `$__file{}` provider to read admin password from a sops-managed file, avoiding Nix store exposure.
**Source:** https://mynixos.com/nixpkgs/option/services.grafana.settings.security.admin_password

```nix
sops.secrets."grafana-admin-password" = {
  owner = "grafana";
  group = "grafana";
};

services.grafana.settings.security = {
  admin_user = "admin";
  admin_password = "$__file{${config.sops.secrets."grafana-admin-password".path}}";
  secret_key = "$__file{${config.sops.secrets."grafana-secret-key".path}}";
};
```

### Anti-Patterns to Avoid
- **Binding to 127.0.0.1:** Seems safer but blocks Tailscale access. Use 0.0.0.0 + trustedInterfaces instead (proven pattern in this codebase).
- **Alerting on everything from day one:** Start with 5 rules (instance down, disk low, memory low, systemd unit failed, high CPU). Add more only after real incidents.
- **Skipping Alertmanager:** Tempting to pipe Prometheus alerts directly, but Alertmanager provides deduplication, grouping, and silencing which become essential quickly.
- **Storing Grafana password in Nix config:** Will end up in world-readable Nix store. Always use `$__file{}` provider with sops.
- **Using deprecated Promtail for log collection:** Promtail is EOL (March 2026). If log aggregation is added later, use Grafana Alloy. But log aggregation is out of scope for this phase.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Metric collection | Custom scripts polling /proc | node_exporter | 100+ collectors, battle-tested, standard PromQL queries |
| Alert routing | Custom if/then in bash | Alertmanager | Deduplication, grouping, silencing, rate limiting |
| Alert-to-ntfy bridge | Custom webhook handler | alertmanager-ntfy (nixpkgs module) | Handles formatting, priority, tags, templates, retries |
| Dashboard provisioning | Manual Grafana UI clicks | Grafana provision + environment.etc | Declarative, survives rebuild, version-controlled |
| Service failure notification | Monitoring cron checking systemctl | systemd OnFailure + ntfy-failure@ template | Native systemd, zero overhead, instant detection |
| Push notification delivery | Custom Firebase/APNS integration | ntfy-sh | HTTP API, Android app, email delivery, NixOS module |

**Key insight:** The entire monitoring pipeline -- from metric scraping through alerting to phone notification -- is achievable with 6 NixOS modules, zero external flake inputs, and approximately 150 lines of Nix configuration.

## Common Pitfalls

### Pitfall 1: Grafana v12 Dashboard Provisioning Bug
**What goes wrong:** Dashboard JSON files are created correctly but Grafana cannot discover them because the provider YAML file is not generated by the NixOS module.
**Why it happens:** NixOS issue #407496 -- affects Grafana v12 on NixOS unstable (25.05). Status: open, stale.
**How to avoid:** This project uses nixos-25.11 which may have a different Grafana version. Verify after deployment: check that `/var/lib/grafana/provisioning/dashboards/` contains a YAML provider file. If missing, add a workaround via `systemd.tmpfiles` or manual activation script.
**Warning signs:** Grafana UI shows no dashboards despite provisioning being configured.

### Pitfall 2: ntfy Android Push Without Firebase
**What goes wrong:** Notifications arrive with delay on Android or not at all.
**Why it happens:** Self-hosted ntfy does NOT use Firebase for push. It uses WebSocket connections which require the Android app's "Instant Delivery" foreground service to be enabled.
**How to avoid:** After installing the ntfy Android app (F-Droid version recommended for self-hosted): (1) add the self-hosted server URL, (2) enable "Instant Delivery" in subscription settings. The F-Droid version enables instant delivery by default.
**Warning signs:** Notifications only arrive when the app is in foreground.

### Pitfall 3: Grafana Admin Password in Nix Store
**What goes wrong:** Admin password visible to any user on the system via `/nix/store/`.
**Why it happens:** Setting `admin_password = "literal-password"` writes it into the Nix store.
**How to avoid:** Always use `$__file{/run/secrets/grafana-admin-password}` syntax with sops-nix secret.
**Warning signs:** `grep -r "admin_password" /nix/store/` returns hits.

### Pitfall 4: ntfy Accessible from Public Internet
**What goes wrong:** Anyone can publish to your ntfy topics, potentially causing notification spam or reading sensitive alerts.
**Why it happens:** ntfy defaults to `auth-default-access = "read-write"`. If port is accidentally opened in firewall, anyone can publish.
**How to avoid:** (1) Set `auth-default-access = "deny-all"`, (2) do NOT add ntfy port to `allowedTCPPorts`, (3) rely on trustedInterfaces for Tailscale access, (4) for internal services on the same host, use `localhost:2586`.
**Warning signs:** `nmap -p 2586 <public-ip>` shows port open.

### Pitfall 5: Prometheus Retention Filling Disk
**What goes wrong:** Prometheus TSDB grows unbounded and fills the 350GB NVMe.
**Why it happens:** Default retention is 15 days but scrape interval and number of metrics affect storage size. With 10s scrape interval and many collectors, data accumulates faster.
**How to avoid:** Set explicit retention: `services.prometheus.retentionTime = "90d"` and optionally `extraFlags = ["--storage.tsdb.retention.size=20GB"]`. Monitor with the disk space alert rule.
**Warning signs:** `/var/lib/prometheus2/` growing faster than expected.

### Pitfall 6: Alertmanager Configuration Ordering
**What goes wrong:** Alerts don't route to ntfy.
**Why it happens:** Alertmanager `configuration.route` must reference receivers that exist. The alertmanager-ntfy bridge must be running before Alertmanager tries to send to it. The webhook URL must match the alertmanager-ntfy listen address.
**How to avoid:** Use `systemd.services.alertmanager.after = [ "alertmanager-ntfy.service" ]` if ordering issues arise. Verify webhook URL matches alertmanager-ntfy's `settings.http.addr`.
**Warning signs:** Alertmanager logs show webhook delivery failures.

### Pitfall 7: fail2ban ntfy Action Missing norestored
**What goes wrong:** After fail2ban service restart, duplicate ban notifications flood ntfy for all currently-banned IPs.
**Why it happens:** fail2ban re-applies bans on restart unless `norestored = true` is set in the action.
**How to avoid:** Always set `norestored = true` in the ntfy action definition.
**Warning signs:** Burst of ban notifications after system reboot or fail2ban restart.

## Code Examples

### Complete Prometheus + node_exporter + Alertmanager Configuration

```nix
# modules/monitoring.nix
# Source: https://wiki.nixos.org/wiki/Prometheus + verified NixOS module options
{ config, pkgs, ... }: {

  # --- node_exporter ---
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = [
      "systemd"
      "processes"
      "tcpstat"
    ];
  };

  # --- Prometheus ---
  services.prometheus = {
    enable = true;
    port = 9090;
    retentionTime = "90d";
    globalConfig.scrape_interval = "15s";

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{
          targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ];
        }];
      }
      {
        job_name = "prometheus";
        static_configs = [{
          targets = [ "localhost:${toString config.services.prometheus.port}" ];
        }];
      }
    ];

    alertmanagers = [{
      static_configs = [{
        targets = [ "localhost:9093" ];
      }];
    }];

    ruleFiles = [
      (pkgs.writeText "alert-rules.json" (builtins.toJSON {
        groups = [{
          name = "system";
          rules = [
            {
              alert = "InstanceDown";
              expr = "up < 1";
              for = "2m";
              labels = { severity = "critical"; };
              annotations = {
                summary = "Instance {{ $labels.instance }} is down";
                description = "{{ $labels.instance }} of job {{ $labels.job }} has been down for more than 2 minutes.";
              };
            }
            {
              alert = "DiskSpaceCritical";
              expr = ''(node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 10'';
              for = "5m";
              labels = { severity = "critical"; };
              annotations = {
                summary = "Disk space below 10% on {{ $labels.instance }}";
              };
            }
            {
              alert = "DiskSpaceWarning";
              expr = ''(node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 20'';
              for = "10m";
              labels = { severity = "warning"; };
              annotations = {
                summary = "Disk space below 20% on {{ $labels.instance }}";
              };
            }
            {
              alert = "HighMemoryUsage";
              expr = "(node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 < 10";
              for = "5m";
              labels = { severity = "critical"; };
              annotations = {
                summary = "Available memory below 10% on {{ $labels.instance }}";
              };
            }
            {
              alert = "HighCpuUsage";
              expr = ''100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90'';
              for = "10m";
              labels = { severity = "warning"; };
              annotations = {
                summary = "CPU usage above 90% for 10 minutes on {{ $labels.instance }}";
              };
            }
            {
              alert = "SystemdUnitFailed";
              expr = ''node_systemd_unit_state{state="failed"} == 1'';
              for = "1m";
              labels = { severity = "critical"; };
              annotations = {
                summary = "Systemd unit {{ $labels.name }} failed on {{ $labels.instance }}";
              };
            }
          ];
        }];
      }))
    ];
  };

  # --- Alertmanager ---
  services.prometheus.alertmanager = {
    enable = true;
    port = 9093;
    configuration = {
      global = {};
      route = {
        receiver = "ntfy";
        group_wait = "30s";
        group_interval = "5m";
        repeat_interval = "4h";
        routes = [
          {
            match = { severity = "critical"; };
            receiver = "ntfy";
            repeat_interval = "1h";
          }
        ];
      };
      receivers = [{
        name = "ntfy";
        webhook_configs = [{
          url = "http://127.0.0.1:8000/hook";
        }];
      }];
    };
  };

  # --- alertmanager-ntfy bridge ---
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
            { tag = "rotating_light"; condition = ''status == "firing"''; }
            { tag = "+1"; condition = ''status == "resolved"''; }
          ];
          templates = {
            title = ''{{ if eq .Status "resolved" }}Resolved: {{ end }}{{ index .Annotations "summary" }}'';
            description = ''{{ index .Annotations "description" }}'';
          };
        };
      };
    };
  };
}
```

### Complete ntfy-sh Configuration

```nix
# modules/ntfy.nix
# Source: https://docs.ntfy.sh/config/ + https://mynixos.com/options/services.ntfy-sh
{ config, pkgs, ... }: {

  services.ntfy-sh = {
    enable = true;
    settings = {
      listen-http = ":2586";
      base-url = "http://localhost:2586";
      behind-proxy = false;

      # Security: deny by default, localhost services send without auth
      auth-default-access = "deny-all";

      # Android push: NOT using upstream-base-url (self-hosted uses WebSocket)
      # upstream-base-url is only needed for iOS push forwarding

      # Persistence
      cache-file = "/var/lib/ntfy-sh/cache.db";
      cache-duration = "24h";

      # Email delivery (for non-urgent notifications)
      # smtp-sender-addr = "smtp.example.com:587";
      # smtp-sender-user = "ntfy@example.com";
      # smtp-sender-from = "ntfy@example.com";
      # Note: smtp-sender-pass should come from environmentFile
    };
    # For SMTP password and other secrets:
    # environmentFile = config.sops.secrets."ntfy-env".path;
  };

  # ntfy port NOT in firewall -- Tailscale-only access
  # localhost services (alertmanager-ntfy, fail2ban, deploy.sh) use localhost:2586
}
```

### Complete Grafana Configuration

```nix
# modules/grafana.nix
# Source: https://wiki.nixos.org/wiki/Grafana
{ config, pkgs, ... }: {

  sops.secrets."grafana-admin-password" = {
    owner = "grafana";
    group = "grafana";
  };
  sops.secrets."grafana-secret-key" = {
    owner = "grafana";
    group = "grafana";
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "0.0.0.0";  # Tailscale access (trustedInterfaces pattern)
        http_port = 3000;
        enable_gzip = true;
      };
      security = {
        admin_user = "admin";
        admin_password = "$__file{${config.sops.secrets."grafana-admin-password".path}}";
        secret_key = "$__file{${config.sops.secrets."grafana-secret-key".path}}";
      };
      analytics.reporting_enabled = false;
    };

    provision = {
      enable = true;
      datasources.settings = {
        datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            url = "http://localhost:${toString config.services.prometheus.port}";
            isDefault = true;
            editable = false;
          }
          {
            name = "Alertmanager";
            type = "alertmanager";
            url = "http://localhost:${toString config.services.prometheus.alertmanager.port}";
            editable = false;
            jsonData.implementation = "prometheus";
          }
        ];
        deleteDatasources = [];
      };
      dashboards.settings.providers = [{
        name = "default";
        disableDeletion = true;
        options = {
          path = "/etc/grafana-dashboards";
          foldersFromFilesStructure = true;
        };
      }];
    };
  };

  # Provision Node Exporter Full dashboard (ID 1860)
  environment.etc."grafana-dashboards/node-exporter-full.json".source =
    builtins.fetchurl {
      url = "https://grafana.com/api/dashboards/1860/revisions/37/download";
      sha256 = "0000000000000000000000000000000000000000000000000000"; # FIXME: nix-prefetch-url
    };

  # Grafana port NOT in firewall -- Tailscale-only access
}
```

### fail2ban ntfy Action

```nix
# Add to modules/networking.nix (alongside existing fail2ban config)
# Source: https://wiki.nixos.org/wiki/Fail2ban + https://gist.github.com/kddlb/4ea43b2123e1275786951e34c47a91da
environment.etc."fail2ban/action.d/ntfy.local".text = ''
  [Definition]
  norestored = true
  actionban = ${pkgs.curl}/bin/curl \
    --fail --show-error --silent \
    --max-time 10 --retry 3 \
    -H "Title: fail2ban: <ip> banned" \
    -H "Priority: default" \
    -H "Tags: police_car_light" \
    -d "<name> jail banned <ip> after <failures> failures on $(hostname)" \
    http://localhost:2586/security
'';

# Add ntfy action to existing fail2ban jails
services.fail2ban.jails.sshd.settings = {
  action = "%(action_)s\n            ntfy";
};
```

### Deploy Script ntfy Notification

```bash
# Add to scripts/deploy.sh at the end of success/failure sections
# Success notification:
curl --silent --max-time 10 \
  -H "Title: Deploy succeeded" \
  -H "Priority: low" \
  -H "Tags: white_check_mark" \
  -d "acfs deployed (parts: $PARTS_REV_SHORT) in $((DURATION / 60))m $((DURATION % 60))s" \
  http://localhost:2586/deploys 2>/dev/null || true

# Failure notification:
curl --silent --max-time 10 \
  -H "Title: Deploy FAILED" \
  -H "Priority: high" \
  -H "Tags: rotating_light" \
  -d "acfs deploy failed after $((DURATION / 60))m $((DURATION % 60))s. Check containers." \
  http://localhost:2586/deploys 2>/dev/null || true
```

Note: deploy.sh runs locally, not on the server. The ntfy curl should target the server's Tailscale IP (e.g., `http://<tailscale-ip>:2586/deploys`) or use SSH to POST on the server. Alternative: use the public ntfy.sh for deploy notifications since they are not sensitive.

### systemd OnFailure Template for All Critical Services

```nix
# Reusable notification template service
# Source: https://discourse.nixos.org/t/how-to-setup-a-notification-in-case-of-systemd-service-failure/51706
systemd.services."ntfy-failure@" = {
  description = "Failure notification for %i";
  serviceConfig.Type = "oneshot";
  scriptArgs = "%i";
  path = [ pkgs.curl pkgs.hostname ];
  script = ''
    curl \
      --fail --show-error --silent \
      --max-time 10 --retry 3 \
      -H "Title: Service crashed: $1" \
      -H "Priority: urgent" \
      -H "Tags: skull" \
      -d "$1 failed on $(hostname) at $(date -Iseconds)" \
      http://localhost:2586/alerts
  '';
};

# Attach to critical services
systemd.services.docker.unitConfig.OnFailure = [ "ntfy-failure@docker.service" ];
systemd.services.prometheus.unitConfig.OnFailure = [ "ntfy-failure@prometheus.service" ];
systemd.services.grafana.unitConfig.OnFailure = [ "ntfy-failure@grafana.service" ];
```

## State of the Art

| Old Approach | Current Approach (2026) | When Changed | Impact |
|--------------|-------------------------|--------------|--------|
| Alertmanager + custom webhook scripts | alertmanager-ntfy (in nixpkgs) | 2024 (merged to nixpkgs) | No external flake input needed |
| Promtail for log collection | Grafana Alloy | Feb 2025 (deprecation) | Out of scope for this phase but noted |
| Email-only alerting | ntfy push + email | 2023-2025 | Instant Android push for critical alerts |
| Manual Grafana dashboard setup | Declarative provisioning + fetchurl | Long-established | Dashboards survive rebuild |
| Custom monitoring scripts | Prometheus + node_exporter | Long-established | Standard PromQL, community dashboards |

**Deprecated/outdated:**
- **Promtail**: EOL March 2026. Do NOT use for log collection. Grafana Alloy is the replacement (but not needed for this phase).
- **alertmanager-ntfy as external flake**: Now in nixpkgs. No need to add as a flake input.

## Open Questions

1. **Grafana version on nixos-25.11**
   - What we know: There is a Grafana v12 dashboard provisioning bug on unstable (25.05). This project uses nixos-25.11.
   - What's unclear: Whether nixos-25.11 includes Grafana v12 and whether the bug is fixed there.
   - Recommendation: Deploy and verify. If dashboards don't appear, apply the workaround (manual provider YAML via tmpfiles). LOW risk -- the bug is well-documented with a known workaround.

2. **ntfy email delivery SMTP provider**
   - What we know: ntfy supports SMTP for email delivery. Configuration requires smtp-sender-addr, smtp-sender-user, smtp-sender-pass, smtp-sender-from.
   - What's unclear: Which SMTP provider the user wants to use (Gmail, Fastmail, SendGrid, etc.). SMTP password needs to go through sops-nix.
   - Recommendation: Make SMTP configuration optional in the module (commented out). User can configure when ready. Push notifications (Android) work without email.

3. **ntfy access control for localhost services**
   - What we know: `auth-default-access = "deny-all"` blocks all unauthenticated access. But localhost services (alertmanager-ntfy, fail2ban action, deploy script) need to publish without auth.
   - What's unclear: Whether ntfy allows localhost bypass or if we need to create a write-only token.
   - Recommendation: Test with `deny-all` first. If localhost is blocked, either (a) create a write token via `ntfy user add` and pass it in curl headers, or (b) use `write-only` as default access since the service is only reachable via Tailscale anyway.

4. **Dashboard JSON sha256 hash**
   - What we know: `builtins.fetchurl` requires a sha256 hash. The Node Exporter Full dashboard (ID 1860) URL is `https://grafana.com/api/dashboards/1860/revisions/37/download`.
   - What's unclear: The exact hash (must be computed at build time).
   - Recommendation: Run `nix-prefetch-url <url>` during implementation to get the hash. This is a mechanical step, not a design question.

5. **Deploy script notification path**
   - What we know: deploy.sh runs on the local machine, not the server. ntfy listens on the server.
   - What's unclear: Whether to target the server's Tailscale IP from the local machine, or use SSH to curl on the server, or use public ntfy.sh for deploy notifications.
   - Recommendation: Use the server's Tailscale IP from the local machine (e.g., `http://100.x.y.z:2586/deploys`). Tailscale is already required for deployment. Fallback: use public ntfy.sh with a unique topic name for deploy-only notifications.

## Sources

### Primary (HIGH confidence)
- [NixOS Wiki: Prometheus](https://wiki.nixos.org/wiki/Prometheus) - Module options, node_exporter config, scrapeConfigs
- [NixOS Wiki: Grafana](https://wiki.nixos.org/wiki/Grafana) - Provisioning datasources, dashboards, server settings
- [NixOS Wiki: Fail2ban](https://wiki.nixos.org/wiki/Fail2ban) - ntfy action integration pattern
- [ntfy.sh Official Docs: Config](https://docs.ntfy.sh/config/) - Server settings, SMTP, upstream, auth
- [ntfy.sh Official Docs: Phone](https://docs.ntfy.sh/subscribe/phone/) - Android setup, WebSocket instant delivery
- [MyNixOS: services.ntfy-sh](https://mynixos.com/options/services.ntfy-sh) - NixOS module options
- [MyNixOS: alertmanager-ntfy](https://mynixos.com/nixpkgs/package/alertmanager-ntfy) - Confirmed in nixpkgs
- [MyNixOS: services.prometheus.alertmanager-ntfy.settings](https://mynixos.com/nixpkgs/option/services.prometheus.alertmanager-ntfy.settings) - NixOS module confirmed
- [alexbakker/alertmanager-ntfy](https://github.com/alexbakker/alertmanager-ntfy) - NixOS module config examples

### Secondary (MEDIUM confidence)
- [CS SYD: Prometheus + Alertmanager on NixOS](https://cs-syd.eu/posts/2025-07-20-highly-available-monitoring-with-prometheus-and-alertmanager-on-nixos) - Alert rules Nix syntax, Alertmanager config
- [Gian Klug: NixOS Monitoring on Proxmox](https://blog.gk.wtf/posts/nixos-monitoring/) - Grafana dashboard fetchurl, alertmanager-ntfy integration, complete stack example
- [NixOS Discourse: systemd failure notification](https://discourse.nixos.org/t/how-to-setup-a-notification-in-case-of-systemd-service-failure/51706) - OnFailure + ntfy template pattern
- [Prometheus Alert Rules Gist](https://gist.github.com/krisek/62a98e2645af5dce169a7b506e999cd8) - PromQL expressions for common alerts
- [Prometheus Storage Docs](https://prometheus.io/docs/prometheus/latest/storage/) - Retention configuration

### Tertiary (LOW confidence)
- [GitHub Issue #407496: Grafana v12 provisioning bug](https://github.com/NixOS/nixpkgs/issues/407496) - May or may not affect nixos-25.11 (needs validation)
- [GitHub Issue #294637: ntfy-sh missing secure settings](https://github.com/NixOS/nixpkgs/issues/294637) - May affect environmentFile behavior (needs validation)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All components are first-class NixOS modules in nixpkgs, verified via official wiki and MyNixOS
- Architecture: HIGH - Patterns proven in this codebase (trustedInterfaces) and verified against multiple NixOS blog examples
- Pitfalls: HIGH - Sourced from official docs, NixOS issues, and community experience
- Code examples: MEDIUM-HIGH - Synthesized from official docs and verified examples, but exact module option compatibility with nixos-25.11 should be validated during implementation
- Alert rules: HIGH - Standard PromQL expressions verified against Prometheus docs

**Research date:** 2026-02-18
**Valid until:** 2026-03-20 (30 days - stable domain, established tools)
