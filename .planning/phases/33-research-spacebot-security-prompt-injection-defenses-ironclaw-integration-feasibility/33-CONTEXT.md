# Phase 33: Research Spacebot Security + Ironclaw Integration - Context

**Gathered:** 2026-02-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Research phase covering two questions:
1. How does spacebot guard against prompt injection? (sandboxing, input validation, context isolation, published threat model)
2. Is ironclaw viable as the LLM backend/agent executor behind spacebot's UI layer? (architecture fit, effort estimate, go/no-go recommendation)

This phase produces a research document and findings. Implementation work (if any) belongs in a follow-up phase.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices deferred to Claude — user gave full discretion. Sensible defaults applied:

**Research output format:**
- Single `33-RESEARCH.md` in the phase directory (consistent with Phase 31 pattern)
- Key findings that warrant follow-up work get captured as beads
- No inline code changes during research — pure discovery

**Prompt injection research focus:**
- Cover both existing defenses AND gaps/recommendations
- Neurosys-specific threat model: spacebot is Tailscale-only (port 19898, localhost), so external network attack surface is minimal; focus on injection via the agent/LLM path and any admin interface exposure
- Document what spacebot does, what it doesn't do, and what neurosys-specific mitigations apply

**Ironclaw feasibility scope:**
- Architecture survey + go/no-go recommendation with rough effort estimate
- No prototype or proof-of-concept needed in this phase
- Key question: can ironclaw replace spacebot's LLM backend without breaking the UI/UX layer?

**Action threshold:**
- Pure discovery — findings feed into new phases, no auto-triggered implementation
- If ironclaw is feasible and desirable, a follow-up phase gets added to roadmap
- If prompt injection gaps are critical, they get triaged as beads or a new phase

</decisions>

<specifics>
## Specific Ideas

- Spacebot is deployed at `ghcr.io/spacedriveapp/spacebot:slim` on port 19898 (Tailscale-only)
- Upstream NixOS module exists at `nix/module.nix` in the spacebot repo — relevant for ironclaw wiring
- Repo cloned to `/data/projects/spacebot`
- LLM key currently injected via `sops.templates."spacebot-env"` referencing `anthropic-api-key`

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 33-research-spacebot-security-prompt-injection-defenses-ironclaw-integration-feasibility*
*Context gathered: 2026-02-26*
