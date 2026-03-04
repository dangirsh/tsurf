---
phase: 58
plan: 58-01
subsystem: agent-canvas
tags: [dashboard, canvas, vega-lite, sse, nixos]
requires: [dashboard.nix, networking.nix, config-checks.nix]
provides: [agent-canvas-service, panel-rest-api, panel-sse-stream, grid-layout-ui]
affects: [modules/canvas.nix, modules/networking.nix, hosts/services/default.nix, tests/eval/config-checks.nix, .test-status, .planning/STATE.md]
tech-stack: [nixos-module, python-stdlib-http.server, vega-lite, gridstack, marked]
key-files:
  - modules/canvas.nix
  - modules/networking.nix
  - hosts/services/default.nix
  - tests/eval/config-checks.nix
  - .test-status
  - .planning/STATE.md
key-decisions: [CANVAS-01, CANVAS-02, CANVAS-03]
duration: "~62m"
completed: "2026-03-04"
---

Implemented a new NixOS-native Agent Canvas service that lets agents push Vega-Lite and markdown panels over REST and update browsers in real time via SSE.

## Performance

- Duration: ~62 minutes
- Tasks completed: 7/7 planned execution tasks (A through G)
- Files touched: 4 implementation files + `.test-status` + planning docs

## Accomplishments

- Created `modules/canvas.nix` with a stdlib-only Python server packaged via `pkgs.writers.writePython3Bin "agent-canvas"`.
- Implemented REST API endpoints:
  - `POST /api/panels`
  - `GET /api/panels`
  - `GET /api/panels/{id}`
  - `PATCH /api/panels/{id}`
  - `DELETE /api/panels/{id}`
  - `POST /api/panels/{id}/data`
- Implemented SSE endpoint `GET /api/events` with create/update/delete events and heartbeat handling.
- Added atomic persistence to `/var/lib/agent-canvas/panels.json` (temp write + `os.replace`) with lock-based concurrency control.
- Added embedded client HTML with CDN `vega@6`, `vega-lite@6`, `vega-embed@7`, `gridstack@12`, and `marked@15`.
- Implemented 12-column drag/resize grid layout and debounced (300ms) PATCH layout persistence.
- Added module options (`services.agentCanvas.enable`, `listenPort` default `8083`) and hardened systemd service:
  - `DynamicUser = true`
  - `StateDirectory = "agent-canvas"`
  - strict sandboxing and capability restrictions aligned with dashboard pattern.
- Added dashboard entry `services.dashboard.entries.canvas`.
- Added internal firewall safeguard entry `internalOnlyPorts."8083" = "agent-canvas"`.
- Imported and enabled module in `hosts/services/default.nix`.
- Extended eval checks:
  - `expected-services-neurosys` includes `agent-canvas`
  - new `canvas-enabled` check asserts enabled + port `8083`
- Validation:
  - `nix flake check` passed
  - required gate command passed and wrote `.test-status`
  - smoke test: one `curl -X POST` created a Vega-Lite panel and API/UI assets served correctly.

## Task Commits

- Task A: `7bac471` — add agent canvas REST/SSE backend
- Task B: `585fe59` — add canvas HTML client with live sync
- Task C: `5cc8453` — wire module options, dashboard entry, hardened service
- Task D: `fbc331a` — reserve internal-only port 8083
- Task E: `3712e80` — import and enable canvas module in host services
- Task F: `81c8eb7` — add eval checks for canvas service
- Task G: `97d02ad` — run flake checks and record `.test-status`

## Files Created/Modified

- Created: `modules/canvas.nix`
- Modified: `modules/networking.nix`
- Modified: `hosts/services/default.nix`
- Modified: `tests/eval/config-checks.nix`
- Modified: `.test-status`
- Created: `.planning/phases/58-research-agent-driven-dynamic-dashboard-for-neurosys/58-01-SUMMARY.md`
- Modified: `.planning/STATE.md`

## Decisions Made

- CANVAS-01: Keep the server stdlib-only (`http.server`, no framework) for minimal attack surface and reliable Nix packaging.
- CANVAS-02: Use `DynamicUser` with `StateDirectory` to combine runtime isolation with persistent panel data.
- CANVAS-03: Keep auth out of the app layer and rely on internal-only network exposure/Tailscale trust boundary.

## Deviations from Plan

- Repository-state deviation: `.planning/phases/58-research-agent-driven-dynamic-dashboard-for-neurosys/58-01-PLAN.md` was not present in this branch snapshot, so execution followed the provided Executor Task specification directly.
- No Rule 1/2/3/4 implementation deviations were required.

## Issues Encountered

- `nix flake check` emitted pre-existing warnings (Home Manager renamed options, `runCommandNoCC` rename notices). Checks still passed; no canvas-specific failures.

## Next Phase Readiness

- Canvas service is fully integrated and guarded by eval checks.
- API + SSE + persistence are in place for agent-driven panel updates.
- Ready for deployment and optional follow-on phases (auth proxying, panel templates, multi-canvas support).
