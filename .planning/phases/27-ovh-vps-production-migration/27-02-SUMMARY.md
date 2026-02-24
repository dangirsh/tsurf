---
phase: 27-ovh-vps-production-migration
plan: 02
subsystem: multi-host-flake-and-deploy-targeting
tags: [nixos, flake, deploy-rs, multi-host, ovh, contabo]

requires:
  - phase: 27-ovh-vps-production-migration
    plan: 01
    provides: OVH hardware/network/boot facts and host-scoped sops bootstrap
provides:
  - dual nixosConfigurations (`neurosys`, `ovh`) with shared module stack and host-specific overrides
  - dual deploy-rs nodes for staging (Contabo) and production (OVH)
  - host-specific secrets, NAT interface, GRUB device, and homepage host data wiring
  - multi-target deploy script with `--node` and node-aware default SSH targets
affects: [deployment, host-topology, secrets-resolution, boot-config, networking]

tech-stack:
  added: [none]
  patterns: [mkHost-helper, host-owned-overrides, multi-node-deploy-wrapper]

key-files:
  created:
    - hosts/ovh/default.nix
    - hosts/ovh/hardware.nix
    - hosts/ovh/disko-config.nix
    - .planning/phases/27-ovh-vps-production-migration/27-02-SUMMARY.md
  modified:
    - flake.nix
    - modules/secrets.nix
    - modules/docker.nix
    - modules/homepage.nix
    - modules/boot.nix
    - hosts/neurosys/default.nix
    - scripts/deploy.sh
    - .planning/STATE.md

key-decisions:
  - "Kept `../../modules` imported from each host directory and excluded `./modules` from flake-level `commonModules` to avoid duplicate module imports."
  - "Moved `sops.defaultSopsFile`, `networking.nat.externalInterface`, and `boot.loader.grub.device` ownership to host configs so shared modules remain provider-agnostic."
  - "Switched homepage host coupling from hardcoded Tailscale IP to `config.networking.hostName`/MagicDNS and wildcard `allowedHosts` under Tailscale trusted-interface controls."
  - "Deploy wrapper now targets flake node via `--node` (`neurosys` default, `ovh` optional) while preserving `--target` for SSH lock/health-check channel control."

duration: 7min
completed: 2026-02-23
---

# Phase 27 Plan 02: Multi-Host Flake Refactor Summary

**Shipped a two-host NixOS topology with shared modules and host-owned overrides, plus node-selectable deploy automation for Contabo staging and OVH production.**

## Performance

- **Duration:** 7min
- **Started:** 2026-02-23T16:52:00+01:00
- **Completed:** 2026-02-23T16:59:00+01:00
- **Tasks:** 2
- **Files modified:** 12

## Accomplishments

- Parameterized shared modules by removing host-bound defaults:
  - `modules/secrets.nix` no longer sets `sops.defaultSopsFile`.
  - `modules/docker.nix` no longer hardcodes `networking.nat.externalInterface = "eth0"`.
  - `modules/homepage.nix` no longer hardcodes Tailscale IP/hostname labels and now derives host data from `config.networking.hostName` with `allowedHosts = "*"`.
  - `modules/boot.nix` no longer hardcodes `boot.loader.grub.device`.
- Updated staging host (`hosts/neurosys/default.nix`) with host-owned overrides for grub device, NAT external interface, and SOPS file.
- Added full OVH host definition under `hosts/ovh/`:
  - `default.nix` with OVH DHCP networking, host-specific NAT/grub/sops settings, and srvos overrides.
  - `hardware.nix` using qemu guest profile and virtio kernel modules.
  - `disko-config.nix` with BIOS-compatible GPT layout and `/dev/sda` device mapping.
- Refactored `flake.nix` with `commonModules` + `mkHost` helper and added:
  - `nixosConfigurations.neurosys`
  - `nixosConfigurations.ovh`
  - `deploy.nodes.neurosys`
  - `deploy.nodes.ovh`
- Extended `scripts/deploy.sh` with `--node` support:
  - default node `neurosys`
  - OVH option via `--node ovh`
  - node-specific default targets (`root@neurosys`, `root@neurosys-prod`)
  - deploy-rs activation path now uses `"$FLAKE_DIR#$NODE"`
  - lock paths and deploy messaging are node-aware.
- Verified end-to-end with `nix flake check` (both host configs evaluated and checks passed).

## Task Commits

1. **Task 1: Parameterize shared modules and add OVH host configs** - `74c0ead` (feat)
2. **Task 2: Refactor flake outputs and deploy wrapper for multi-node** - `be99739` (feat)

## Files Created/Modified

- `flake.nix` - added `commonModules`, `mkHost`, and dual `nixosConfigurations`/`deploy.nodes`.
- `hosts/ovh/default.nix` - new OVH host entrypoint with host-specific overrides.
- `hosts/ovh/hardware.nix` - new OVH hardware profile.
- `hosts/ovh/disko-config.nix` - new OVH disk layout on `/dev/sda`.
- `modules/secrets.nix` - removed shared `defaultSopsFile` default.
- `modules/docker.nix` - removed shared hardcoded external NAT interface.
- `modules/homepage.nix` - replaced hardcoded host/IP values with hostname-derived settings.
- `modules/boot.nix` - removed shared hardcoded GRUB device.
- `hosts/neurosys/default.nix` - added host-local GRUB/NAT/SOPS settings.
- `scripts/deploy.sh` - added `--node`, node validation/defaults, and node-based deploy target wiring.
- `.planning/STATE.md` - advanced project state to Plan 27-02 completion.
- `.planning/phases/27-ovh-vps-production-migration/27-02-SUMMARY.md` - execution record.

## Decisions Made

- Host-scoped values remain in host modules, not shared modules.
- Deploy-rs node selection is explicit via `--node`; `--target` remains an SSH transport override only.
- OVH host keeps DHCP networking per 27-01 reconnaissance data.
- Homepage inter-service links now rely on hostnames (MagicDNS), not fixed Tailscale IP literals.

## Deviations from Plan

- None.

## Issues Encountered

- `shellcheck` was not present in the base PATH (`command not found`); validation relied on successful `scripts/deploy.sh --help` execution and full flake checks.

## Next Phase Readiness

- Plan 27-03 can bootstrap OVH with `nixos-anywhere` using `.#ovh` and proceed with staged service migration.
- Both staging and production flake targets now evaluate and are deploy-rs addressable.
- Host-specific secret routing is in place (`secrets/neurosys.yaml`, `secrets/ovh.yaml`).
