# Phase 61: Nix-Derived Dynamic Dashboard - Context

**Gathered:** 2026-03-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace the manually-maintained homepage-dashboard with a dashboard generated from NixOS module expressions. The dashboard renders a collapsible tree view of services with status indicators and links, derived from the actual Nix source. Custom extractors walk the config at eval time to produce a JSON manifest. A runtime layer overlays live systemd status. The dashboard always reflects the deployed config — zero drift between Nix source and what the UI shows.

</domain>

<decisions>
## Implementation Decisions

### Data extraction approach
- Custom extractors from scratch — no nix-topology dependency. Own Nix functions that walk `config.services.*` and custom annotations to emit a JSON manifest at build time.
- Live status overlay: systemd unit status only (active/inactive/failed). No HTTP health checks, no Prometheus coupling.
- Manifest generation approach and serving architecture: Claude's discretion (NixOS activation artifact vs. standalone derivation; static HTML + sidecar vs. single dynamic server).

### Visual layout & hierarchy
- Tree structure mirrors the `modules/` directory — one branch per `.nix` file, sub-services nested under their parent module
- Collapsible tree (expand/collapse module branches), default all-expanded
- Status indicated by colored dots (green/yellow/red) next to each service name — minimal, dense, scannable
- Clicking a service expands an inline collapsible detail section showing port, systemd unit name, status, and link to web UI if available

### Annotation schema
- Medium richness: display name, port, web UI URL, one-line description, icon/emoji, and optional health check endpoint
- Annotation placement: Claude's discretion (custom NixOS option namespace vs. centralized manifest module vs. other approach)
- Graceful degradation: unannotated modules still appear in the tree using the module filename as display name, no URL, no health check. Annotations are progressive enhancement.
- Escape hatches: the schema supports "external" entries — things defined in Nix but not backed by a NixOS module (Docker containers, external service URLs). Everything in one dashboard view.
- Must work for both public repo modules and private overlay modules.

### Relationship to current homepage
- Replace after validation — build alongside homepage-dashboard, run both briefly to validate core parity, then remove the old one
- Core parity only — service tree with status indicators + links must match. System resource gauges and Docker-specific widgets can be dropped (Prometheus handles that).
- Same port (8082), same Tailscale-only access pattern via `trustedInterfaces`
- Phase scope includes build + deploy + validate on live server (full end-to-end)

### Existing tool research
- **nix-topology** (oddlama): 77 service extractors, extractor pattern is reusable but we're writing custom extractors instead. No dependency on nix-topology.
- **NixoScope**: Module dependency graph via `.graph` output — not directly relevant but `.graph` is interesting infrastructure.
- **No standard `meta` on NixOS options** — open PR (nixpkgs#341199) not merged. Custom option namespace or similar approach needed.
- **`nix eval` + `builtins.toJSON`**: The simplest building block — walk `config.services.*` at eval time and emit JSON.
- **Clan JSON Schema converter**: Generates option schemas, not values. Not directly applicable.
- **Thymis**: Fleet management platform, overkill for this use case.

### Claude's Discretion
- Manifest generation approach (activation artifact vs. standalone derivation)
- Serving architecture (static HTML + status API sidecar vs. single dynamic server)
- Annotation placement (custom option namespace vs. centralized module vs. other)
- Exact tree styling, color scheme, polling interval
- Implementation language for the status API (Python stdlib, Go, etc.)
- How to handle the transition period (both dashboards coexisting)

</decisions>

<specifics>
## Specific Ideas

- "A tree view with status indicators + links to service pages, derived from the actual NixOS module structure rather than a manually maintained homepage config"
- Dashboard should be generated from the Nix expressions — the visual representation is always in sync with the source
- OK to require additional annotations in the Nix modules, as long as they're lightweight and co-located
- Structure should mirror the module file organization, not an arbitrary grouping
- nix-topology's extractor pattern is a useful reference for how to conditionally read `config.services.*` attributes

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 61-nix-derived-dynamic-dashboard*
*Context gathered: 2026-03-04*
