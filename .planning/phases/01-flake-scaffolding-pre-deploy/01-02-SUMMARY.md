---
phase: 01-flake-scaffolding-pre-deploy
plan: 02
subsystem: infra
tags: [sops-nix, age, secrets, ssh-host-key]

requires:
  - phase: 01-plan-01
    provides: flake skeleton with sops-nix module config
provides:
  - .sops.yaml with admin + host age key anchors and creation rules
  - sops-encrypted secrets/acfs.yaml decryptable by both keys
  - Pre-generated SSH host ed25519 key pair for Phase 2 nixos-anywhere deployment
  - .gitignore excluding tmp/ from version control
affects: [phase-02-bootable-base-system]

tech-stack:
  added: [sops, age]
  patterns: [pre-generated-host-key, dual-age-key-encryption]

key-files:
  created:
    - .sops.yaml
    - .gitignore
  modified:
    - secrets/acfs.yaml

key-decisions:
  - "Pre-generated SSH host key stored in tmp/host-key/ (gitignored), deployed via nixos-anywhere --extra-files in Phase 2"
  - "Dual age keys: admin key for local editing + host key for server-side decryption"
  - "Age keys derived from SSH ed25519 keys (no separate age keyfile management)"

patterns-established:
  - "secrets/acfs.yaml is the single encrypted secrets file for the acfs host"
  - ".sops.yaml creation_rules route secrets/* to the correct key groups"

duration: 5min
completed: 2026-02-13
---

# Phase 1 Plan 02: sops-nix Secrets Bootstrap Summary

**Complete sops-nix secrets pipeline: pre-generated SSH host key, age public keys derived, `.sops.yaml` with encryption rules, encrypted secrets file verified locally**

## Performance

- **Duration:** ~5 min
- **Completed:** 2026-02-13
- **Files created:** 2 (.sops.yaml, .gitignore)
- **Files modified:** 1 (secrets/acfs.yaml)

## Accomplishments
- Created `.sops.yaml` with admin and host age key anchors and creation rules for `secrets/acfs.yaml`
- Encrypted `secrets/acfs.yaml` with sops using dual age keys (admin + host)
- Pre-generated SSH host ed25519 key pair in `tmp/host-key/` for Phase 2 `nixos-anywhere --extra-files`
- Added `.gitignore` to exclude `tmp/` from version control

## Task Commits

1. **feat(01-02): bootstrap sops-nix secrets pipeline** - `9846715`

## Files Created/Modified
- `.sops.yaml` - sops encryption rules with age key anchors and creation rules
- `.gitignore` - Excludes tmp/ directory
- `secrets/acfs.yaml` - sops-encrypted secrets (was placeholder, now real encrypted YAML)

## Decisions Made
- Admin age key `age1q4c...` for local secret editing from dev machine
- Host age key `age1k55...` derived from pre-generated SSH host key for server decryption
- `tmp/host-key/` holds private key material, excluded from git

## Deviations from Plan

None.

## Next Phase Readiness
- Phase 1 complete — flake skeleton + secrets pipeline both done
- Ready for Phase 2 (Bootable Base System) or Phase 3.1 (Parts Integration)

---
*Phase: 01-flake-scaffolding-pre-deploy*
*Completed: 2026-02-13*
