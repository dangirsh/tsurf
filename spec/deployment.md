# Deployment Specification

This document specifies the deployment safety guards, watchdog mechanism,
locking protocol, and public repo non-deployability.

Source: `examples/scripts/deploy.sh`, `flake.nix`

## Public Repo Non-Deployability

| ID | Claim | Source |
|----|-------|--------|
| DEP-001 | Public flake exports no `deploy.nodes` | `flake.nix`, `tests/eval/config-checks.nix:public-deploy-empty` |
| DEP-002 | `deploy.sh` refuses to deploy from public repo — detects absence of `tsurf.url` flake input | `examples/scripts/deploy.sh` lines 234-250, `@decision DEPLOY-02` |
| DEP-003 | Deploy script lives in `examples/scripts/` (not `extras/scripts/`) — it's a reference implementation | `CLAUDE.md` project structure |

## Deploy Modes

| ID | Claim | Source |
|----|-------|--------|
| DEP-004 | Two modes: `--mode remote` (build on target, default) and `--mode local` (build locally) | `examples/scripts/deploy.sh` lines 6-7 |
| DEP-005 | `--fast` mode: local build, single evaluation, no `--remote-build` | `examples/scripts/deploy.sh` lines 360-363 |
| DEP-006 | Uses deploy-rs for deployment (not `nixos-rebuild switch`) | `examples/scripts/deploy.sh` lines 366-372 |

## Rollback Watchdog

| ID | Claim | Source |
|----|-------|--------|
| DEP-007 | Pre-deploy: 5-minute rollback watchdog scheduled via `systemd-run` transient timer | `examples/scripts/deploy.sh` lines 315-336, `@decision DEPLOY-03` |
| DEP-008 | Watchdog survives sshd restarts and cgroup cleanup during activation | `@decision DEPLOY-05` |
| DEP-009 | Watchdog auto-reverts to previous NixOS generation if SSH not verified post-deploy | `examples/scripts/deploy.sh` lines 325-328 |
| DEP-010 | Watchdog cancelled after successful SSH connectivity verification | `examples/scripts/deploy.sh` lines 421-429 |
| DEP-011 | First deploy mode (`--first-deploy`) disables watchdog | `examples/scripts/deploy.sh` lines 315-316 |

## Remote Locking

| ID | Claim | Source |
|----|-------|--------|
| DEP-012 | Remote directory-based lock at `/var/lock/deploy-${NODE}.lock` prevents concurrent deploys | `examples/scripts/deploy.sh` lines 84-85, 269-280 |
| DEP-013 | Lock metadata includes: holder, PID, timestamp, SHA | `examples/scripts/deploy.sh` lines 264-267 |
| DEP-014 | Lock released on exit via cleanup trap | `examples/scripts/deploy.sh` lines 92-105 |

## Post-Deploy Verification

| ID | Claim | Source |
|----|-------|--------|
| DEP-015 | Service health check: verifies `tailscaled` and `sshd` active after deploy | `examples/scripts/deploy.sh` lines 258, 382-388 |
| DEP-016 | SSH connectivity verified via non-multiplexed fresh connection (tests real path, not cached) | `examples/scripts/deploy.sh` lines 397-404, `@decision DEPLOY-04` |
| DEP-017 | Optional public IP connectivity check via `--public-ip` | `examples/scripts/deploy.sh` lines 407-416 |

## Deploy Status

| ID | Claim | Source |
|----|-------|--------|
| DEP-018 | Deploy status JSON written to remote `/var/lib/deploy-status/status.json` | `examples/scripts/deploy.sh` lines 56-81 |
| DEP-019 | Status includes: status, timestamp, SHA, node, duration, summary | `examples/scripts/deploy.sh` lines 63-71 |
| DEP-020 | Deploy summary computed from git log between previous deploy SHA and HEAD | `examples/scripts/deploy.sh` lines 283-306 |

## Post-Deploy Hooks

| ID | Claim | Source |
|----|-------|--------|
| DEP-021 | No repo-controlled post-deploy hooks — `--post-hook` must be an absolute path outside the repo, executed as subprocess (not sourced) | `examples/scripts/deploy.sh` lines 490-493, `@decision DEPLOY-114-01` |
| DEP-022 | deploy.sh has no repo-controlled `source` calls | `tests/eval/config-checks.nix:deploy-no-repo-source` |

## SSH Multiplexing

| ID | Claim | Source |
|----|-------|--------|
| DEP-023 | SSH multiplexing enabled for all deploy locking/health-check calls via `ControlMaster=auto` | `examples/scripts/deploy.sh` lines 89-90 |
| DEP-024 | SSH control socket stored in `$FLAKE_DIR/tmp/` (not `/tmp/`) | `examples/scripts/deploy.sh` line 89 |
