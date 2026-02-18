---
phase: 14-monitoring-notifications-prometheus-grafana-ntfy
verified: 2026-02-18T18:05:00Z
status: passed
score: 14/14 must-haves verified
---

# Phase 14: Monitoring + Notifications Verification Report

**Phase Goal:** Declarative monitoring stack with persistent metrics history, Grafana dashboards (Tailscale-only), and ntfy push notifications for server events (deploy, agent completion, security). Prometheus + node_exporter + Grafana + ntfy.
**Verified:** 2026-02-18T18:05:00Z
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Prometheus scrapes node_exporter metrics every 15s and stores time-series data with 90-day retention | VERIFIED | `modules/monitoring.nix` lines 18-44: `services.prometheus.enable = true`, `retentionTime = "90d"`, `globalConfig.scrape_interval = "15s"`, scrapeConfigs for `node` (port 9100) and `prometheus` (port 9090) |
| 2 | Alertmanager routes alerts to ntfy via the alertmanager-ntfy bridge | VERIFIED | `modules/monitoring.nix` lines 141-198: Alertmanager on port 9093 with `webhook_configs` URL `http://127.0.0.1:8000/hook`, alertmanager-ntfy bridge on `127.0.0.1:8000` sending to `http://localhost:2586` topic `alerts` |
| 3 | ntfy-sh is running on port 2586, accessible via Tailscale only, with write-only default access | VERIFIED | `modules/ntfy.nix` lines 5-23: `listen-http = ":2586"`, `auth-default-access = "write-only"`. Port 2586 not in `allowedTCPPorts` (only `[ 22 80 443 22000 ]` in `networking.nix` line 28). Tailscale-only via `trustedInterfaces = [ "tailscale0" ]` |
| 4 | Grafana displays the Node Exporter Full dashboard, accessible via Tailscale only on port 3000 | VERIFIED | `modules/grafana.nix` lines 16-83: `http_port = 3000`, dashboard provisioned via `builtins.fetchurl` (ID 1860 rev 37) at `/etc/grafana-dashboards`. Port 3000 not in `allowedTCPPorts` |
| 5 | Grafana admin password comes from sops-nix, not hardcoded in Nix store | VERIFIED | `modules/grafana.nix` line 28: `admin_password = "$__file{${config.sops.secrets."grafana-admin-password".path}}"` -- uses Grafana's `$__file` provider to read from sops-managed file at runtime, not evaluated into the Nix store |
| 6 | fail2ban sends ban notifications to ntfy | VERIFIED | `modules/networking.nix` lines 78-95: sshd jail action includes `ntfy`, and `ntfy.local` action defined with curl POST to `http://localhost:2586/security` with `norestored = true` |
| 7 | Critical service crashes trigger ntfy notifications via systemd OnFailure | VERIFIED | `modules/monitoring.nix` lines 200-219: `ntfy-failure@` systemd template service curls `http://localhost:2586/alerts` with urgent priority. OnFailure wired to `docker`, `prometheus`, and `grafana` services |
| 8 | Six alert rules fire for instance down, disk low, memory low, high CPU, and systemd unit failures | VERIFIED | `modules/monitoring.nix` lines 57-137: 6 rules confirmed via grep count: `InstanceDown`, `DiskSpaceCritical`, `DiskSpaceWarning`, `HighMemoryUsage`, `HighCpuUsage`, `SystemdUnitFailed` |
| 9 | Deploy script sends ntfy notification on success with parts revision and duration | VERIFIED | `scripts/deploy.sh` lines 136-141: SSH curl POST with `Priority: low`, includes `$PARTS_REV_SHORT` and duration in body |
| 10 | Deploy script sends ntfy notification on failure with error context | VERIFIED | `scripts/deploy.sh` lines 153-158: SSH curl POST with `Priority: high`, includes duration and "Check containers" message |
| 11 | Deploy notifications use priority low for success, high for failure | VERIFIED | `scripts/deploy.sh` line 138: `Priority: low`, line 155: `Priority: high` |
| 12 | ntfy notifications are best-effort and never block the deploy pipeline | VERIFIED | Both notification calls end with `2>/dev/null \|\| true` (lines 141 and 158) |
| 13 | A generic notify.sh script exists that any process can call to send ntfy notifications | VERIFIED | `scripts/notify.sh`: 55-line executable script, accepts topic, title, optional message, `--priority`, `--tags`; curls `$NTFY_URL/$TOPIC` where NTFY_URL is `http://localhost:2586` |
| 14 | nix flake check passes with complete monitoring stack | VERIFIED | Both summaries report `nix flake check` passing. Commits `9b71b84`, `79befd0`, `69d5848` all exist in git history. Module imports wired in `modules/default.nix` |

