---
phase: 35-unified-messaging-bridge-signal-whatsapp-telegram-ai
plan: 01
subsystem: infra
tags: [nixos, matrix, conduit, mautrix-telegram, sops, impermanence]
key-decisions:
  - "MTX-01: single matrix module for homeserver and bridges"
  - "MTX-02: private Tailscale-only Matrix hub with federation disabled"
duration: 65min
completed: 2026-02-27
---

# Phase 35 Plan 01: Conduit Homeserver + mautrix-telegram Summary

Shipped a declarative Matrix stack for neurosys with Conduit and mautrix-telegram, including secrets wiring, firewall policy updates, and persistence.

## Performance
- **Duration:** 65 min
- **Tasks:** 7 completed (35-01-A through 35-01-G)
- **Files modified:** 10

## Accomplishments
- Added `modules/matrix.nix` with Conduit (`services.matrix-conduit`) and mautrix-telegram (`services.mautrix-telegram`) configuration.
- Added Matrix bridge secrets to sops declarations and encrypted placeholders in `secrets/neurosys.yaml`.
- Added Matrix/bridge ports (`6167`, `29317`, `29318`, `29328`) to `internalOnlyPorts` in `modules/networking.nix`.
- Imported `./matrix.nix` in `modules/default.nix`.
- Added `/var/lib/mautrix-telegram` to impermanence persistence.
- Passed `nix flake check` across both `nixosConfigurations.neurosys` and `nixosConfigurations.ovh`.
- Wrote `.claude/.test-status` with `pass|0|<timestamp>`.

## Task Commits
1. **Tasks 35-01-A to 35-01-F: Matrix implementation + validation** - `d598be4` (feat)

## Files Created/Modified
- `modules/matrix.nix` - Conduit + mautrix-telegram service module with sops templates and MTX decisions
- `modules/default.nix` - imports matrix module
- `modules/networking.nix` - internal-only Matrix/bridge ports added
- `modules/secrets.nix` - Matrix secret declarations with explicit `sopsFile`
- `modules/impermanence.nix` - persisted `/var/lib/mautrix-telegram`
- `secrets/neurosys.yaml` - encrypted placeholders and generated matrix registration token
- `.claude/.test-status` - flake-check gate marker
- `.planning/phases/35-unified-messaging-bridge-signal-whatsapp-telegram-ai/35-01-SUMMARY.md` - this summary
- `.planning/STATE.md` - updated current phase position and new decisions

## Decisions Made
- MTX-01: Keep homeserver and bridge config in one module to reduce cross-module coupling.
- MTX-02: Disable federation and keep Matrix stack internal-only for private Tailscale usage.
- Scoped Matrix services to `neurosys` host and allowlisted `olm-3.2.16` only there to satisfy nixpkgs insecure-package gating for mautrix-telegram.

## Deviations from Plan
- `[Rule 3 - Blocking]` `sops` binary missing in base shell. Fixed by running `sops` through `nix shell nixpkgs#sops`.
- `[Rule 3 - Blocking]` Stale `.git/index.lock` blocked staging. Removed stale lock (`unlink`) after verifying no active git process.
- `[Rule 3 - Blocking]` Secret name conflict with imported `parts` module (`telegram-api-*` `sopsFile`). Fixed with `lib.mkForce` on the three Matrix secret `sopsFile` values.
- `[Rule 3 - Blocking]` `mautrix-telegram` dependency on insecure `olm-3.2.16` blocked flake evaluation. Fixed with narrow `nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ]` under `mkIf isNeurosys`.

## Issues Encountered
- Home-manager deprecation warnings were present during flake evaluation but non-blocking and unrelated to this phase.

## Self-Check
PASSED: `nix flake check` completed successfully with both `nixosConfigurations.neurosys` and `nixosConfigurations.ovh` evaluated and all checks passing.

## Next Phase Readiness
Ready for Plan 35-02 implementation after manual checkpoint actions (credentials, deploy, and Matrix appservice bootstrap).

---
*Phase: 35-unified-messaging-bridge-signal-whatsapp-telegram-ai*
*Completed: 2026-02-27*
