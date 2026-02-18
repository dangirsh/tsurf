---
phase: quick-5
plan: 01
subsystem: infra
tags: [prometheus, monitoring, nixos, cleanup]

# Dependency graph
requires:
  - phase: 14-monitoring-notifications
    provides: Prometheus + Alertmanager + ntfy + Grafana monitoring stack
provides:
  - Lean Prometheus-only monitoring (no Alertmanager, ntfy, Grafana)
  - Agent-queryable alerts API at localhost:9090/api/v1/alerts
affects: [deploy, homepage, networking, crowdsec-phase-15]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Agent-direct Prometheus query pattern (no notification middleware)"
    - "Minimal monitoring: collect + alert-rules only, no routing/dashboards/push"

key-files:
  created: []
  modified:
    - modules/monitoring.nix
    - modules/default.nix
    - modules/networking.nix
    - modules/homepage.nix
    - scripts/deploy.sh

key-decisions:
  - "MON-05: Alertmanager, ntfy, Grafana removed -- agents query Prometheus /api/v1/alerts directly"
  - "Delete modules entirely (ntfy.nix, grafana.nix, notify.sh) rather than leaving empty stubs"
  - "fail2ban reverts to default action (ban only) without ntfy notification"

patterns-established:
  - "Agents consume Prometheus alerts API directly -- no notification middleware"

# Metrics
duration: 4min
completed: 2026-02-18
---

# Quick Task 5: Minimize Monitoring Stack Summary

**Stripped monitoring to Prometheus + node_exporter + 6 alert rules; removed Alertmanager, ntfy, Grafana, and all notification plumbing**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-18T18:04:29Z
- **Completed:** 2026-02-18T18:08:04Z
- **Tasks:** 2
- **Files modified:** 6 modified, 3 deleted

## Accomplishments
- Prometheus + node_exporter + 6 alert rules fully intact and evaluating
- Alertmanager, alertmanager-ntfy bridge, ntfy service, Grafana all completely removed
- fail2ban still active with default ban action (no ntfy notification)
- Homepage dashboard trimmed: Prometheus-only under Monitoring, Syncthing under Sync
- Deploy script reports to stdout only, no push notifications
- Zero active ntfy/grafana/alertmanager references in modules/ or scripts/
- `nix flake check` passes cleanly

## Task Commits

Each task was committed atomically:

1. **Task 1: Gut monitoring.nix and remove ntfy/grafana modules** - `c5ddbca` (feat)
2. **Task 2: Clean up networking, homepage, deploy script, and notify.sh** - `c5fa13b` (feat)

## Files Created/Modified

- `modules/monitoring.nix` - Prometheus + node_exporter + 6 alert rules only (Alertmanager, ntfy bridge, OnFailure hooks removed)
- `modules/default.nix` - Removed ntfy.nix and grafana.nix imports
- `modules/networking.nix` - Removed ntfy/grafana/alertmanager from internalOnlyPorts, removed fail2ban ntfy integration
- `modules/homepage.nix` - Monitoring group: Prometheus only; renamed Notifications & Sync to Sync: Syncthing only
- `scripts/deploy.sh` - Removed NTFY_TOPIC variable and both ntfy curl notification blocks
- `modules/ntfy.nix` - DELETED
- `modules/grafana.nix` - DELETED
- `scripts/notify.sh` - DELETED

## Decisions Made

- **MON-05**: Agents query `http://localhost:9090/api/v1/alerts` directly instead of going through Alertmanager -> ntfy notification chain. This removes all middleware between Prometheus alert evaluation and agent consumption.
- **Clean deletion over empty stubs**: Deleted ntfy.nix, grafana.nix, and notify.sh entirely and removed their imports, rather than leaving empty module stubs. Cleaner and avoids confusion.
- **fail2ban default action**: Reverted to ban-only (no notification) since ntfy is gone. fail2ban itself remains active with progressive banning.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. The removed services (ntfy, Grafana, Alertmanager) will stop running on next deploy. Prometheus continues unchanged.

## Next Phase Readiness
- Monitoring stack is minimal and stable for agent consumption
- CrowdSec (Phase 15) can proceed without dependency on ntfy/Alertmanager
- If push notifications are needed in future, a new notification layer can be added on top of the Prometheus alerts API

---
*Quick Task: 5-minimize-monitoring-notification-stack*
*Completed: 2026-02-18*
