# Impermanence Specification

This document specifies the BTRFS root rollback mechanism and the persistence
manifest that survives across reboots.

Source: `modules/impermanence.nix`, `modules/boot.nix`, `scripts/btrfs-rollback.sh`

## BTRFS Root Rollback

| ID | Claim | Source |
|----|-------|--------|
| IMP-001 | Root filesystem uses BTRFS subvolume rollback (not tmpfs) — server workloads need disk-backed root | `modules/impermanence.nix`, `@decision IMP-01` |
| IMP-002 | Rollback script runs in initrd via `boot.initrd.postResumeCommands` | `modules/boot.nix` lines 9-10 |
| IMP-003 | On each boot: current `root` subvolume moved to `old_roots/<timestamp>` | `scripts/btrfs-rollback.sh` lines 17-20 |
| IMP-004 | Old root snapshots older than 30 days are recursively deleted | `scripts/btrfs-rollback.sh` lines 31-33 |
| IMP-005 | Fresh `root` subvolume created each boot | `scripts/btrfs-rollback.sh` line 35 |
| IMP-006 | Non-systemd initrd enforced: `boot.initrd.systemd.enable = false` | `modules/base.nix` line 74 |

## Persistence Manifest

### Core System State

| ID | Claim | Source |
|----|-------|--------|
| IMP-007 | `/var/lib/nixos` persisted (UID/GID maps, declarative users/groups) | `modules/impermanence.nix` line 36 |
| IMP-009 | `/var/lib/systemd/timers` persisted (Persistent=true timer stamps) | `modules/impermanence.nix` line 37 |
| IMP-010 | `/var/lib/systemd/timesync` persisted (NTP clock file) | `modules/impermanence.nix` line 38 |
| IMP-011 | `/var/lib/systemd/linger` not persisted — user linger is not part of the public model | `modules/impermanence.nix`, `tests/eval/config-checks.nix:no-linger-persistence` |
| IMP-012 | `/var/lib/private` persisted (DynamicUser services) | `modules/impermanence.nix` line 40 |
| IMP-013 | `/etc/machine-id` persisted (journal continuity) | `modules/impermanence.nix` line 30 |
| IMP-014 | `/var/lib/systemd/random-seed` persisted (kernel entropy) | `modules/impermanence.nix` line 31 |
| IMP-015 | `hideMounts = true` | `modules/impermanence.nix` line 18 |

### Network State

| ID | Claim | Source |
|----|-------|--------|
| IMP-017 | SSH host keys persisted (`/etc/ssh/ssh_host_ed25519_key` and `.pub`) | `modules/networking.nix` lines 160-163 |

### Root Home State

| ID | Claim | Source |
|----|-------|--------|
| IMP-020 | `/root/.ssh`, `.config/nix`, `.docker` persisted | `modules/users.nix` lines 113-117 |
| IMP-021 | `/root/.gitconfig` persisted (file) | `modules/users.nix` line 119 |

### Agent Home State

| ID | Claim | Source |
|----|-------|--------|
| IMP-022 | Agent persist paths derived from `agentCfg.home` (not hardcoded) | `tests/eval/config-checks.nix:impermanence-agent-home` |
| IMP-023 | Agent directories persisted: `.claude`, `.config/claude`, `.config/git`, `.local/share/direnv` | `modules/agent-sandbox.nix` lines 177-183 |
| IMP-024 | Agent files persisted: `.gitconfig`, `.bash_history` | `modules/agent-sandbox.nix` lines 185-189 |

### Project Data

| ID | Claim | Source |
|----|-------|--------|
| IMP-025 | `/data/projects` persisted | `modules/agent-compute.nix` lines 34-36 |

## Activation Ordering

| ID | Claim | Source |
|----|-------|--------|
| IMP-026 | `setupSecrets` depends on `persist-files` — sops-nix reads persisted SSH host key before decrypting secrets | `modules/impermanence.nix` lines 12-14, `@decision IMP-06` |
| IMP-027 | `/etc` permissions fixed after `etc` activation for sshd strict mode | `modules/impermanence.nix` lines 5-9, `@decision IMP-05` |
