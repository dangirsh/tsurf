---
phase: 14-monitoring-notifications-prometheus-grafana-ntfy
plan: 14-02
subsystem: observability
tags:
  - nixos
  - ntfy
  - deploy
  - operations
  - scripts
requires:
  - modules/ntfy.nix
  - scripts/deploy.sh
  - nix flake evaluation
provides:
  - deploy outcome push notifications
  - reusable notification helper script
  - validated monitoring and notification configuration
affects:
  - scripts/deploy.sh
  - scripts/notify.sh
  - .planning/STATE.md
tech-stack:
  - Bash
  - curl
  - OpenSSH
  - ntfy-sh
  - Nix flakes
key-files:
  - scripts/deploy.sh
  - scripts/notify.sh
  - modules/monitoring.nix
  - modules/ntfy.nix
  - modules/grafana.nix
  - secrets/acfs.yaml
key-decisions:
  - Deploy notifications are sent by SSHing to the target and curling ntfy on server localhost
  - Deploy notifications are best-effort and must not block or fail deployments
  - Generic notify.sh runs server-side for ad-hoc producers (agents, cron, future restic hooks)
duration: "~8m"
completed: "2026-02-18T17:49:17+01:00"
---

Deploy pipeline now pushes ntfy success/failure events plus a reusable server-side `notify.sh`, with full monitoring stack re-validated by `nix flake check`.

## Performance
- Duration: ~8 minutes
- Start: 2026-02-18T17:41:00+01:00
- End: 2026-02-18T17:49:17+01:00
- Task count: 3 plan tasks completed
- File count: 2 implementation files changed, 2 planning files added/updated

## Accomplishments
- Updated `scripts/deploy.sh` to publish deploy success and failure notifications to topic `deploys` through SSH to target-host localhost ntfy.
- Added low-priority success payload including parts revision + duration and high-priority failure payload with duration + error context.
- Implemented best-effort delivery in deploy flow (`2>/dev/null || true`) so notification outages cannot break deploy execution.
- Created executable `scripts/notify.sh` helper with required positional args (`topic`, `title`) and optional message/`--priority`/`--tags` flags for generic producers.
- Verified scripts (`bash -n`, executable bit, localhost endpoint checks) and validated complete flake with `nix flake check`.
- Audited monitoring posture: no monitoring ports in firewall allowlist, Grafana file-provider secrets configured, ntfy write-only access, 6 alert rules, and both Grafana secrets present in encrypted secrets file.

## Task Commits
- `79befd0` `feat(14-01): add ntfy notifications to deploy outcomes`
- `69d5848` `feat(14-01): add generic ntfy notify helper script`

## Files Created/Modified
- Modified: `scripts/deploy.sh`
- Created: `scripts/notify.sh`
- Created: `.planning/phases/14-monitoring-notifications-prometheus-grafana-ntfy/14-02-SUMMARY.md`
- Modified: `.planning/STATE.md`

## Decisions Made
- [14-02] Deploy notifications are emitted from `deploy.sh` via SSH to the deploy target because ntfy is bound to server-local/Tailscale-only access.
- [14-02] Success notifications use `Priority: low`; failure notifications use `Priority: high` and include elapsed duration context.
- [14-02] `scripts/notify.sh` is intentionally generic and server-local so agent wrappers, timers, and future restic hooks can reuse a single notification interface.

## Deviations from Plan
- Alert rule verification used `alert =` expression matching (Nix attr syntax) rather than `alert:` (YAML syntax) while confirming the expected total of 6 rules.

## Issues Encountered
- `nix flake check` produced existing non-blocking Home Manager option rename warnings and one `runCommandNoCC` deprecation warning; evaluation still passed.

## Next Phase Readiness
- Phase 14 monitoring + notifications implementation is complete and validated.
- Ready to proceed to Phase 15 (CrowdSec Intrusion Prevention) with deploy-time and generic notification plumbing in place.
