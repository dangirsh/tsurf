# Deployment Specification

This document specifies the deployment safety guards, locking protocol,
and public repo non-deployability.

Source: `scripts/deploy.sh`, `flake.nix`

## Public Repo Non-Deployability

| ID | Claim | Source |
|----|-------|--------|
| DEP-001 | Public flake exports no `deploy.nodes` | `flake.nix`, `tests/eval/config-checks.nix:public-deploy-empty` |
| DEP-002 | `deploy.sh` refuses to deploy from public repo; detects absence of `tsurf.url` flake input | `scripts/deploy.sh` safety guard, `@decision DEPLOY-02` |
| DEP-003 | Deploy script lives in `scripts/` as a core feature | `CLAUDE.md` project structure |

## Deploy Modes

| ID | Claim | Source |
|----|-------|--------|
| DEP-004 | Two modes: `--mode remote` (build on target, default) and `--mode local` (build locally) | `scripts/deploy.sh` |
| DEP-005 | `--fast` mode: local build, single evaluation, no `--remote-build` | `scripts/deploy.sh` |
| DEP-006 | Uses deploy-rs for deployment (not `nixos-rebuild switch`) | `scripts/deploy.sh` |

## Remote Locking

| ID | Claim | Source |
|----|-------|--------|
| DEP-012 | Remote directory-based lock at `/var/lock/deploy-${NODE}.lock` prevents concurrent deploys | `scripts/deploy.sh` |
| DEP-013 | Lock metadata includes: holder, PID, timestamp, SHA | `scripts/deploy.sh` |
| DEP-014 | Lock released on exit via cleanup trap | `scripts/deploy.sh` |

## Post-Deploy Verification

| ID | Claim | Source |
|----|-------|--------|
| DEP-015 | Service health check: verifies `sshd` and `nftables` after deploy | `scripts/deploy.sh` |
| DEP-016 | SSH connectivity verified via non-multiplexed fresh connection (tests real path, not cached) | `scripts/deploy.sh`, `@decision DEPLOY-04` |
| DEP-017 | No separate public-IP probe path; deploy verification stays minimal and SSH-based | `scripts/deploy.sh` |

## Post-Deploy Hooks

| ID | Claim | Source |
|----|-------|--------|
| DEP-021 | No repo-controlled post-deploy hooks | `scripts/deploy.sh`, `@decision DEPLOY-114-01` |
| DEP-022 | deploy.sh has no repo-controlled `source` calls | `tests/eval/config-checks.nix:deploy-no-repo-source` |

## SSH Multiplexing

| ID | Claim | Source |
|----|-------|--------|
| DEP-023 | SSH multiplexing enabled for all deploy locking/health-check calls via `ControlMaster=auto` | `scripts/deploy.sh` |
| DEP-024 | SSH control socket stored in `$FLAKE_DIR/tmp/` (not `/tmp/`) | `scripts/deploy.sh` |
