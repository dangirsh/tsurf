# Users and Privileges Specification

This document specifies the user model, launcher sudo configuration, and
template safety mechanisms.

Source: `modules/users.nix`, `modules/agent-launcher.nix`

## User Identities

| ID | Claim | Source |
|----|-------|--------|
| USR-001 | Two-user model: root (operator) + agent (sandboxed tools) | `modules/users.nix`, `@decision SEC-152-01` |
| USR-002 | Agent user: default `agent`, UID 1001, GID 1001, home `/home/agent`, member of `users` only | `modules/users.nix` |
| USR-003 | Agent user has sub-UID/GID ranges for rootless containers (200000+) | `modules/users.nix` lines 59-60 |
| USR-005 | Agent user shell is `bashInteractive` | `modules/users.nix` line 61 |
| USR-006 | `users.mutableUsers = false` | `modules/users.nix` line 50 |

## Sudo Configuration

| ID | Claim | Source |
|----|-------|--------|
| USR-007 | `security.sudo.execWheelOnly = false` — allows the non-wheel agent user to invoke explicit sudo rules | `modules/users.nix` |
| USR-008 | Agent sudo rules grant `NOPASSWD` access only to immutable per-agent launchers | `modules/agent-launcher.nix` |
| USR-009 | Launcher sudo rules do not grant `SETENV` or general root access | `tests/eval/config-checks.nix:brokered-launch-sudoers` |

## Root SSH Access

| ID | Claim | Source |
|----|-------|--------|
| USR-010 | Real deployments must set at least one root SSH authorized key | `modules/users.nix` |
| USR-011 | `tsurf-init` can materialize `modules/root-ssh.nix` for a private overlay | `scripts/tsurf-init.sh` |
| USR-012 | `PermitRootLogin = "prohibit-password"` keeps root SSH key-only | `modules/networking.nix` |

## Root User

| ID | Claim | Source |
|----|-------|--------|
| USR-014 | Root authorized keys default to an empty list in the public repo | `modules/users.nix` |
| USR-015 | Root home persistence includes `.ssh`, `.config/nix`, `.docker`, and `.gitconfig` | `modules/users.nix` |

## Template Safety Assertions

| ID | Claim | Source |
|----|-------|--------|
| USR-017 | When `allowUnsafePlaceholders = false`: assertion rejects an empty root authorized_keys list | `modules/users.nix` |
| USR-018 | `allowUnsafePlaceholders` exists only for eval fixtures; real hosts must provide root SSH material, while fixtures also set `users.allowNoPasswordLogin = true` to bypass the NixOS lockout assertion | `flake.nix`, `modules/users.nix` |
| USR-019 | Unconditional assertion: agent not in docker | `modules/users.nix` |
