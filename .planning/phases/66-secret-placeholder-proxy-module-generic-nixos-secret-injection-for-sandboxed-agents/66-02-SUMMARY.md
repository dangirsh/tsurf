---
phase: 66-secret-placeholder-proxy-module-generic-nixos-secret-injection-for-sandboxed-agents
plan: "02"
subsystem: infra
tags: [nixos, systemd, secret-proxy, security, nix]

requires:
  - phase: "66-01"
    provides: Rust secret-proxy package and flake export
provides:
  - Generic `services.secretProxy.services.<name>` NixOS module interface
  - Per-service systemd units and dedicated system users for proxy isolation
  - TOML config generation via `pkgs.writeText` and eval-time duplicate-port assertion
affects: [phase-66-03, sandboxed agents, private overlay service declarations]

tech-stack:
  added: []
  patterns: [attrsOf submodule service declarations, per-service system user isolation, store-path TOML config for runtime]

key-files:
  created: []
  modified:
    - modules/secret-proxy.nix
    - modules/networking.nix

key-decisions:
  - "Use `baseUrlEnvVar` option (default `ANTHROPIC_BASE_URL`) to generate read-only `bwrapArgs` explicitly per service."
  - "Generate per-service config with `pkgs.writeText` store paths; no tmpfiles/runtime config generation needed."
  - "Remove hardcoded `9091` internalOnlyPorts mapping because secret-proxy listeners bind to 127.0.0.1 only."

patterns-established:
  - "Secret proxy services are declared declaratively via `services.secretProxy.services` and materialize as `secret-proxy-<name>` units/users."
  - "Port collision prevention is enforced at eval time via module assertions over declared service ports."

duration: 3 min
completed: 2026-03-07
---

# Phase 66 Plan 02: Generic NixOS Module for Secret Placeholder Proxy Summary

**Replaced the hardcoded Python Anthropic proxy module with a generic multi-service NixOS module that builds per-service users, units, store-path TOML configs, and read-only bwrap base URL args.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-07T19:04:38Z
- **Completed:** 2026-03-07T19:07:43Z
- **Tasks:** 4
- **Files modified:** 2

## Accomplishments
- Rewrote `modules/secret-proxy.nix` as a backend-agnostic module exposing `options.services.secretProxy.services` as an `attrsOf` submodule.
- Added per-service option schema (`port`, `placeholder`, `baseUrlEnvVar`, `secrets`, read-only `bwrapArgs`) and per-service runtime resources (`secret-proxy-<name>` service + user).
- Added TOML config generation with `pkgs.writeText` for each declared service and wired service startup to `${secretProxyPkg}/bin/secret-proxy --config <store-path>`.
- Added eval-time duplicate-port assertion for `services.secretProxy.services` declarations.
- Removed hardcoded `"9091" = "anthropic-secret-proxy"` from `modules/networking.nix` and replaced it with module-ownership comments.
- Verified `nix flake check` passes with default empty service declarations.

## Task Commits

Each task was committed atomically:

1. **Tasks 66-02-A through 66-02-D (module rewrite, networking update, verification)** - `9331ad8` (feat)

## Files Created/Modified
- `modules/secret-proxy.nix` - Generic secret proxy NixOS module with service submodule options, TOML generation, per-service unit/user creation, and duplicate-port assertions.
- `modules/networking.nix` - Removed static `9091` internal port mapping and documented secret-proxy loopback-only behavior.

## Decisions Made
- Adopted explicit `baseUrlEnvVar` service option for generating `bwrapArgs` instead of deriving provider env vars from header names.
- Kept config materialization in Nix store (`pkgs.writeText`) because generated TOML contains non-secret metadata only (paths, ports, headers).
- Scoped anti-collision checks to `services.secretProxy.services` port declarations with clear eval-time assertion messaging.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- `gsd-tools state advance-plan` / `state update-progress` failed due current STATE parser assumptions (`Cannot parse Current Plan or Total Plans in Phase` and subsequent `String.prototype.repeat ... Infinity`). State and roadmap were updated manually to keep plan metadata accurate.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
Plan 66-02 complete and verified. Ready for `66-03-PLAN.md` private overlay consumer migration and integration checks.

---
*Phase: 66-secret-placeholder-proxy-module-generic-nixos-secret-injection-for-sandboxed-agents*
*Completed: 2026-03-07*