**Score:** 14/14 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `modules/monitoring.nix` | Prometheus, node_exporter, Alertmanager, alertmanager-ntfy, alert rules, systemd OnFailure template | VERIFIED | 220 lines, all 6 components present, `services.prometheus` confirmed |
| `modules/ntfy.nix` | ntfy-sh notification server | VERIFIED | 27 lines, `services.ntfy-sh` with write-only access, port 2586, cache persistence |
| `modules/grafana.nix` | Grafana server with sops secrets, provisioned datasources and dashboard | VERIFIED | 83 lines, `services.grafana` with `$__file` secret provider, Prometheus + Alertmanager datasources, Node Exporter Full dashboard |
| `modules/default.nix` | Imports all 3 new modules | VERIFIED | Lines 9-11: `./monitoring.nix`, `./ntfy.nix`, `./grafana.nix` all imported |
| `modules/networking.nix` | fail2ban ntfy action with norestored=true | VERIFIED | Lines 78-95: sshd jail with ntfy action, `ntfy.local` action definition with `norestored = true` |
| `secrets/acfs.yaml` | grafana-admin-password and grafana-secret-key encrypted | VERIFIED | `sops -d` shows 2 grafana entries (confirmed via grep count) |
| `scripts/deploy.sh` | ntfy notifications on success (low) and failure (high), best-effort | VERIFIED | Lines 136-141 (success) and 153-158 (failure), both with `|| true` |
| `scripts/notify.sh` | Generic server-side notification helper, executable | VERIFIED | 55 lines, executable bit set, bash syntax valid, accepts topic/title/message/priority/tags |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `modules/monitoring.nix` | `modules/ntfy.nix` | alertmanager-ntfy bridge sends to localhost:2586 | WIRED | Line 177: `baseurl = "http://localhost:2586"`, line 210: OnFailure curls `http://localhost:2586/alerts` |
| `modules/grafana.nix` | `modules/monitoring.nix` | Grafana Prometheus datasource at localhost:9090 | WIRED | Line 47: `url = "http://localhost:${toString config.services.prometheus.port}"` (resolves to 9090) |
| `modules/grafana.nix` | `modules/secrets.nix` | Grafana reads admin password from sops secret file | WIRED | Line 28: `admin_password = "$__file{${config.sops.secrets."grafana-admin-password".path}}"`. Secrets declared in grafana.nix lines 6-13 (co-located, not in secrets.nix -- valid pattern) |
| `modules/networking.nix` | `modules/ntfy.nix` | fail2ban ntfy action curls localhost:2586 | WIRED | Line 94: curl POST to `http://localhost:2586/security` |
| `scripts/deploy.sh` | `modules/ntfy.nix` | SSH curl POST to server's ntfy for deploy events | WIRED | Lines 141, 158: `http://localhost:2586/$NTFY_TOPIC` where `NTFY_TOPIC="deploys"` (line 23) |
| `scripts/notify.sh` | `modules/ntfy.nix` | curl POST to localhost:2586 for arbitrary topics | WIRED | Line 12: `NTFY_URL="http://localhost:2586"`, line 55: `curl "${CURL_ARGS[@]}" "$NTFY_URL/$TOPIC"` |

### Requirements Coverage

No phase 14 requirements in REQUIREMENTS.md. Phase goal states "None (new capability from Phase 13 research)".

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | - | - | - | No TODO/FIXME/PLACEHOLDER/HACK patterns found in any phase 14 files |

No anti-patterns detected in any of the 7 implementation files (monitoring.nix, ntfy.nix, grafana.nix, default.nix, networking.nix, deploy.sh, notify.sh).

### Human Verification Required

### 1. Services Start Successfully on Deploy

**Test:** Deploy to acfs server with `scripts/deploy.sh` and verify all monitoring services start.
**Expected:** `systemctl status prometheus`, `systemctl status prometheus-node-exporter`, `systemctl status prometheus-alertmanager`, `systemctl status alertmanager-ntfy`, `systemctl status ntfy-sh`, `systemctl status grafana` all show active (running).
**Why human:** Cannot verify runtime service startup from code analysis alone.

### 2. Grafana Dashboard Loads

**Test:** Open `http://<tailscale-ip>:3000` in browser, log in with admin credentials.
**Expected:** Node Exporter Full dashboard is visible and displays live system metrics (CPU, memory, disk, network).
**Why human:** Visual dashboard rendering and data population requires a running system.

### 3. ntfy Notifications Arrive

**Test:** Run `scripts/notify.sh agents "Test notification" "Verification test" --priority low --tags white_check_mark` on the server.
**Expected:** Notification appears on subscribed ntfy client (Android app or web UI at Tailscale IP:2586).
**Why human:** End-to-end notification delivery requires a running ntfy instance and subscribed client.

### 4. Alert Rules Fire Correctly

**Test:** Verify alerts are loaded: `curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules | length'` should return 6.
**Expected:** All 6 rules are loaded and evaluating (not necessarily firing -- that depends on system state).
**Why human:** Alert evaluation requires running Prometheus with live scrape data.

### 5. Deploy Notifications Work End-to-End

**Test:** Run a deploy with `scripts/deploy.sh --skip-update` and subscribe to the `deploys` ntfy topic.
**Expected:** Low-priority success notification with parts revision and duration arrives on the ntfy topic.
**Why human:** Requires actual deploy execution and ntfy subscription.

### 6. Grafana Secrets Not in Nix Store

**Test:** After deploy, run `nix-store --query --tree /run/current-system | grep grafana` and inspect the store paths. Also check `cat /run/secrets/grafana-admin-password` exists as a sops-managed file.
**Expected:** Admin password is NOT visible in any Nix store path; it exists only in the sops-managed runtime secret file.
**Why human:** Requires inspecting the deployed system's Nix store paths.

### Gaps Summary

No gaps found. All 14 observable truths verified. All 8 artifacts exist, are substantive (no stubs), and are properly wired. All 6 key links confirmed. No anti-patterns detected. Commits `9b71b84`, `79befd0`, `69d5848` verified in git history.

The phase goal -- "Prometheus + node_exporter + Grafana + ntfy monitoring baseline and push notifications" -- is achieved at the configuration level. Human verification is recommended for runtime behavior (services starting, dashboards rendering, notifications delivering) but the NixOS configuration is complete and validated by `nix flake check`.

---

_Verified: 2026-02-18T18:05:00Z_
_Verifier: Claude (gsd-verifier)_
