# Backup Specification

This document specifies the restic backup configuration, retention policy,
and status reporting.

Source: `extras/restic.nix`

## Backup Configuration

| ID | Claim | Source |
|----|-------|--------|
| BAK-001 | Restic backup is opt-in via `services.resticStarter.enable` | `extras/restic.nix` line 8, `tests/eval/config-checks.nix:restic-opt-in` |
| BAK-002 | S3-compatible Backblaze B2 backend (not native B2 connector) | `extras/restic.nix` line 19, `@decision RESTIC-01` |
| BAK-003 | Backup target: `/persist` (all persisted state) | `extras/restic.nix` line 24 |
| BAK-004 | Repository auto-initialized (`initialize = true`) | `extras/restic.nix` line 13 |
| BAK-005 | Password from sops secret `restic-password` | `extras/restic.nix` line 21 |
| BAK-006 | Environment file from sops template `restic-b2-env` | `extras/restic.nix` line 22 |

## Schedule and Retention

| ID | Claim | Source |
|----|-------|--------|
| BAK-007 | Daily backups with `Persistent=true` and `RandomizedDelaySec=1h` | `extras/restic.nix` lines 53-56 |
| BAK-008 | Retention: 7 daily, 5 weekly, 12 monthly | `extras/restic.nix` lines 46-50 |

## Exclusions

| ID | Claim | Source |
|----|-------|--------|
| BAK-009 | Cache directories excluded (`--exclude-caches`, `.cache/**`) | `extras/restic.nix` lines 27, 33 |
| BAK-010 | Directories with `.nobackup` marker excluded (`--exclude-if-present .nobackup`) | `extras/restic.nix` line 28 |
| BAK-011 | Git objects and config excluded (reproducible + may contain tokens) | `extras/restic.nix` lines 36-37 |
| BAK-012 | Language/build artifacts excluded: `node_modules`, `__pycache__`, `.direnv`, `result` | `extras/restic.nix` lines 40-43 |

## Status Server

| ID | Claim | Source |
|----|-------|--------|
| BAK-013 | Post-backup cleanup writes status JSON to `/var/lib/restic-status/status.json` | `extras/restic.nix` lines 65-68 |
| BAK-014 | HTTP status server on `127.0.0.1:9200` serving `/var/lib/restic-status` | `extras/restic.nix` line 83 |
| BAK-015 | Status server uses `DynamicUser=true` for least privilege | `extras/restic.nix` line 89, `tests/eval/config-checks.nix:restic-status-dynamic-user` |
| BAK-016 | Status server fully hardened: `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`, `PrivateDevices`, `CapabilityBoundingSet=""`, etc. | `extras/restic.nix` lines 90-111 |
| BAK-017 | Status server registered as dashboard entry on port 9200 | `extras/restic.nix` lines 124-131 |

## Persistence

| ID | Claim | Source |
|----|-------|--------|
| BAK-018 | Restic chunk cache persisted at `/root/.cache/restic` | `extras/restic.nix` lines 72-74 |
