# Phase 61: Nix-Derived Dynamic Dashboard - Context

**Gathered:** 2026-03-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace the manually-maintained homepage-dashboard with a dashboard generated from NixOS module expressions. The dashboard renders a collapsible tree view of services with status indicators and links, derived from the actual Nix source. Annotations in modules provide display metadata. The dashboard always reflects the deployed config — zero drift between Nix source and what the UI shows.

</domain>

<decisions>
## Implementation Decisions

### Data extraction approach
- **Two-layer architecture:** Static structure from Nix eval at build time + live status overlay at runtime
- Build-time: Nix expression evaluates the config and emits a JSON manifest as a NixOS activation artifact (e.g., `/run/current-system/dashboard.json`). Always matches the running generation.
- Runtime: Minimal status API sidecar queries systemd unit status as baseline + optional HTTP health endpoints (from annotations) for richer status per service.
- **Dashboard architecture:** Static HTML generated at build time from the manifest. A lightweight status API sidecar serves live status JSON. Dashboard polls status via JS fetch.

### Visual layout & hierarchy
- Tree structure mirrors the `modules/` directory — each `.nix` file becomes a branch, sub-services nested underneath
- Collapsible tree (expand/collapse module branches), default all-expanded
- Status indicated by colored dots (green/yellow/red) next to each service name — minimal, dense, scannable
- Services with a web UI URL annotation get a clickable link; others are display-only with status dot

### Annotation schema
- **Medium richness:** name, port, URL, one-line description, icon/emoji, and optional health check endpoint
- Annotations live in a custom NixOS option namespace (e.g., `services.*.dashboard` or similar), type-checked by the module system, co-located with service definitions
- **Graceful degradation:** Unannotated modules still appear in the tree using the module filename as display name, no URL, no health check. Annotations are progressive enhancement, not required.
- **Escape hatches:** The annotation schema supports "external" entries — things defined in Nix but not backed by a NixOS module (Docker containers, external service URLs). Keeps everything in one view.
- Works for both public repo modules and private overlay modules — the built JSON includes both. Dashboard shows the full deployed picture.

### Relationship to current homepage
- **Full replacement** of homepage-dashboard. Remove it entirely once the Nix-derived dashboard is validated.
- Same port (8082), same Tailscale-only access pattern via `trustedInterfaces`. Drop-in replacement, no networking changes.
- Phase scope: build + local validation (`nix flake check`). Deployment to live server follows normal deploy flow.

### Claude's Discretion
- Exact NixOS option type definitions and module structure for the annotation schema
- Status API implementation language/framework (Python stdlib, Go, etc.)
- Static HTML generation approach (Nix builder, template engine, etc.)
- Polling interval for live status
- Color scheme and exact tree styling
- How to handle the transition from homepage-dashboard (ordering of removal)

</decisions>

<specifics>
## Specific Ideas

- "A tree view with status indicators + links to service pages, derived from the actual NixOS module structure rather than a manually maintained homepage config"
- Dashboard should be generated from the Nix expressions — the visual representation is always in sync with the source
- OK to require additional annotations in the Nix modules, as long as they're lightweight and co-located
- Structure should mirror the module file organization, not an arbitrary grouping

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 61-nix-derived-dynamic-dashboard*
*Context gathered: 2026-03-02*
