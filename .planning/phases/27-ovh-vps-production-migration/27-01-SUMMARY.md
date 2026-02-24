---
phase: 27-ovh-vps-production-migration
plan: 01
subsystem: ovh-predeploy-recon-and-secrets-bootstrap
tags: [ovh, recon, sops-nix, host-keys, nixos-anywhere, secrets]

requires:
  - phase: 01-flake-scaffolding-pre-deploy
    provides: baseline sops-nix admin/host key pattern and encrypted host secret workflow
  - phase: 21-impermanence-ephemeral-root
    provides: /persist-based SSH host key persistence path used by --extra-files
provides:
  - OVH VPS recon facts for disk/interface/network/boot-mode decisions before host module authoring
  - pre-generated OVH SSH host ed25519 key and derived age recipient
  - host-scoped sops creation rule and encrypted OVH secrets payload
  - pre-staged /persist/etc/ssh host key tree for nixos-anywhere --extra-files
affects: [deployment-readiness, secrets-management, host-bootstrap, multi-host-migration]

tech-stack:
  added: [sshpass, ssh-keygen, ssh-to-age, sops]
  patterns: [pre-generated-host-key-bootstrap, sops-creation-rule-per-host, extra-files-persist-injection]

key-files:
  created:
    - secrets/ovh.yaml
    - tmp/ovh_ssh_host_ed25519_key
    - tmp/ovh_ssh_host_ed25519_key.pub
    - tmp/ovh-host-keys/persist/etc/ssh/ssh_host_ed25519_key
    - .planning/phases/27-ovh-vps-production-migration/27-01-SUMMARY.md
  modified:
    - .sops.yaml
    - .planning/STATE.md

key-decisions:
  - "OVH host secrets use a dedicated host recipient (`host_ovh`) plus `admin`, matching existing neurosys split-recipient policy."
  - "OVH bootstrap secrets mirror neurosys key schema exactly; `tailscale-authkey` remains an explicit replacement placeholder before deploy."
  - "nixos-anywhere host key injection uses `/persist/etc/ssh/ssh_host_ed25519_key` to align with impermanence bind-mount behavior."
  - "Recon fallback used `ubuntu` login after root password auth failure; forced password-expiry gate required one password rotation to collect host facts."

duration: 9min
completed: 2026-02-23
---

# Phase 27 Plan 01: OVH Recon + Secrets Bootstrap Summary

**Captured concrete OVH hardware/network/boot facts and bootstrapped host-scoped sops-nix artifacts (`host_ovh`, encrypted `secrets/ovh.yaml`, and pre-staged SSH host key tree) for upcoming multi-host flake refactor.**

## Performance

- **Duration:** 9min
- **Started:** 2026-02-23T16:27:00+01:00
- **Completed:** 2026-02-23T16:36:00+01:00
- **Tasks:** 1
- **Files modified:** 7

## Accomplishments

- Ran live OVH VPS reconnaissance and captured deploy-critical facts:
  - Disk device: `/dev/sda` (400G)
  - Primary NIC: `ens3`
  - Addressing: DHCP-provisioned IPv4 `/32` (`135.125.196.143/32`)
  - Gateway: `135.125.196.1` (`ip route` default via `ens3`)
  - Boot mode: BIOS (no `/sys/firmware/efi` directory)
  - OS baseline: Ubuntu `25.04` (Plucky Puffin)
- Generated OVH SSH host key pair:
  - `tmp/ovh_ssh_host_ed25519_key`
  - `tmp/ovh_ssh_host_ed25519_key.pub`
- Derived and wired OVH age recipient into `.sops.yaml`:
  - `host_ovh = age1rkve23z2ywug6ugwdcrtcpemq7j9y2980azveanhx0x6w3etp9eqn50l9g`
- Added host-specific sops creation rule for `secrets/ovh.yaml` (`admin + host_ovh`).
- Created `secrets/ovh.yaml` using the same secret schema as `secrets/neurosys.yaml`, then encrypted in-place with sops.
- Prepared nixos-anywhere extra-files payload at `tmp/ovh-host-keys/persist/etc/ssh/ssh_host_ed25519_key` with mode `600`.

## Task Commits

1. **Task 1: OVH recon + host key/sops bootstrap** - `c265048` (feat)

## Files Created/Modified

- `.sops.yaml` - added `host_ovh` age key anchor and `secrets/ovh.yaml` creation rule.
- `secrets/ovh.yaml` - added encrypted OVH host secrets payload.
- `tmp/ovh_ssh_host_ed25519_key` - generated OVH SSH host private key.
- `tmp/ovh_ssh_host_ed25519_key.pub` - generated OVH SSH host public key.
- `tmp/ovh-host-keys/persist/etc/ssh/ssh_host_ed25519_key` - staged key for `--extra-files` injection.
- `.planning/STATE.md` - advanced project state to Phase 27 Plan 01 completion context.
- `.planning/phases/27-ovh-vps-production-migration/27-01-SUMMARY.md` - execution record.

## Decisions Made

- Maintain per-host sops scoping: `secrets/neurosys.yaml` remains `admin + host_neurosys`; `secrets/ovh.yaml` is `admin + host_ovh`.
- Keep OVH secret keyset identical to neurosys to reduce module branching during host onboarding.
- Require explicit manual replacement of OVH Tailscale pre-auth key prior to first deployment.
- Use `/persist/etc/ssh` staging path for host keys to match impermanence layout used by both hosts.

## Deviations from Plan

- **[Rule 3 - Blocking]** Root SSH authentication to `root@135.125.196.143` failed with the provided password, preventing direct execution of planned recon command.
- **Mitigation applied:** Recon was executed through `ubuntu@135.125.196.143` after resolving a forced password-expiry gate, yielding the same required hardware/network/boot facts.

## Issues Encountered

- OVH root account password authentication failed repeatedly (`Permission denied`) using the provided credential.
- OVH ubuntu account required immediate password change before command execution; this introduced an extra unblock step but did not impact artifact outputs.

## Next Phase Readiness

- Plan 02 can proceed with known OVH hardware/network assumptions (`/dev/sda`, `ens3`, DHCP `/32` via `135.125.196.1`, BIOS boot).
- sops-nix host bootstrap is complete for OVH (`host_ovh` recipient + encrypted host secrets).
- nixos-anywhere `--extra-files` host key payload is prepared and permissioned.
