---
phase: 34-voice-mcp-claude-android-app-tools-via-home-assistant
plan: "01"
subsystem: infra
tags: [nixos, home-assistant, tailscale, mcp, voice]
key-decisions:
  - "HA-04: trusted_proxies for Tailscale Serve reverse proxy"
  - "HA-05: Declarative systemd oneshot for tailscale serve --bg"
duration: 15min
completed: 2026-02-27
---

# Phase 34 Plan 01: Enable HA MCP Server + Tailscale Serve HTTPS Proxy Summary

**Validated and checkpointed Home Assistant MCP + Tailscale Serve configuration, with code-level changes already present in `main` and flake checks passing.**

## Performance

- **Duration:** 15 min
- **Tasks:** 4 completed
- **Files modified:** 2

## Accomplishments

- Confirmed `modules/home-assistant.nix` already includes:
  - `extraComponents = [ ... "mcp_server" ]`
  - `http.use_x_forwarded_for = true`
  - `http.trusted_proxies = [ "127.0.0.1" ]`
  - `systemd.services.tailscale-serve-ha` oneshot with `after/wants tailscaled.service` and `wantedBy multi-user.target`
- Ran full `nix flake check` (neurosys + ovh paths) successfully; only pre-existing evaluation warnings remained.
- Wrote `.claude/.test-status` gate as required by execution protocol.
- Advanced execution to checkpoint boundary (Task 34-01-E) for required human deployment/verification steps.

## Task Commits

1. **Task A+B: HA MCP config + tailscale-serve-ha service** - `cf65e1c` (feat, pre-existing on `main`)
2. **Plan metadata** - `ecd881c` (docs)

## Files Created/Modified

- `modules/home-assistant.nix` - verified existing mcp_server, trusted proxies, and tailscale-serve-ha service
- `.planning/STATE.md` - updated current position and Phase 34 decisions/checkpoint status
- `.planning/phases/34-voice-mcp-claude-android-app-tools-via-home-assistant/34-01-SUMMARY.md` - added execution summary

## Decisions Made

- HA-04: trusted_proxies = ["127.0.0.1"] for Tailscale Serve localhost proxy
- HA-05: systemd oneshot wrapping `tailscale serve --bg` for declarative, reboot-safe config

## Deviations from Plan

- Existing mainline already contained Task 34-01-A and 34-01-B implementation (`cf65e1c`), so this execution validated and checkpointed rather than introducing new source deltas.

## Issues Encountered

- No blocking issues. `nix flake check` emitted existing Home Manager deprecation warnings unrelated to this phase.

## Self-Check

PASSED

## Next Phase Readiness

- NixOS config complete and validated; deploy + HA UI setup + Claude connector remain human-action checkpoints (Tasks 34-01-E through 34-01-G).
- Ready for user-triggered deploy verification checkpoint.

---
*Phase: 34-voice-mcp-claude-android-app-tools-via-home-assistant*
*Completed: 2026-02-27*
