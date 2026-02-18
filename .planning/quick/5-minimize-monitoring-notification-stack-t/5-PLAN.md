---
phase: quick-5
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - modules/monitoring.nix
  - modules/ntfy.nix
  - modules/grafana.nix
  - modules/default.nix
  - modules/networking.nix
  - modules/homepage.nix
  - scripts/deploy.sh
  - scripts/notify.sh
  - modules/secrets.nix
autonomous: true
must_haves:
  truths:
    - "Prometheus is running with all 6 alert rules intact"
    - "node_exporter is running and scraped by Prometheus"
    - "Agents can query http://localhost:9090/api/v1/alerts to see firing alerts"
    - "Alertmanager, ntfy, Grafana services are fully removed"
    - "nix flake check passes cleanly"
    - "Deploy script works without ntfy notification calls"
  artifacts:
    - path: "modules/monitoring.nix"
      provides: "Prometheus + node_exporter + alert rules only"
      contains: "services.prometheus.enable"
    - path: "modules/default.nix"
      provides: "Module imports without ntfy.nix or grafana.nix"
  key_links:
    - from: "modules/monitoring.nix"
      to: "Prometheus alert rules"
      via: "ruleFiles"
      pattern: "ruleFiles"
---

<objective>
Strip the monitoring/notification stack down to the bare minimum needed for agent health awareness: Prometheus + node_exporter + alert rules. Remove Alertmanager, alertmanager-ntfy, ntfy, Grafana, all notification integrations, and related secrets/scripts.

Purpose: Agents (parts containers) need only `http://localhost:9090/api/v1/alerts` to query host health. Everything else is overhead — notification routing, dashboards, push brokers — none of it is consumed by anything.

Output: Lean monitoring config with Prometheus + node_exporter only.
</objective>

<execution_context>
@/home/ubuntu/.claude/get-shit-done/workflows/execute-plan.md
@/home/ubuntu/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@modules/monitoring.nix
@modules/ntfy.nix
@modules/grafana.nix
@modules/default.nix
@modules/networking.nix
@modules/homepage.nix
@scripts/deploy.sh
@scripts/notify.sh
@modules/secrets.nix
</context>

<tasks>

<task type="auto">
  <name>Task 1: Gut monitoring.nix and remove ntfy/grafana modules</name>
  <files>
    modules/monitoring.nix
    modules/ntfy.nix
    modules/grafana.nix
    modules/default.nix
    modules/secrets.nix
  </files>
  <action>
**modules/monitoring.nix** — Keep ONLY:
- `services.prometheus.exporters.node` block (lines 8-16) — unchanged
- `services.prometheus` block with: `enable`, `port`, `retentionTime`, `globalConfig`, `scrapeConfigs` (both `node` and `prometheus` jobs), and `ruleFiles` with all 6 alert rules
- REMOVE: `services.prometheus.alertmanagers` block (lines 46-54) — no Alertmanager to point to
- REMOVE: `services.prometheus.alertmanager` block (lines 141-170) — the entire Alertmanager service
- REMOVE: `services.prometheus.alertmanager-ntfy` block (lines 172-198) — ntfy bridge
- REMOVE: `systemd.services."ntfy-failure@"` template (lines 200-215) — ntfy crash notifier
- REMOVE: All three `systemd.services.*.unitConfig.OnFailure` lines (217-219) — docker, prometheus, grafana crash hooks
- Update `@decision` annotations at top: remove MON-01 (ntfy routing), MON-03 (alertmanager-ntfy), MON-04 (OnFailure template). Keep MON-02 (scrape interval + retention).
- Add new annotation: `@decision MON-05: Alertmanager, ntfy, Grafana removed — agents query Prometheus /api/v1/alerts directly.`

**modules/ntfy.nix** — Replace entire contents with an empty module:
```nix
# modules/ntfy.nix — REMOVED
# ntfy was removed in quick-5 (monitoring minimization).
# Agents query Prometheus alerts API directly; no push notification broker needed.
{ ... }: {}
```

**modules/grafana.nix** — Replace entire contents with an empty module:
```nix
# modules/grafana.nix — REMOVED
# Grafana was removed in quick-5 (monitoring minimization).
# No dashboards needed; agents query Prometheus alerts API directly.
{ ... }: {}
```

Why empty modules instead of deleting: `modules/default.nix` imports them. Keeping empty modules is safer than removing imports and risking missed references. The empty `{ ... }: {}` evaluates to nothing.

**modules/default.nix** — Actually, since we're making empty modules, no change needed here. But for cleanliness, REMOVE the import lines for `./ntfy.nix` and `./grafana.nix` from the imports list, and delete the empty module files. This is cleaner.

Correction: DELETE `modules/ntfy.nix` and `modules/grafana.nix` entirely. In `modules/default.nix`, remove the two import lines:
```
    ./ntfy.nix
    ./grafana.nix
```

