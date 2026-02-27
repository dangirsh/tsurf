# Phase 39: Conway Automaton Monitoring Dashboard - Research

**Researched:** 2026-02-27

## Q1: SQLite Schema of state.db

The automaton uses better-sqlite3 with WAL mode enabled (`journal_mode = WAL`). Schema version is currently 10. The database path is `/var/lib/automaton/.automaton/state.db`.

### Tables Available for Dashboard Display

**Core tables (most useful for dashboard):**

| Table | Key Columns | Dashboard Use |
|-------|-------------|---------------|
| `kv` | `key TEXT PK, value TEXT` | Agent state (`agent_state`), financial state (`financial_state` JSON), current tier (`current_tier`), sleep_until |
| `turns` | `id, timestamp, state, input, input_source, thinking, tool_calls JSON, token_usage JSON, cost_cents` | Turn count, recent activity, cost tracking |
| `tool_calls` | `id, turn_id, name, arguments JSON, result, duration_ms, error` | Recent tool calls display |
| `transactions` | `id, type, amount_cents, balance_after_cents, description, created_at` | Financial transaction log |
| `goals` | `id, title, description, status, strategy, expected_revenue_cents, actual_revenue_cents, created_at, deadline, completed_at` | Current goal + task progress |
| `task_graph` | `id, parent_id, goal_id, title, description, status, assigned_to, priority, dependencies JSON, estimated_cost_cents, actual_cost_cents` | Task progress under goals |
| `inference_costs` | `id, session_id, turn_id, model, provider, input_tokens, output_tokens, cost_cents, latency_ms, tier, task_type, cache_hit, created_at` | Spend rate calculation |
| `spend_tracking` | `id, tool_name, amount_cents, recipient, domain, category, window_hour, window_day` | Spend rate by category |
| `identity` | `key TEXT PK, value TEXT` | Agent name, address, creator, sandbox, automatonId |

**Additional tables (secondary for dashboard):**

| Table | Use |
|-------|-----|
| `heartbeat_schedule` | Show heartbeat task statuses, last run, fail counts |
| `heartbeat_history` | Recent heartbeat execution log |
| `working_memory` | Current goals/plans/observations in working memory |
| `session_summaries` | Session cost summaries |
| `metric_snapshots` | Historical metric snapshots (metrics_json, alerts_json) |
| `skills` | Installed skills list |
| `children` | Child automaton status |
| `modifications` | Self-modification audit log |
| `wake_events` | Pending wake events |

### Agent State Values

The `agent_state` KV entry contains one of: `setup`, `waking`, `running`, `sleeping`, `low_compute`, `critical`, `dead`.

### Financial State in KV

The `financial_state` KV entry is a JSON blob: `{"creditsCents": N, "usdcBalance": N, "lastChecked": "ISO8601"}`.
The `current_tier` KV entry is one of: `dead`, `critical`, `low_compute`, `normal`, `high`.

### Survival Tier Thresholds

From `types.ts`:
- `high`: > 500 cents ($5.00)
- `normal`: > 50 cents ($0.50)
- `low_compute`: > 10 cents ($0.10)
- `critical`: >= 0 cents
- `dead`: < 0 (negative balance)

## Q2: Does the Automaton Expose HTTP Endpoints?

**No.** The automaton is a headless CLI process (`automaton --run`) with no HTTP server. The `index.ts` entry point runs a main loop (heartbeat daemon + agent loop) with no `http.createServer`, Express, or similar.

The `MetricsCollector` class is in-process only (JavaScript Maps) with no HTTP exposure. The `metric_snapshots` table stores periodic snapshots to SQLite, but there is no `/metrics` endpoint.

The `--status` CLI command prints agent status to stdout and exits. It is not an HTTP endpoint.

**Implication:** The monitoring dashboard must read directly from the SQLite database and journald. There is no API to call.

## Q3: Web Server Approach

### Options Considered

**Option A: Python with `http.server` (ThreadingTCPServer pattern)**
- Matches the existing `secret-proxy.nix` pattern (per MEMORY.md: `pkgs.writers.writePython3Bin`)
- Python's `sqlite3` stdlib can open the DB in read-only mode (`?mode=ro`)
- `subprocess.check_output(["journalctl", ...])` for journald access
- Enforces flake8 E501 (79 char line limit) and E305 (2 blank lines after class)
- HTML served inline as Python string or from a small template
- **Pros:** Proven pattern in this codebase, no extra dependencies, Python sqlite3 is robust
- **Cons:** Flake8 line-length enforcement makes large HTML templates awkward; need to split HTML into multiple lines

