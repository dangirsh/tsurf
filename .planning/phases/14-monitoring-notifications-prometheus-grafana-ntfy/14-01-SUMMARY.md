---
phase: 14-monitoring-notifications-prometheus-grafana-ntfy
plan: 14-01
subsystem: observability
tags:
  - nixos
  - prometheus
  - alertmanager
  - ntfy
  - grafana
requires:
  - sops-nix
  - tailscale trustedInterfaces pattern
provides:
  - metrics collection
  - alert routing
  - push notifications
  - dashboards
affects:
  - modules/default.nix
  - modules/networking.nix
  - secrets/acfs.yaml
tech-stack:
  - Prometheus
  - node_exporter
  - Alertmanager
  - alertmanager-ntfy
  - ntfy-sh
  - Grafana
key-files:
  - modules/monitoring.nix
  - modules/ntfy.nix
  - modules/grafana.nix
  - modules/networking.nix
  - modules/default.nix
  - secrets/acfs.yaml
key-decisions:
  - Keep ntfy and Grafana Tailscale-only (no public firewall ports)
  - Use sops file-provider secrets for Grafana credentials
  - Route Alertmanager through alertmanager-ntfy for unified notification policy
duration: "~12m"
completed: "2026-02-18T17:42:43+01:00"
---

Prometheus + Alertmanager + ntfy + Grafana monitoring stack with six alert rules, fail2ban/systemd failure notifications, and sops-managed Grafana secrets.

## Performance
- Duration: ~12 minutes
- Start: 2026-02-18T17:31:00+01:00
- End: 2026-02-18T17:42:43+01:00
- Task count: 3 plan tasks completed
- File count: 6 implementation files changed, 2 planning files added/updated

## Accomplishments
- Added `modules/monitoring.nix` with node_exporter, Prometheus (15s scrape, 90d retention), Alertmanager, alertmanager-ntfy bridge, 6 alert rules, and `ntfy-failure@` systemd `OnFailure` template wiring for `docker`, `prometheus`, and `grafana`.
- Added `modules/ntfy.nix` with ntfy-sh on `:2586`, write-only default access, persistent cache, and SMTP future-config comments.
- Added `modules/grafana.nix` with sops-backed `grafana-admin-password` and `grafana-secret-key`, Prometheus + Alertmanager datasources, and Node Exporter Full dashboard provisioning (ID 1860 rev 37).
- Wired new module imports in `modules/default.nix`.
- Added fail2ban ntfy action (`norestored = true`) and enabled it in sshd jail action chain in `modules/networking.nix`.
- Added encrypted secrets `grafana-admin-password` and `grafana-secret-key` to `secrets/acfs.yaml` via `sops --set`.
- Verification passed: `nix flake check` completed successfully.

## Task Commits
- `9b71b84` `feat(14-01): add monitoring, ntfy, and grafana stack`

## Files Created/Modified
- Created: `modules/monitoring.nix`
- Created: `modules/ntfy.nix`
- Created: `modules/grafana.nix`
- Modified: `modules/default.nix`
- Modified: `modules/networking.nix`
- Modified: `secrets/acfs.yaml`
- Created: `.planning/phases/14-monitoring-notifications-prometheus-grafana-ntfy/14-01-SUMMARY.md`
- Modified: `.planning/STATE.md`

## Decisions Made
- [14-01] Prometheus alert rules stored as JSON via `pkgs.writeText` + `builtins.toJSON` for declarative, generated rule config.
- [14-01] Alertmanager forwards to local `alertmanager-ntfy` webhook on `127.0.0.1:8000`, then publishes to local ntfy topic `alerts`.
- [14-01] Grafana dashboard provisioning uses `environment.etc` at `/etc/grafana-dashboards` with provider `foldersFromFilesStructure = true`.

## Deviations from Plan
- `nix eval --raw '.#nixosConfigurations.acfs.config.services.prometheus.enable'` failed because `--raw` cannot print booleans; validation was completed with `nix eval '.#nixosConfigurations.acfs.config.services.prometheus.enable'` returning `true`.

## Issues Encountered
- `nix flake check` reported pre-existing Home Manager option rename warnings (`programs.ssh.*`, `programs.git.user*`), non-blocking for this plan.

## Next Phase Readiness
- Monitoring/notification baseline is in place and validated.
- Ready for plan `14-02` (generic `notify.sh`/agent completion notifications) to consume local ntfy endpoint.
