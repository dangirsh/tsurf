# Boot and Base System Specification

This document specifies the bootloader configuration, base system packages,
and foundational system settings.

Source: `modules/boot.nix`, `modules/base.nix`, `hosts/hardware.nix`, `hosts/disko-config.nix`

## Bootloader

| ID | Claim | Source |
|----|-------|--------|
| BAS-001 | GRUB bootloader enabled with EFI support | `modules/boot.nix` lines 2-5 |
| BAS-002 | `efiInstallAsRemovable = true` — works without NVRAM modification | `modules/boot.nix` line 5 |
| BAS-003 | `configurationLimit = 10` — limits stored generations | `modules/boot.nix` line 6 |
| BAS-004 | BTRFS rollback script runs in initrd `postResumeCommands` | `modules/boot.nix` lines 9-10 |
| BAS-005 | Non-systemd initrd enforced: `boot.initrd.systemd.enable = false` | `modules/base.nix` line 74 |

## Nix Configuration

| ID | Claim | Source |
|----|-------|--------|
| BAS-006 | Experimental features enabled: `nix-command`, `flakes` | `modules/base.nix` line 16 |
| BAS-007 | Store auto-optimization enabled | `modules/base.nix` line 17 |
| BAS-008 | Weekly garbage collection, keep 30 days | `modules/base.nix` lines 34-38 |
| BAS-009 | Nix channels disabled, nixPath cleared | `modules/base.nix` lines 11-12, `@decision SYS-02` |
| BAS-010 | `environment.defaultPackages` emptied — nothing lands outside Nix declarations | `modules/base.nix` line 13 |
| BAS-011 | Numtide cache configured as extra substituter | `modules/base.nix` lines 26-31 |

## Unfree Packages

| ID | Claim | Source |
|----|-------|--------|
| BAS-012 | Unfree allowlist: `claude-code` only | `modules/base.nix` lines 3-5 |

## Base System Packages

| ID | Claim | Source |
|----|-------|--------|
| BAS-013 | System packages: git, rsync, ripgrep, fd | `modules/base.nix` lines 54-59 |

## srvos Integration

| ID | Claim | Source |
|----|-------|--------|
| BAS-014 | srvos server module applied to all hosts | `flake.nix` line 61 |
| BAS-015 | Man pages disabled (`srvos.server.docs.enable = false`) | `modules/base.nix` line 66 |
| BAS-016 | `command-not-found` disabled | `modules/base.nix` line 67 |

## Flake Inputs

| ID | Claim | Source |
|----|-------|--------|
| BAS-017 | nixpkgs pinned to `nixos-25.11` | `flake.nix` line 3 |
| BAS-018 | home-manager pinned to `release-25.11` with nixpkgs follows | `flake.nix` lines 4-7 |
| BAS-019 | All inputs follow nixpkgs where applicable (sops-nix, disko, llm-agents, deploy-rs, srvos, nixos-anywhere) | `flake.nix` lines 8-35 |
| BAS-020 | Common modules applied to all hosts: srvos, disko, impermanence, sops-nix, home-manager | `flake.nix` lines 60-78 |
| BAS-021 | tsurf overlay provides the pinned `nono` package | `flake.nix` |
| BAS-022 | llm-agents overlay provides `claude-code`, `codex`, etc. | `flake.nix` line 68 |
| BAS-023 | Coredumps are disabled at both the systemd and kernel layers (`systemd.coredump.enable = false`, `kernel.core_pattern = "|/bin/false"`) | `modules/base.nix` |