**Option B: Static HTML + Python JSON API**
- Python backend serves `/api/status` JSON endpoint
- Static `index.html` with vanilla JS fetches and renders
- HTML file stored as `pkgs.writeText` and served by the Python backend
- **Pros:** Clean separation, easier to iterate on UI, avoids flake8 HTML issues
- **Cons:** Two files to manage (HTML + Python), slightly more complexity

**Option C: Go single-binary**
- `pkgs.buildGoModule` with embedded HTML template
- `mattn/go-sqlite3` or `modernc.org/sqlite` for DB access
- **Pros:** Single binary, fast, no runtime dependencies
- **Cons:** Requires Go module packaging, new build pattern for this project, overkill for a simple dashboard

**Option D: nginx + static HTML + cron-generated JSON**
- Cron/systemd timer runs a script that queries SQLite and writes JSON to a static path
- nginx serves both the HTML and JSON
- **Pros:** Very simple, no running web server process
- **Cons:** Not live data (delayed by cron interval), adds nginx dependency, more moving parts

### Recommendation: Option B (Python JSON API + Static HTML)

Rationale:
1. Python `http.server` pattern is proven in this codebase (secret-proxy.nix)
2. Separating HTML from Python avoids flake8 line-length pain
3. Single systemd service, single port
4. `sqlite3` stdlib is available without extra packages
5. `journalctl` is available on the system PATH
6. HTML file can be a `pkgs.writeText` derivation, served by the Python `do_GET` handler

The Python server handles:
- `GET /` -> serve static HTML file
- `GET /api/status` -> JSON blob with all dashboard data
- The HTML uses `setInterval(fetch('/api/status'), 5000)` for auto-refresh

## Q4: SQLite Concurrent Read Access

The automaton opens the database with **WAL mode** (Write-Ahead Logging):
```typescript
db.pragma("journal_mode = WAL");
db.pragma("wal_autocheckpoint = 1000");
```

WAL mode allows **concurrent readers with one writer**. This is ideal for the dashboard:

### Safe Read-Only Access Pattern

```python
import sqlite3
conn = sqlite3.connect(
    "file:/var/lib/automaton/.automaton/state.db?mode=ro",
    uri=True,
    timeout=5
)
```

Key considerations:
- The `?mode=ro` URI parameter opens the DB in read-only mode at the SQLite level
- WAL mode allows the dashboard to read without blocking the automaton's writes
- The dashboard process must have filesystem read access to both `state.db` and `state.db-wal` and `state.db-shm`
- **User/group access:** The automaton runs as `automaton:automaton`. The dashboard service needs to be in the `automaton` group, OR the state directory needs group-readable permissions
- Recommended: Run dashboard as its own user (e.g., `automaton-dashboard`) in group `automaton`, with `state.db` being group-readable (0640)

### Permission Approach

**Option 1:** Add dashboard user to `automaton` group + set `state.db` permissions to 0640
- Requires: modify automaton activation script to `chmod 0640` the DB files
- Risk: The automaton may reset permissions on restart

**Option 2:** Run dashboard as `automaton` user
- Simplest, no permission changes needed
- Risk: Dashboard process has write access (but we open `?mode=ro`)

**Option 3:** Use a bind-mount or symlink
- Overkill for this use case

**Recommendation: Option 2** (run as `automaton` user). The `?mode=ro` SQLite flag prevents writes at the SQLite level. This matches the principle of simplicity. If the dashboard had a vulnerability, it could write to the DB, but it's Tailscale-only and the attack surface is minimal.

## Q5: Reading Journald Logs

### Approach

```python
import subprocess
import json

result = subprocess.run(
    ["journalctl", "-u", "conway-automaton",
     "--output=json", "--no-pager",
     "-n", "50", "--reverse"],
    capture_output=True, text=True, timeout=5
)
for line in result.stdout.strip().split("\n"):
    entry = json.loads(line)
    # entry["MESSAGE"], entry["__REALTIME_TIMESTAMP"], etc.
```

Key fields from journald JSON output:
- `MESSAGE` - the log message
- `__REALTIME_TIMESTAMP` - microseconds since epoch
- `_PID` - process ID
- `PRIORITY` - syslog priority (3=error, 4=warning, 6=info, 7=debug)

### Alternative: systemd-journal gateway

NixOS has `services.journald.gateway.enable` which starts an HTTP gateway on port 19531. However, this adds another service and port, and is overkill when `subprocess.run(["journalctl", ...])` works fine.

### Permission for journalctl

