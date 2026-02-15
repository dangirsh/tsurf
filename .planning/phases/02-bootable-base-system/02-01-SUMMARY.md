---
phase: 02-bootable-base-system
plan: 01
subsystem: infra
tags: [nftables, openssh, firewall, nixos-modules]

requires:
  - phase: 01-flake-scaffolding-pre-deploy
    provides: NixOS flake skeleton with networking.nix and users.nix modules
provides:
  - Hardened networking.nix with nftables + SSH lockdown
  - users.nix with docker group membership
affects: [phase-02-plan-02-deployment, phase-03-networking-secrets-docker]

tech-stack:
  added: []
  patterns: [nftables-firewall-backend, ssh-key-only-auth]

key-files:
  created: []
  modified:
    - modules/networking.nix
    - modules/users.nix

key-decisions:
  - "nftables backend enabled alongside standard firewall API (no raw nftables rules)"
  - "PermitRootLogin changed from prohibit-password to no (fully reject root SSH)"
  - "KbdInteractiveAuthentication disabled (prevents PAM-based auth bypass)"
  - "docker group added pre-emptively before Docker enable (Phase 3)"

patterns-established:
  - "Module-level @decision annotations for requirement traceability"

duration: ~5min
completed: 2026-02-15
---

# Phase 2 Plan 01: Module Config Hardening

**nftables firewall backend, SSH key-only auth with root login rejected, and docker group for dangirsh**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-02-15
- **Completed:** 2026-02-15
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Enabled nftables as firewall backend (modern replacement for iptables)
- Tightened SSH to key-only with KbdInteractiveAuthentication disabled and PermitRootLogin "no"
- Added docker group to dangirsh user for Phase 3 Docker enable
- `nix flake check` passes with hardened configuration

## Task Commits

1. **Task 1: Harden networking.nix** - `f5ad0f2` (feat)
2. **Task 2: Add docker group to users.nix** - `c2f83e2` (feat)

## Files Created/Modified
- `modules/networking.nix` - nftables + SSH hardening (NET-01, NET-02, NET-04)
- `modules/users.nix` - docker group added to dangirsh (SYS-01)

## Decisions Made
- nftables backend with standard firewall API (no raw rules needed)
- PermitRootLogin "no" (was "prohibit-password" -- tightened per NET-01)
- Root SSH keys retained temporarily for deployment fallback (removed in Plan 02)
- docker group pre-added before Phase 3 Docker enable (NixOS handles gracefully)

## Deviations from Plan

None - plan executed as written. Codex started execution but timed out waiting for `nix flake check`; orchestrator completed the work directly.

## Issues Encountered
- Codex CLI timed out during `nix flake check` (NixOS evaluation takes ~2 min). Work completed by orchestrator directly.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Module config hardened, ready for Plan 02 (nixos-anywhere deployment)
- Root SSH key kept as lockout fallback during initial deployment

---
*Phase: 02-bootable-base-system*
*Completed: 2026-02-15*
