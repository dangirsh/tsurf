# Users and Privileges Specification

This document specifies the user model, sudo configuration, and
template safety mechanisms.

Source: `modules/users.nix`, `modules/break-glass-ssh.nix`

## User Identities

| ID | Claim | Source |
|----|-------|--------|
| USR-001 | `dev` user: UID configurable via `tsurf.template.devUid` (default 1000), group `dev`, member of `wheel` | `modules/users.nix` lines 62-72 |
| USR-002 | Agent user: default `agent`, UID 1001, GID 1001, home `/home/agent`, member of `users` only | `modules/users.nix` lines 79-89 |
| USR-003 | Both users have sub-UID/GID ranges for rootless containers (dev: 100000+, agent: 200000+) | `modules/users.nix` lines 67-68, 85-86 |
| USR-004 | Agent user has `linger = true` for user-level systemd services | `modules/users.nix` line 88 |
| USR-005 | Agent user shell is `bashInteractive` | `modules/users.nix` line 87 |
| USR-006 | `users.mutableUsers = false` | `modules/users.nix` line 59 |

## Sudo Configuration

| ID | Claim | Source |
|----|-------|--------|
| USR-007 | `security.sudo.execWheelOnly = false` — allows non-wheel sudo rules for agent immutable launchers | `modules/users.nix` line 105, `@decision SYS-01` |
| USR-008 | `security.sudo.wheelNeedsPassword` toggled by `allowUnsafePlaceholders` | `modules/users.nix` line 104 |
| USR-009 | Agent sudo rules: only immutable per-agent launchers with `NOPASSWD`, no `SETENV` | `modules/agent-sandbox.nix` lines 160-175 |

## Break-Glass SSH

| ID | Claim | Source |
|----|-------|--------|
| USR-010 | Break-glass emergency SSH key hardcoded in `break-glass-ssh.nix`, independent of sops-nix | `modules/break-glass-ssh.nix`, `@decision SEC-70-01` |
| USR-011 | Key comment must contain `break-glass-emergency` — checked by build-time assertion | `modules/networking.nix` lines 105-107 |
| USR-012 | Placeholder key material shipped in public repo — must be replaced before real deployment | `modules/break-glass-ssh.nix` lines 15-17 |
| USR-013 | Break-glass key survives: sops activation failures, private overlay users.nix replacement, key-management misconfiguration | `@decision SEC-70-01` |

## Root User

| ID | Claim | Source |
|----|-------|--------|
| USR-014 | Root has bootstrap SSH key (placeholder in public repo) | `modules/users.nix` lines 95-99 |
| USR-015 | Root has break-glass SSH key (separate from bootstrap) | `modules/break-glass-ssh.nix` |
| USR-016 | `PermitRootLogin = "prohibit-password"` — key-only root access | `modules/networking.nix` line 177 |

## Template Safety Assertions

| ID | Claim | Source |
|----|-------|--------|
| USR-017 | When `allowUnsafePlaceholders = false`: assertion rejects bootstrap-key in root authorized_keys | `modules/users.nix` lines 122-130 |
| USR-018 | When `allowUnsafePlaceholders = false`: assertion rejects break-glass placeholder in root authorized_keys | `modules/users.nix` lines 131-139 |
| USR-019 | Unconditional assertions: agent not in wheel, agent not in docker, agent != dev | `modules/users.nix` lines 108-119 |
