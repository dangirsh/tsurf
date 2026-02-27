---
phase: 35-unified-messaging-bridge-signal-whatsapp-telegram-ai
plan: 02
subsystem: infra
tags: [nixos, matrix, conduit, mautrix-whatsapp, mautrix-signal, impermanence]

requires:
  - phase: 35-unified-messaging-bridge-signal-whatsapp-telegram-ai
    provides: Conduit + mautrix-telegram baseline and Matrix secret scaffolding
provides:
  - WhatsApp and Signal bridges configured in Matrix module
  - Signal libsignal JIT compatibility override
  - Persistent bridge state across reboots
affects: [35-unified-messaging-bridge-signal-whatsapp-telegram-ai]

tech-stack:
  added: []
  patterns:
    - serviceDependencies on conduit for bridge startup ordering
    - sqlite URI string form for mautrix bridge appservice databases

key-files:
  created:
    - .planning/phases/35-unified-messaging-bridge-signal-whatsapp-telegram-ai/35-02-SUMMARY.md
  modified:
    - modules/matrix.nix
    - modules/impermanence.nix
    - .planning/STATE.md

key-decisions:
  - "MTX-03: set MemoryDenyWriteExecute=false for mautrix-signal due to libsignal JIT"
  - "MTX-04: accept unavoidable bridge plaintext boundary for E2E interoperability"
  - "MTX-05: accept WhatsApp account ban/disconnect risk with backup/relink mitigation"

patterns-established:
  - "Matrix bridge pattern: localhost appservice endpoints + conduit dependency + sqlite DB per bridge"

duration: 38min
completed: 2026-02-27
---

# Phase 35 Plan 02: WhatsApp + Signal Bridge Wiring Summary

Added declarative `mautrix-whatsapp` and `mautrix-signal` services to the existing Matrix hub, validated by full flake checks across both host configurations.

## Performance
- **Duration:** 38 min
- **Started:** 2026-02-27T14:03:00Z
- **Completed:** 2026-02-27T14:41:27Z
- **Tasks:** 4 completed (35-02-A through 35-02-D)
- **Files modified:** 4

## Accomplishments
- Added `services.mautrix-whatsapp` in `modules/matrix.nix` with localhost appservice endpoint (`29318`), conduit dependency, and Matrix permission mapping.
- Added `services.mautrix-signal` in `modules/matrix.nix` with localhost appservice endpoint (`29328`), conduit dependency, and Matrix permission mapping.
- Added `systemd.services.mautrix-signal.serviceConfig.MemoryDenyWriteExecute = false` to satisfy libsignal JIT requirements.
- Added MTX-03/MTX-04/MTX-05 decision annotations in the matrix module header.
- Added impermanence persistence entries for `/var/lib/mautrix-whatsapp` and `/var/lib/mautrix-signal`.
- Ran `nix flake check` successfully (neurosys + ovh) and wrote `.claude/.test-status` with pass gate status.

## Task Commits
1. **Tasks 35-02-A to 35-02-D: bridge implementation + validation** - `cd9d36c` (feat)
2. **Task 35-02 metadata: summary + state update** - pending (this docs commit)

## Files Created/Modified
- `modules/matrix.nix` - Added WhatsApp and Signal bridges, MTX-03/04/05 annotations, and signal JIT systemd override.
- `modules/impermanence.nix` - Persisted WhatsApp and Signal bridge state directories.
- `.planning/phases/35-unified-messaging-bridge-signal-whatsapp-telegram-ai/35-02-SUMMARY.md` - Plan execution summary.
- `.planning/STATE.md` - Updated current focus and recorded 35-02 decisions.

## Decisions Made
- Used sqlite database URI string form for both new bridge configs to match the existing `mautrix-telegram` module style and avoid module schema mismatch risk.
- Kept `serviceDependencies = [ "conduit.service" ]` for both bridges, consistent with existing matrix bridge startup ordering.
- Applied `MemoryDenyWriteExecute = false` only to `mautrix-signal` service scope, minimizing hardening relaxation blast radius.

## Deviations from Plan
None - plan executed as specified.

## Issues Encountered
- `nix flake check` produced pre-existing home-manager deprecation warnings unrelated to this plan; checks still passed.

## Next Phase Readiness
Code changes for 35-02 are complete. Checkpoint 35-02-E remains pending human deploy + manual account linking.

---
*Phase: 35-unified-messaging-bridge-signal-whatsapp-telegram-ai*
*Completed: 2026-02-27*