The dashboard user needs to be in the `systemd-journal` group to read journal logs. If running as `automaton` user, add `automaton` to `systemd-journal` supplementary group:

```nix
users.users.automaton.extraGroups = [ "systemd-journal" ];
```

Or use `journalctl --system` which requires root. Better: add the user to the `systemd-journal` group.

## Q6: Port Selection

### Current internalOnlyPorts Map

```
3000  - claw-swap app
6167  - matrix-conduit
8082  - homepage-dashboard
8123  - home-assistant
8384  - syncthing-gui
9090  - prometheus
9091  - anthropic-secret-proxy
9100  - node-exporter
18789 - openclaw-mark
18790 - openclaw-lou
18791 - openclaw-alexia
18792 - openclaw-ari
19898 - spacebot
29317 - mautrix-telegram
29318 - mautrix-whatsapp
29328 - mautrix-signal
```

### Recommended Port: 9093

Rationale:
- In the 909x range near other monitoring/infrastructure services (9090 Prometheus, 9091 secret-proxy, 9100 node-exporter)
- Not used by any common service convention (9093 is typically Alertmanager, which is not deployed here per MON-05)
- Alternatively: 9092 (Kafka convention, not used), 9094, 9095
- 9093 is the best fit: "automaton monitoring" sits alongside Prometheus in the monitoring range

## Q7: Module Structure

### Recommendation: New module `modules/automaton-dashboard.nix`

Rationale:
- `automaton.nix` is already 257 lines (the automaton service, user, activation scripts, sops templates)
- The dashboard is a separate service with its own systemd unit, port, and concerns
- Follows the "one module per concern" convention
- The dashboard depends on but is separate from the automaton service

### Module responsibilities:
1. Python dashboard script (pkgs.writers.writePython3Bin or pkgs.writeText + wrapper)
2. Static HTML file (pkgs.writeText)
3. Systemd service unit
4. Port registration in internalOnlyPorts (networking.nix)
5. Homepage dashboard entry (homepage.nix)

### Changes to other modules:
- `modules/default.nix` — add `./automaton-dashboard.nix` to imports
- `modules/networking.nix` — add `"9093" = "automaton-dashboard"` to internalOnlyPorts
- `modules/homepage.nix` — add "Conway Automaton" entry under "Infrastructure" or new "Agents" section

## Q8: Data Available for Required Metrics

### Required vs. Available

| Dashboard Requirement | Data Source | SQL Query Pattern |
|----------------------|-------------|-------------------|
| Agent state (running/sleeping/thinking) | `kv` table, key `agent_state` | `SELECT value FROM kv WHERE key = 'agent_state'` |
| Conway credits balance | `kv` table, key `financial_state` (JSON) | `SELECT value FROM kv WHERE key = 'financial_state'` -> parse JSON -> `.creditsCents` |
| Total turns | `turns` table | `SELECT COUNT(*) FROM turns` |
| Current goal + task progress | `goals` + `task_graph` tables | `SELECT * FROM goals WHERE status = 'active'` + `SELECT * FROM task_graph WHERE goal_id = ? ORDER BY priority DESC` |
| Recent tool calls | `tool_calls` table | `SELECT tc.*, t.timestamp FROM tool_calls tc JOIN turns t ON tc.turn_id = t.id ORDER BY tc.created_at DESC LIMIT 20` |
| Spend rate ($/hr) | `inference_costs` table | `SELECT SUM(cost_cents) FROM inference_costs WHERE created_at > datetime('now', '-1 hour')` |
| Current survival tier | `kv` table, key `current_tier` | `SELECT value FROM kv WHERE key = 'current_tier'` |
| Agent name/address | `identity` table | `SELECT value FROM identity WHERE key = 'name'` |
| Recent journal logs | `journalctl -u conway-automaton` | Subprocess call |
| Uptime | systemd service start time | `journalctl -u conway-automaton --output=json -n 1 --reverse` or systemd DBUS |

All required metrics are available in the database. No external API calls needed.

## Q9: Conway Credits Balance

**Credits are in the KV store, NOT requiring an API call.**

The automaton's heartbeat task `check_credits` (runs every 3600s per heartbeat.yml) calls `conway.getCreditsBalance()` and stores the result via `checkResources()` in `survival/monitor.ts`:
```typescript
db.setKV("financial_state", JSON.stringify(financial));
db.setKV("current_tier", tier);
```

The dashboard reads the **cached** value from KV:
```sql
SELECT value FROM kv WHERE key = 'financial_state'
-- Returns: {"creditsCents": N, "usdcBalance": N, "lastChecked": "ISO8601"}
```

