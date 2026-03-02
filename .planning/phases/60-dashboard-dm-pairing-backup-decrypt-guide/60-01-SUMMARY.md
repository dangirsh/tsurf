---
phase: 60-dashboard-dm-pairing-backup-decrypt-guide
plan: 01
subsystem: matrix
tags: [matrix, mautrix, provisioning-api, dm-guide, nixos, sops, python]

requires:
  - phase: 35-matrix-hub
    provides: Conduit + mautrix bridge baseline (signal/whatsapp/telegram)

provides:
  - Matrix bridge provisioning API defaults in public config
  - DM pairing guide service on internal port 8086
  - Host imports for matrix + dm-guide modules
  - Passing public-repo `nix flake check` with updated secrets manifest

affects: [60-02, 60-03]

key-files:
  created: [modules/dm-guide.nix, .planning/phases/60-dashboard-dm-pairing-backup-decrypt-guide/60-01-SUMMARY.md]
  modified: [modules/matrix.nix, modules/networking.nix, hosts/neurosys/default.nix, secrets/neurosys.yaml, .test-status, .planning/STATE.md]

key-decisions:
  - "MTX-06: Enable provisioning API using public placeholder shared_secret with private override"
  - "MTX-07: Single shared provisioning secret for all bridge provisioning endpoints"
  - "DMG-01: Standalone stdlib Python server module for DM onboarding UI"
  - "DMG-02: Provisioning secret injected via systemd LoadCredential"

duration: 8min
completed: 2026-03-02
---

# Phase 60 Plan 01: Matrix Provisioning + DM Guide Summary

Implemented the public-repo portion of DM bridge pairing support: enabled provisioning API config for all three Matrix bridges, added a standalone `dm-guide` pairing service/UI, wired host imports and internal firewall assertions, and passed full `nix flake check`.

## Performance Metrics

- Duration: ~8 minutes (first commit 18:07:36+01:00, final task commit 18:15:27+01:00)
- Tasks in scope: 5 (A, B, C, D, F)
- Files created: 2
- Files modified: 6
- Verification: `nix flake check` passed; `.test-status` updated to `pass|0|1772471682`

## Accomplishments

- Added Matrix provisioning decisions (MTX-06/MTX-07) and provisioning settings for:
  - `mautrix-whatsapp.settings.provisioning.shared_secret = "disable"`
  - `mautrix-signal.settings.provisioning.shared_secret = "disable"`
  - `mautrix-telegram.settings.appservice.provisioning.enabled/shared_secret`
- Added Matrix secret declarations in `modules/matrix.nix` including `dm-provisioning-secret`.
- Created `modules/dm-guide.nix`:
  - `pkgs.writers.writePython3Bin` + `flakeIgnore = ["E501"]`
  - Single-page HTML UI with dark theme and sections for Signal/WhatsApp/Telegram
  - Client-side QR generation via CDN `qrcode-generator`
  - `/api/bridge/{bridge}/login/*` proxy routing to bridge provisioning APIs
  - Bridge-specific login helpers for QR start/wait and Telegram phone/code/2FA steps
  - systemd service with `DynamicUser`, `StateDirectory`, `LoadCredential`, hardening
  - Listener bound to `0.0.0.0:8086`
- Updated `modules/networking.nix`:
  - Removed stale `[OVH only]` tags from Matrix bridge/conduit internal ports
  - Added internal-only port `8086 = dm-guide`
- Updated `hosts/neurosys/default.nix` imports:
  - `../../modules/matrix.nix`
  - `../../modules/dm-guide.nix`
- Added encrypted placeholder `dm-provisioning-secret` to `secrets/neurosys.yaml` so sops manifest validation succeeds during eval checks.

## Task Commits

- Task A: `647e01a` — `feat(60-01): enable matrix provisioning API defaults`
- Task B: `f9bfc63` — `feat(60-01): import matrix and dm-guide modules on neurosys`
- Task C: `55dd322` — `feat(60-01): add dm-guide provisioning web service`
- Task D: `b1a1877` — `feat(60-01): register dm-guide as internal-only service port`
- [Rule 3 - Blocking] Fix: `f4d5ccc` — `fix(60-01): add dm provisioning secret and escape embedded JS`
- Task F: `c585439` — `test(60-01): record passing flake check status`

## Files Created/Modified

- `modules/dm-guide.nix` (created): standalone DM pairing service module + HTML + proxy server.
- `modules/matrix.nix` (modified): provisioning config + decision annotations + secret declarations.
- `modules/networking.nix` (modified): Matrix label cleanup + `8086` internal-only port.
- `hosts/neurosys/default.nix` (modified): imports `matrix.nix` and `dm-guide.nix`.
- `secrets/neurosys.yaml` (modified): added encrypted `dm-provisioning-secret` key.
- `.test-status` (modified): pass stamp after successful flake checks.
- `.planning/phases/60-dashboard-dm-pairing-backup-decrypt-guide/60-01-SUMMARY.md` (created): execution summary.
- `.planning/STATE.md` (modified): current position + decision updates.

## Decisions Made

- MTX-06: Provisioning API is enabled in public module config with placeholder shared secrets (`"disable"`), with private overlay intended to inject real values.
- MTX-07: One shared provisioning secret is used across Signal/WhatsApp/Telegram bridges for this internal-only MVP.
- DMG-01: DM guide is a standalone stdlib Python server to keep dependency and operational complexity low.
- DMG-02: `dm-provisioning-secret` is consumed via `LoadCredential` and `CREDENTIALS_DIRECTORY` to avoid Nix-store secret exposure.

## Deviations from Plan

- [Rule 3 - Blocking] Added encrypted `dm-provisioning-secret` to `secrets/neurosys.yaml` to satisfy sops manifest validation in `nix flake check`.
- [Rule 1 - Bug] Escaped embedded JavaScript empty-string literals in the Nix multi-line string to resolve parse failure (`''` token collision).

## Issues Encountered

- Initial flake eval failed on a Nix parser error caused by JavaScript `''` inside an indented Nix string.
- After parse fix, check failed again because `dm-provisioning-secret` key was declared but missing in `secrets/neurosys.yaml`.
- Both issues were fixed and `nix flake check` completed successfully.

## Skipped Tasks (Placeholders)

- Task E (private overlay): SKIPPED in this repo by scope rule. No changes made under private overlay paths.
- Task G (post-deploy SSH validation): SKIPPED in this plan execution; requires live host access after deploy.
