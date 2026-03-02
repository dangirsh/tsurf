---
phase: 59-logseq-pkm-agent-suite
plan: 01
subsystem: infra
tags: [python, mcp, logseq, orgparse, nix]

requires:
  - phase: 45-neurosys-mcp-server
    provides: FastMCP server infrastructure on port 8400

provides:
  - Three read-only Logseq vault MCP tools (logseq_get_todos, logseq_search_pages, logseq_get_page)
  - orgparse dependency in neurosys-mcp Nix package

affects: [59-02]

tech-stack:
  added: [orgparse]
  patterns: [register(mcp_instance) pattern for tool modules]

key-files:
  created: [src/neurosys-mcp/logseq.py]
  modified: [src/neurosys-mcp/server.py, src/neurosys-mcp/pyproject.toml, packages/neurosys-mcp.nix]

key-decisions:
  - "LOGSEQ-01: orgparse for org-mode parsing (in nixpkgs, handles TODO state/tags/properties)"
  - "LOGSEQ-02: Read-only tools only, write operations deferred"
  - "LOGSEQ-03: Vault path via LOGSEQ_VAULT_PATH env var"

duration: 2min
completed: 2026-03-02
---

# Phase 59 Plan 01: Logseq MCP Tools — Python Source + Nix Packaging Summary

Implemented a new `logseq.py` tool module with three read-only vault query tools, registered it into the FastMCP server, and updated Python/Nix packaging so `orgparse`-backed Logseq parsing builds and evaluates cleanly.

## Performance

- **Duration:** ~2 minutes
- **Started:** 2026-03-02T12:34:05+01:00
- **Completed:** 2026-03-02T12:35:52+01:00
- **Tasks:** 5
- **Files modified:** 7

## Accomplishments

- Added `logseq_get_todos`, `logseq_search_pages`, and `logseq_get_page` as async FastMCP tools via `register(mcp_instance)`.
- Added graceful degradation for unset/missing `LOGSEQ_VAULT_PATH`, missing `pages/`, invalid inputs, and parse/read errors.
- Registered Logseq tools in `server.py` and updated runtime tool guidance in MCP instructions.
- Added `orgparse` to both Python package dependencies and Nix derivation dependencies.
- Updated package import checks (`server`, `logseq`) and package metadata to include Logseq.
- Verified Python syntax and ran full `nix flake check` (including `nixosConfigurations.neurosys` and `nixosConfigurations.ovh`) successfully.
- Recorded `.test-status` as passing.

## Task Commits

- `dd44b58` — `feat(59-01): add read-only logseq tool module`
- `7b16862` — `feat(59-01): register logseq tools in mcp server`
- `e54bd78` — `chore(59-01): add logseq module packaging deps`
- `3b7adda` — `chore(59-01): include orgparse in nix package`
- `53b43d2` — `chore(59-01): record plan test status`

## Files Created/Modified

- `src/neurosys-mcp/logseq.py` (created): Logseq vault query tools + helper/parsing utilities.
- `src/neurosys-mcp/server.py` (modified): Logseq registration + updated MCP instructions.
- `src/neurosys-mcp/pyproject.toml` (modified): `orgparse` dependency + `logseq` py-module.
- `packages/neurosys-mcp.nix` (modified): Nix dependency, import checks, description update.
- `.test-status` (modified): pass marker after check suite.
- `.planning/phases/59-logseq-pkm-agent-suite/59-01-SUMMARY.md` (created): execution report.
- `.planning/STATE.md` (modified): phase position/decisions update.

## Decisions Made

- LOGSEQ-01: orgparse selected for org-mode parsing because it is available in nixpkgs and exposes TODO/tags/properties/timestamps/tree traversal.
- LOGSEQ-02: Scope constrained to read-only tools in Plan 59-01; write operations deferred to later phase(s).
- LOGSEQ-03: Vault path is configuration-driven through `LOGSEQ_VAULT_PATH` and validated at runtime by each tool.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Non-blocking `nix flake check` warnings were emitted for pre-existing Home Manager option renames and `runCommandNoCC` rename notices.

## Next Phase Readiness

- Plan 59-01 complete. Ready for Plan 59-02 (private overlay + logseq-agent-suite repo).
