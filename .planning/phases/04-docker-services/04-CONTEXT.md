# Phase 4: Docker Services — Context

**Gathered:** 2026-02-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Declare and run the claw-swap production Docker stack with security hardening. Both Ollama and grok-mcp dropped from this phase — no active consumers in v1 scope. All containers get read-only rootfs, cap-drop ALL, no-new-privileges, and resource limits.

</domain>

<decisions>
## Implementation Decisions

### claw-swap deployment pattern
- claw-swap repo exports a NixOS module via its own flake (same pattern as parts)
- Agent-neurosys imports it as a flake input
- Docker images built with Nix dockerTools (not pulled from registry) — reproducible, same as parts
- PostgreSQL stays as a Docker container (not NixOS-native) — keep current approach
- Service-specific config (containers, networks, secrets) lives in the claw-swap repo, not agent-neurosys

### Container resource limits
- Generous headroom: 512MB for lightweight containers, 2GB for Java/heavy ones (47GB RAM VPS)
- Both memory AND CPU limits set per container
- Restart policy: on-failure with max retries (prevents crash loops, stays down after repeated failures for investigation)

### Ollama
- DROPPED from Phase 4 — only known consumer (claude-memory-daemon) is out of scope for v1
- Can be added later as a simple NixOS module if a use case appears (CASS indexer in Phase 6, experiments)

### grok-mcp
- DROPPED from Phase 4 — not needed

### Claude's Discretion
- Caddy TLS/domain config ownership (claw-swap repo vs agent-neurosys)
- Exact CPU/memory values per container — start generous, document in config
- Container restart max retry count

</decisions>

<specifics>
## Specific Ideas

- Follow the parts cross-flake pattern exactly: curried module, sops.templates for env files, consumer imports nixosModules.default
- Container hardening pattern documented in 09-RESEARCH.md: `extraOptions` for read-only, cap-drop, no-new-privileges, resource limits
- Security hardening is a success criterion (SC5), not optional

</specifics>

<deferred>
## Deferred Ideas

- Ollama AI inference service — add when a consumer exists (Phase 6 CASS indexer may need it)
- grok-mcp — add back if needed in the future
- NixOS-native PostgreSQL — could simplify backups in Phase 7, but keep Docker for now

</deferred>

---

*Phase: 04-docker-services*
*Context gathered: 2026-02-16*
