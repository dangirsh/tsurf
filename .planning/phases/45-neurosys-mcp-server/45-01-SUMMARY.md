---
phase: 45-neurosys-mcp-server
plan: 01
subsystem: infra
tags: [mcp, home-assistant, nixos, fastmcp, python]
requires: []
provides:
  - FastMCP Streamable HTTP Home Assistant server source
  - Nix package derivation for neurosys-mcp with pinned PyPI hashes
  - internalOnlyPorts registration for 8400
affects: [45-02]
tech-stack:
  added: [python, fastmcp, mcp]
  patterns: [buildPythonPackage from PyPI, buildPythonApplication for local source]
key-files:
  created: [src/neurosys-mcp/server.py, src/neurosys-mcp/pyproject.toml, packages/neurosys-mcp.nix]
  modified: [flake.nix, modules/networking.nix]
key-decisions:
  - "Pinned fastmcp to 2.12.4 to avoid py-key-value-aio dependency chain"
  - "Packaged mcp and fastmcp from PyPI via buildPythonPackage"
  - "MCP server runs Streamable HTTP transport with main entrypoint server:main"
completed: 2026-03-01
---

# Phase 45 Plan 01 Summary

Implemented and packaged a custom `neurosys-mcp` FastMCP server exposing Home Assistant REST control tools over Streamable HTTP, then integrated the package into flake outputs and reserved internal port 8400.

## Accomplishments
- Added `src/neurosys-mcp/server.py` with 5 async tools:
  - `ha_get_states`
  - `ha_get_state`
  - `ha_call_service`
  - `ha_list_services`
  - `ha_search_entities`
- Added `src/neurosys-mcp/pyproject.toml` with script entrypoint:
  - `neurosys-mcp = "server:main"`
- Added `packages/neurosys-mcp.nix`:
  - Custom `mcp` and `fastmcp` package derivations from PyPI with pinned hashes
  - `buildPythonApplication` for local source package
- Exposed package in `flake.nix` at `packages.x86_64-linux.neurosys-mcp`
- Registered `"8400" = "neurosys-mcp"` under `internalOnlyPorts` in `modules/networking.nix`

## Verification
- `python3 -c "import ast; ast.parse(open('src/neurosys-mcp/server.py').read())"`
- `nix build .#neurosys-mcp`
- `nix flake check` (passes including `nixosConfigurations.neurosys` and `nixosConfigurations.ovh`)

## Issues Encountered
- `mcp` and `fastmcp` both required `uv-dynamic-versioning` in build-system; added explicitly.

## Next Phase Readiness
Phase 45-01 goals are complete. Plan 45-02 can add deployment wiring/services in private overlay.