The `lastChecked` timestamp tells the dashboard how fresh the data is. Display alongside the balance with "as of X minutes ago".

**No Conway API key or network call needed** by the dashboard. The automaton maintains the cached balance.

## Q10: Spend Rate Calculation

### Approach 1: inference_costs table (most accurate)

```sql
-- Hourly spend rate from inference costs
SELECT
  SUM(cost_cents) as total_cents,
  COUNT(*) as call_count
FROM inference_costs
WHERE created_at > datetime('now', '-1 hour')
```

The `inference_costs` table tracks every LLM call with `cost_cents`, `input_tokens`, `output_tokens`, `model`, `provider`, `task_type`.

### Approach 2: spend_tracking table (by category)

```sql
-- Spend by category for current hour
SELECT category, SUM(amount_cents) as total
FROM spend_tracking
WHERE window_hour = strftime('%Y-%m-%dT%H', 'now')
GROUP BY category
```

Categories: `transfer`, `x402`, `inference`, `other`.

### Approach 3: turns table (simpler but less granular)

```sql
-- Cost per hour from turns
SELECT
  SUM(cost_cents) as hourly_cost
FROM turns
WHERE timestamp > datetime('now', '-1 hour')
```

### Recommendation

Use **Approach 1** (inference_costs) as the primary spend rate. Display as "$/hr" calculated from the last hour's data. Additionally show cumulative daily spend from `spend_tracking` by category.

Display format:
```
Spend Rate: $0.42/hr (last hour)
Today: $3.28 total ($2.95 inference, $0.33 transfers)
```

## Architecture Summary

```
[Browser] --> [Python HTTP Server :9093]
                   |
                   ├── GET /          --> static HTML (auto-refresh JS)
                   ├── GET /api/status --> JSON blob from:
                   |       ├── SQLite read-only: state.db
                   |       │     ├── kv (agent_state, financial_state, current_tier)
                   |       │     ├── turns (count, recent)
                   |       │     ├── tool_calls (recent)
                   |       │     ├── goals + task_graph (active)
                   |       │     ├── inference_costs (spend rate)
                   |       │     └── identity (name, address)
                   |       └── journalctl subprocess (recent logs)
                   └── [systemd unit: automaton-dashboard.service]
                         User=automaton
                         After=conway-automaton.service
```

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| SQLite locking contention | Low | WAL mode + read-only connection; dashboard reads don't block writes |
| state.db doesn't exist yet (automaton not started) | Medium | Dashboard shows "Automaton not running" with graceful error handling |
| journalctl access denied | Medium | Add `automaton` user to `systemd-journal` group |
| Flake8 E501 in Python | Certain | Separate HTML into pkgs.writeText; keep Python under 79 chars |
| Stale financial data | Low | Display `lastChecked` timestamp; automaton refreshes hourly |
| Database schema changes | Low | Use `SELECT ... FROM ... WHERE` patterns that degrade gracefully if tables don't exist |

## Files to Create/Modify

### New Files
1. `modules/automaton-dashboard.nix` — new NixOS module (Python server + HTML + systemd service)

### Modified Files
1. `modules/default.nix` — add `./automaton-dashboard.nix` to imports
2. `modules/networking.nix` — add `"9093" = "automaton-dashboard"` to internalOnlyPorts
3. `modules/homepage.nix` — add Conway Automaton dashboard entry

### No Secrets Needed
The dashboard reads from a local SQLite file and journalctl. No API keys, no sops secrets required.

## Implementation Estimate

- **Effort:** Low-Medium
- **Files changed:** 4 (1 new, 3 modified)
- **Risk tier:** Low (internal tool, Tailscale-only, read-only access)
- **Dependencies:** Phase 32 must be complete (automaton.nix deployed, state.db exists)

## Key Design Decisions for Planning

1. **DASH-01:** Python HTTP server (stdlib) matches existing secret-proxy pattern; no new runtime dependencies
2. **DASH-02:** Read-only SQLite access via `?mode=ro` URI; runs as `automaton` user for simplicity
3. **DASH-03:** Port 9093 (monitoring range, Alertmanager convention, not in use)
4. **DASH-04:** Separate module `automaton-dashboard.nix` per one-module-per-concern convention
5. **DASH-05:** Static HTML with JS auto-refresh (5s interval via fetch), no SPA framework
6. **DASH-06:** Journal access via `journalctl` subprocess, not systemd-journal HTTP gateway
7. **DASH-07:** No external API calls; all data from local SQLite + journald
