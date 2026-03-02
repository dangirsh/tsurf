---
phase: 63
plan: 63-01
subsystem: neurosys-mcp
tags: [mcp, oauth2, gmail, nix, fastmcp]
requires: [phase-59-mcp-snapshot, fastmcp-2.12.4]
provides: [google-oauth-flow, gmail-mcp-tools, neurosys-mcp-package]
key-files:
  - src/neurosys-mcp/server.py
  - src/neurosys-mcp/auth.py
  - src/neurosys-mcp/google_auth.py
  - src/neurosys-mcp/gmail.py
  - src/neurosys-mcp/pyproject.toml
  - packages/neurosys-mcp.nix
  - flake.nix
  - .planning/phases/63-google-oauth-gmail-calendar-mcp-tools/63-DEPLOY.md
key-decisions: [MCP-63-01, MCP-63-02, MCP-63-03, MCP-63-04, MCP-63-05, MCP-63-06]
duration: "~55m"
completed: "2026-03-02"
---

Restored the public `neurosys-mcp` server stack and added production-ready Google OAuth + Gmail MCP tooling with Nix package/flake integration and full repo checks passing.

## Performance

- Duration: ~55 minutes
- Tasks completed: 9/9 planned tasks (A-H + deployment doc)
- Files touched: 10

## Accomplishments

- Restored `auth.py` from Phase 59 for MCP OAuth provider support.
- Added `google_auth.py` with:
  - env-driven config (`GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, redirect URI fallback)
  - auth URL generation (`/google/auth`)
  - callback code exchange (`/google/callback`)
  - token persistence at `/var/lib/neurosys-mcp/google-tokens.json`
  - auto-refresh with `google-auth` and persisted refreshed tokens
- Added `gmail.py` with five registered async tools:
  - `gmail_read`, `gmail_search`, `gmail_draft`, `gmail_send`, `gmail_archive`
- Enforced Gmail auth behavior: tools return `{"ok": false, "error": "google_auth_required"}` when Google OAuth is not configured or access credentials are unavailable.
- Restored and updated `server.py`:
  - HA + Matrix + Logseq tools retained
  - Gmail tools registered
  - Google OAuth routes mounted via Starlette only when configured
  - fallback to standard `mcp.run(streamable-http)` when not configured
- Restored/updated packaging:
  - `src/neurosys-mcp/pyproject.toml` module list + deps
  - `packages/neurosys-mcp.nix` with `google-auth` + import checks
  - `flake.nix` exposing `packages.x86_64-linux.neurosys-mcp`
- Added deployment runbook `.planning/phases/63-google-oauth-gmail-calendar-mcp-tools/63-DEPLOY.md` including reuse of existing Google OAuth credentials.
- Validation complete:
  - `nix build .#neurosys-mcp` passes
  - `nix flake check` passes (`nixosConfigurations.neurosys` and `nixosConfigurations.ovh` evaluated)
  - Python AST syntax checks pass for all `src/neurosys-mcp/*.py`

## Task Commits

- Task 63-01-A: `7a2ff9e` — restore oauth provider auth module
- Task 63-01-B: `35b9277` — add google oauth infrastructure module
- Task 63-01-C: `2cca548` — add gmail mcp tools module
- Task 63-01-D: `d115af1` — restore mcp server with google oauth routes
- Task 63-01-E: `977aa27` — restore pyproject with google auth modules
- Task 63-01-F: `fc642c1` — restore nix package for neurosys mcp gmail
- Task 63-01-G: `b0d3b6e` — expose package in flake and fix deps
- Task 63-01-G2: `2fe29c4` — add google oauth deployment runbook
- Task 63-01-H: `38f2ac4` — run flake checks and record pass status

## Files Created/Modified

- Created: `src/neurosys-mcp/auth.py`
- Created: `src/neurosys-mcp/google_auth.py`
- Created: `src/neurosys-mcp/gmail.py`
- Created: `src/neurosys-mcp/server.py`
- Created: `src/neurosys-mcp/pyproject.toml`
- Created: `packages/neurosys-mcp.nix`
- Modified: `flake.nix`
- Created: `.planning/phases/63-google-oauth-gmail-calendar-mcp-tools/63-DEPLOY.md`
- Modified: `.test-status`
- Modified: `.planning/STATE.md`

## Decisions Made

- Used `google-auth` + `httpx` for OAuth/token lifecycle and Gmail API calls.
- Stored Google OAuth tokens in `/var/lib/neurosys-mcp/google-tokens.json` to survive restarts.
- Mounted Google callback endpoints directly in the MCP server process to support one-time interactive authorization.
- Implemented Gmail tools with a single shared auth/request helper to enforce consistent auth error handling.
- Exposed `neurosys-mcp` as a first-class flake package again.

## Deviations from Plan

- [Rule 3 - Blocking] `nix build .#neurosys-mcp` failed because `google.auth.transport.requests` imports `requests` which was not in runtime dependencies.
- Fix applied: added `requests` to `src/neurosys-mcp/pyproject.toml` and `python3Packages.requests` to `packages/neurosys-mcp.nix`.
- No architectural deviations requiring Rule 4 approval.

## Issues Encountered

- Initial package build failure due to missing transitive runtime dependency (`requests`) for Google refresh transport.
- Non-blocking evaluation warnings in existing Home Manager options during `nix flake check` (pre-existing, unchanged by this plan).

## Next Phase Readiness

- Ready for private overlay secret wiring and deployment.
- Runbook in place for sops secret injection and one-time `/google/auth` completion.
- Public repo is ready for merge once branch review is complete.

## Self-Check: PASSED
