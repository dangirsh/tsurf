---
phase: 63
plan: 63-02
subsystem: neurosys-mcp
tags: [mcp, google-oauth, google-calendar, nix, fastmcp]
requires: [63-01, google_auth.get_access_token]
provides: [calendar-mcp-tools, calendar-registration, package-metadata-update]
key-files:
  - src/neurosys-mcp/calendar_tools.py
  - src/neurosys-mcp/server.py
  - src/neurosys-mcp/pyproject.toml
  - packages/neurosys-mcp.nix
  - .test-status
  - .planning/STATE.md
key-decisions: [CAL-01, CAL-02, CAL-03]
duration: "~28m"
completed: "2026-03-02"
---

Added six Google Calendar MCP tools to `neurosys-mcp` using the existing Phase 63-01 OAuth/token infrastructure, then validated the package with full Nix checks.

## Performance

- Duration: ~28 minutes
- Tasks completed: 5/5 planned tasks (63-02-A through 63-02-E)
- Files touched: 5 implementation files + `.test-status`

## Accomplishments

- Added `src/neurosys-mcp/calendar_tools.py` with six registered async tools:
  - `calendar_list`
  - `calendar_search`
  - `calendar_free_busy`
  - `calendar_create`
  - `calendar_update`
  - `calendar_delete`
- Implemented shared Calendar request helper (`_cal_request`) with:
  - OAuth configuration gate via `google_auth._google_configured()`
  - token retrieval via `google_auth.get_access_token()`
  - consistent auth failure response: `{"ok": false, "error": "google_auth_required"}`
  - HTTP status 401/403 mapped to `google_auth_required`
- Wired Calendar tools into MCP startup by importing `calendar_tools` and calling `register(mcp)`.
- Updated package metadata:
  - `src/neurosys-mcp/pyproject.toml` now includes `calendar_tools` in `py-modules`, version `0.3.0`, and Calendar in description.
  - `packages/neurosys-mcp.nix` now includes `calendar_tools` in `pythonImportsCheck`, version `0.3.0`, and Calendar in description.
- Validation passed:
  - AST parse checks for all `src/neurosys-mcp/*.py`
  - `nix build .#neurosys-mcp`
  - `nix flake check`
  - `.test-status` updated to `pass|0|<epoch>`

## Task Commits

- Task 63-02-A: `5684e56` — add `calendar_tools.py` with six Calendar MCP tools
- Task 63-02-B: `a75928c` — register Calendar tools in `server.py` and update instructions
- Task 63-02-C: `036effb` — update `pyproject.toml` modules/version/description for Calendar
- Task 63-02-D: `e81e0d3` — update `packages/neurosys-mcp.nix` imports/version/description
- Task 63-02-E: `a8708d9` — run validation (`nix build`, `nix flake check`) and update `.test-status`

## Files Created/Modified

- Created: `src/neurosys-mcp/calendar_tools.py`
- Modified: `src/neurosys-mcp/server.py`
- Modified: `src/neurosys-mcp/pyproject.toml`
- Modified: `packages/neurosys-mcp.nix`
- Modified: `.test-status`
- Modified: `.planning/STATE.md` (this completion update)

## Decisions Made

- Reused the Gmail request architecture (httpx + bearer token from `google_auth`) for Calendar API consistency.
- Kept scope to the primary calendar only to match the plan and current personal-use requirements.
- Named module `calendar_tools.py` to avoid Python stdlib `calendar` shadowing.

## Deviations from Plan

- Repository state deviation: the referenced `.planning/phases/.../63-02-PLAN.md` file was not present in this branch, so execution followed the provided Executor Task specification directly.
- No Rule 1/2/3/4 code deviations were required during implementation.

## Issues Encountered

- `nix flake check` emitted pre-existing evaluation warnings (Home Manager option renames and `runCommandNoCC` rename warnings); checks still passed and no Calendar-related failures occurred.

## Next Phase Readiness

- Calendar and Gmail tools now share the same OAuth/token path and consistent auth-gate behavior.
- Public package/build validation is green; ready for integration/merge and private overlay deployment follow-up.

## Self-Check: PASSED
