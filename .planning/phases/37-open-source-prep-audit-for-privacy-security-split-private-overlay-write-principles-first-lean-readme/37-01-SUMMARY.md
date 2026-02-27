---
phase: 37-open-source-prep-audit-for-privacy-security-split-private-overlay-write-principles-first-lean-readme
plan: 01
subsystem: privacy-audit
tags: [privacy, open-source-prep, nixos, sanitization]
requires: []
provides: [public-safe-flake, sanitized-identifiers, private-overlay-hooks]
affects:
  - flake.nix
  - modules/
  - hosts/
  - home/
  - .gitignore
tech-stack: [nix, nixos, home-manager, sops-nix]
key-files:
  - flake.nix
  - modules/default.nix
  - modules/users.nix
  - modules/networking.nix
  - modules/homepage.nix
  - .gitignore
key-decisions:
  - Export `nixosModules.default` from public flake for private overlay composition.
  - Remove private module imports from public default module set.
  - Replace all personal identity markers with neutral placeholders (`myuser`, example repos, placeholder keys).
  - Keep public module evaluable by removing private-service coupled secret/template references.
duration: 11m
completed: true
---

# Phase 37 Plan 01: Privacy Audit Summary

Sanitized the repository for public release by removing personal identifiers and private service wiring, while preserving generic infrastructure modules and making private customization explicit via overlay hooks.

## Performance

- Duration: ~11 minutes
- Start: 2026-02-27T16:57:53+01:00
- End: 2026-02-27T17:08:44+01:00
- Tasks completed: 4/4
- Files modified: 20

## Accomplishments

- Removed static host IP/gateway/nameserver values from `hosts/neurosys/default.nix` and replaced with a private-overlay note.
- Replaced personal user identity and SSH key material with public-safe placeholders in users/home config.
- Replaced hardcoded `dangirsh` paths with `myuser` across agent compute, syncthing, home defaults, and related modules.
- Removed private flake inputs (`parts`, `claw-swap`, `dangirsh-site`, `automaton`) and exported `nixosModules.default`.
- Removed private modules from `modules/default.nix` public import set.
- Removed private service entries from homepage dashboard and private-only ports from networking internal assertions.
- Moved nginx public/private service implementation out of public config surface via placeholder module + host import removal.
- Added ignore guards for `.planning/`, `secrets/`, `.sops.yaml`, and `.worktrees/`.
- Resolved `nix flake check` blockers introduced by private-module extraction (secret owners/templates and restic pre-hook assumptions).

## Task Commits

- Task 1: scrub host IP and identity defaults -> `b71f018`
- Task 2: abstract username/private repo identifiers -> `43ff565`
- Task 3: remove private flake inputs, export public modules, update ignores -> `b83df20`
- Task 4 (+check blockers): remove private service bindings, pass flake checks -> `5384441`

## Files Created/Modified

- Created: `.planning/phases/37-open-source-prep-audit-for-privacy-security-split-private-overlay-write-principles-first-lean-readme/37-01-SUMMARY.md`
- Modified:
  - `.gitignore`
  - `flake.lock`
  - `flake.nix`
  - `home/cass.nix`
  - `home/default.nix`
  - `home/git.nix`
  - `hosts/neurosys/default.nix`
  - `hosts/ovh/default.nix`
  - `modules/agent-compute.nix`
  - `modules/default.nix`
  - `modules/home-assistant.nix`
  - `modules/homepage.nix`
  - `modules/impermanence.nix`
  - `modules/networking.nix`
  - `modules/nginx.nix`
  - `modules/repos.nix`
  - `modules/restic.nix`
  - `modules/secrets.nix`
  - `modules/syncthing.nix`
  - `modules/users.nix`

## Decisions Made

- Public repo now uses `myuser` as the canonical example username.
- Public repo ships placeholder SSH key comments instead of any real public key values.
- Private-domain/service routing moved out of host imports and into private overlay responsibility.
- Restic public template keeps generic backup behavior and defers service-specific dump hooks to private overlay.

## Deviations from Plan

- [Rule 2 - Missing Critical] Extended username scrubbing beyond listed files to `home/default.nix`, `home/cass.nix`, `modules/impermanence.nix`, and `modules/secrets.nix` so global `dangirsh` grep checks pass.
- [Rule 2 - Missing Critical] Sanitized `modules/nginx.nix` (placeholder module) because private domains and fixed IPs remained in tracked files.
- [Rule 3 - Blocking] Removed residual `automaton` secret/template and adjusted secret ownership after private module/input removal broke evaluation.
- [Rule 3 - Blocking] Removed private PostgreSQL dump assumption from restic pre-hook to restore `nix flake check` in the public module set.
- [Rule 3 - Blocking] Added `users.allowNoPasswordLogin = true` in the public template to satisfy NixOS lockout assertion when placeholder SSH keys are used.

## Issues Encountered

- `nix flake check` initially failed due to dangling references to removed private services (`automaton`, ACME user, PostgreSQL package assumptions).
- Public-safe placeholder SSH keys triggered NixOS lockout assertion until explicit template-safe auth setting was added.

## Next Phase Readiness

- Privacy audit requirements for Phase 37 Plan 01 are met.
- Public module set evaluates cleanly with `nix flake check`.
- Repo is ready to proceed to Phase 37 Plan 02 (private overlay principles/split design).

## Self-Check: PASSED
