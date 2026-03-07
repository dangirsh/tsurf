---
phase: 66-secret-placeholder-proxy-module-generic-nixos-secret-injection-for-sandboxed-agents
plan: "01"
subsystem: api
tags: [rust, axum, reqwest, nix, secret-proxy]

requires:
  - phase: "22-01"
    provides: original secret proxy pattern and BASE_URL architecture
provides:
  - Rust `secret-proxy` binary with host allowlist enforcement and header injection
  - Nix package definition for `packages.x86_64-linux.secret-proxy`
  - Flake package export for direct `nix build .#secret-proxy`
affects: [nixos module wiring, sandboxed agents, secret management]

tech-stack:
  added: [axum, reqwest, tokio, serde, toml]
  patterns: [plain-http localhost ingress, strict host allowlist, startup secret file loading]

key-files:
  created:
    - packages/secret-proxy/Cargo.toml
    - packages/secret-proxy/Cargo.lock
    - packages/secret-proxy/src/config.rs
    - packages/secret-proxy/src/main.rs
    - packages/secret-proxy/src/proxy.rs
    - packages/secret-proxy.nix
  modified:
    - flake.nix

key-decisions:
  - "Forward upstream is fixed to allowed_domains[0] for the matched secret."
  - "Secret files are read once at startup; proxy fails fast on unreadable/empty values."
  - "Reqwest native TLS path retained; Nix package adds pkg-config + openssl inputs."

patterns-established:
  - "Host header must match configured allowlist before any forwarding."
  - "Request secret headers are overwritten at proxy boundary, never trusted from sandboxed clients."

duration: 53 min
completed: 2026-03-07
---

# Phase 66 Plan 01: Rust secret-proxy Binary Summary

**Shipped a Rust secret-proxy service that enforces per-secret host allowlists, injects real secrets from disk-backed files, and forwards requests over HTTPS with streamed responses.**

## Performance

- **Duration:** 53 min
- **Started:** 2026-03-07T19:43:00Z
- **Completed:** 2026-03-07T20:36:00Z
- **Tasks:** 7
- **Files modified:** 7

## Accomplishments
- Added a new Rust crate at `packages/secret-proxy` with TOML config parsing and `--config <path>` CLI support.
- Implemented request handling that extracts/normalizes `Host`, enforces `allowed_domains`, denies mismatches with HTTP 403, and logs allow/deny decisions.
- Implemented per-secret header injection by replacing configured header values with cached secret file contents loaded at startup.
- Implemented HTTPS forwarding via `reqwest` and streaming upstream response pass-through via Axum body streams.
- Added `packages/secret-proxy.nix` and exported `secret-proxy` in flake packages for `nix build` usage.
- Verified with `cargo build`, `nix eval`, `nix build .#packages.x86_64-linux.secret-proxy`, `nix build .#secret-proxy`, and `nix flake check`.

## Task Commits

Each task was committed atomically:

1. **Tasks 66-01-A through 66-01-G (crate + Nix wiring + verification)** - `96d2dad` (feat)

## Files Created/Modified
- `packages/secret-proxy/Cargo.toml` - Rust crate metadata and dependencies.
- `packages/secret-proxy/Cargo.lock` - Locked dependency graph for reproducible Nix builds.
- `packages/secret-proxy/src/config.rs` - TOML schema for port/placeholder/secret entries.
- `packages/secret-proxy/src/main.rs` - Startup path: parse config, load secrets, build router, bind listener.
- `packages/secret-proxy/src/proxy.rs` - Core proxy logic: allowlist matching, header rewrite, HTTPS forwarding, streamed responses.
- `packages/secret-proxy.nix` - `rustPlatform.buildRustPackage` packaging for `secret-proxy`.
- `flake.nix` - Exposed `packages.${system}.secret-proxy` output.

## Decisions Made
- Destination control is proxy-owned: requests always forward to `https://{allowed_domains[0]}{path_and_query}` for matched secret.
- Request forwarding drops security-sensitive hop headers and user-supplied secret headers before injecting the real secret.
- Domain matching uses normalized lowercase host names with port stripped from `Host`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added OpenSSL/pkg-config inputs for Nix Rust build**
- **Found during:** Task 66-01-E (Nix package build)
- **Issue:** `nix build` failed with `openssl-sys` because `pkg-config` and OpenSSL headers were unavailable in build inputs.
- **Fix:** Added `nativeBuildInputs = [ pkgs.pkg-config ];` and `buildInputs = [ pkgs.openssl ];` in `packages/secret-proxy.nix`.
- **Files modified:** `packages/secret-proxy.nix`
- **Verification:** `nix build .#packages.x86_64-linux.secret-proxy` succeeded after the change.
- **Committed in:** `96d2dad` (Task commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** No scope creep; blocker fix was required to make the planned Nix package buildable.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
Plan 66-01 is complete and verified. Ready for `66-02-PLAN.md`.

---
*Phase: 66-secret-placeholder-proxy-module-generic-nixos-secret-injection-for-sandboxed-agents*
*Completed: 2026-03-07*