**modules/secrets.nix** — No changes needed. The grafana secrets (`grafana-admin-password`, `grafana-secret-key`) are defined in `modules/grafana.nix`, not in `secrets.nix`. Deleting grafana.nix removes them.

Note: The `secrets/acfs.yaml` sops file may still contain grafana secret entries, but they become harmless dead data — sops-nix only decrypts secrets explicitly declared in NixOS config. No sops re-encryption needed.
  </action>
  <verify>
Run `nix flake check` from the repo root. Must pass with no errors. Specifically verify:
- No "undefined variable" errors from removed ntfy/grafana references
- No "file not found" errors from deleted module files
  </verify>
  <done>
monitoring.nix contains only Prometheus + node_exporter + 6 alert rules. ntfy.nix and grafana.nix are deleted. default.nix no longer imports them. No Alertmanager, no ntfy, no Grafana in the NixOS config.
  </done>
</task>

<task type="auto">
  <name>Task 2: Clean up networking, homepage, deploy script, and notify.sh</name>
  <files>
    modules/networking.nix
    modules/homepage.nix
    scripts/deploy.sh
    scripts/notify.sh
  </files>
  <action>
**modules/networking.nix** — Two changes:
1. Remove fail2ban ntfy integration (lines 98-115):
   - Change `jails.sshd.settings` from `action = "%(action_)s\n            ntfy";` to just remove the entire `jails.sshd.settings` block (lines 98-100). This reverts to fail2ban default action (ban only, no notification). The jail itself remains active via the global fail2ban config above.
   - DELETE the `environment.etc."fail2ban/action.d/ntfy.local"` block (lines 103-115).
2. Remove ntfy, grafana, alertmanager from `internalOnlyPorts` (lines 13, 14, 19):
   - Remove `"2586" = "ntfy";`
   - Remove `"3000" = "grafana";`
   - Remove `"9093" = "alertmanager";`
   - Keep: homepage-dashboard (8082), home-assistant (8123), syncthing-gui (8384), prometheus (9090), node-exporter (9100).

**modules/homepage.nix** — Remove monitoring/notification entries:
1. Remove the entire `"Monitoring"` service group (lines 28-53) and replace with a trimmed version containing ONLY Prometheus:
```nix
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
```
2. Remove the entire `"Notifications & Sync"` group (lines 55-74) and replace with just Syncthing under a renamed group:
```nix
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
```

**scripts/deploy.sh** — Remove ntfy notification calls:
1. Remove `NTFY_TOPIC="deploys"` variable (line 23).
2. Remove the success ntfy curl block (lines 178-184): the 4-line `ssh "$TARGET" "curl ...` command. Keep the echo statements and container status reporting around it.
3. Remove the failure ntfy curl block (lines 195-201): the 4-line `ssh "$TARGET" "curl ...` command. Keep the error reporting around it.

**scripts/notify.sh** — DELETE this file entirely. It's a wrapper around ntfy which no longer exists.
  </action>
  <verify>
1. `nix flake check` passes (confirms networking.nix and homepage.nix are valid Nix).
2. `bash -n scripts/deploy.sh` passes (confirms deploy script syntax is valid).
3. `grep -r 'ntfy\|grafana\|alertmanager' modules/ scripts/` should return NO matches except comments explaining removal. Specifically no active service declarations, no curl calls to ntfy, no alertmanager config.
  </verify>
  <done>
All ntfy/grafana/alertmanager references removed from networking, homepage, deploy script. notify.sh deleted. fail2ban uses default action only. Homepage shows only Prometheus under Monitoring. Deploy script reports success/failure to stdout only, no push notifications. Grep confirms no remaining active references.
  </done>
</task>

</tasks>

<verification>
1. `nix flake check` passes — full NixOS config evaluation succeeds
2. `grep -rn 'ntfy\|grafana\|alertmanager' modules/ scripts/` — no active references (only comments if any)
3. `ls modules/ntfy.nix modules/grafana.nix scripts/notify.sh 2>&1` — all three files gone
4. `grep -c 'ruleFiles\|alert =' modules/monitoring.nix` — confirms alert rules still present
5. `bash -n scripts/deploy.sh` — deploy script syntax valid
</verification>

<success_criteria>
- Prometheus + node_exporter + 6 alert rules fully intact and evaluating
- Alertmanager, alertmanager-ntfy, ntfy, Grafana completely removed from NixOS config
- No ntfy/grafana/alertmanager references in any active code (modules/ or scripts/)
- fail2ban still active but without ntfy notification action
- Homepage dashboard shows Prometheus only under Monitoring, Syncthing under Sync
- Deploy script works without notification calls
- `nix flake check` passes
</success_criteria>

<output>
After completion, create `.planning/quick/5-minimize-monitoring-notification-stack-t/5-SUMMARY.md`
</output>
