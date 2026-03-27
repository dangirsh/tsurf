---
phase: 159-cut-public-repo-to-minimal-core
plan: 02
subsystem: docs
tags: [docs, onboarding, cleanup]
provides:
  - "Public newcomer entry point via QUICKSTART.md"
  - "Removal of maintainer-only spec/ content from public tree"
affects:
  - "QUICKSTART.md"
  - "spec/"
  - ".planning/STATE.md"
tech-stack:
  added: []
  patterns:
    - "Public template + private overlay onboarding split"
    - "Opt-in extras positioning for private overlays"
key-files:
  created:
    - "QUICKSTART.md"
    - ".planning/phases/159-cut-public-repo-to-minimal-core/159-02-SUMMARY.md"
  modified:
    - ".planning/STATE.md"
  deleted:
    - "spec/README.md"
    - "spec/agent-compute.md"
    - "spec/backup.md"
    - "spec/boot-and-base.md"
    - "spec/deployment.md"
    - "spec/extras.md"
    - "spec/impermanence.md"
    - "spec/networking.md"
    - "spec/sandbox.md"
    - "spec/secrets.md"
    - "spec/security-model.md"
    - "spec/testing.md"
    - "spec/users-and-privileges.md"
key-decisions:
  - "Claim-level specs are maintainer material and should not be on the newcomer path in the public repo."
  - "QUICKSTART.md is the single newcomer entry point for public validation and private overlay bootstrap."
duration: 20min
completed: 2026-03-27
---

# Phase 159 Plan 02: Remove spec and add QUICKSTART Summary

**Plan 02 removed maintainer-only `spec/` files from the public repo and added `QUICKSTART.md` as the newcomer path.**

## Accomplishments
- Deleted the full `spec/` directory from version control.
- Added a root-level `QUICKSTART.md` that covers:
  - prerequisites
  - public template validation (`git hooks` + `nix flake check`)
  - private overlay creation and `tsurf-init`
  - sops-nix secret setup with age key derivation path
  - first deploy command
  - extras as opt-in (linked to `docs/extras.md`)
  - next-step links to `SECURITY.md` and `docs/architecture.md`
- Updated `.planning/STATE.md` to mark Plan 02 complete and record the decision.

## Verification
- Confirmed `spec/` is removed from tracked files.
- Confirmed `QUICKSTART.md` exists at repo root.
- Confirmed `QUICKSTART.md` links to:
  - `SECURITY.md`
  - `docs/architecture.md`
  - `docs/extras.md`

## Next Phase Readiness
Plan 03 can now perform cross-doc consistency updates (README, architecture, extras, security, and private overlay docs) with `QUICKSTART.md` and `spec/` removal as the new baseline.
