# Phase 9: Audit & Simplify - Context

**Gathered:** 2026-02-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Deep review of all committed NixOS modules (flake.nix, modules/, secrets, .sops.yaml) and all unexecuted phase plans (2, 2.1, 4, 5, 6, 7). Optimize the entire repo for simplicity, minimalism, and security — remove unnecessary complexity, tighten security defaults, simplify module structure, and streamline future plans. Also review roadmap structure (merge/reorder/drop phases). Scope limited to agent-neurosys repo only — service-specific config belongs in service repos.

</domain>

<decisions>
## Implementation Decisions

### Simplification philosophy
- Minimal config that meets all requirements — nothing extra
- Keep options/config that are referenced by future phase plans; only strip truly dead code
- Service-specific details (e.g., Caddy TLS config) belong in service repos (claw-swap), not here
- Audit scope is agent-neurosys base repo only

### Security stance
- Best security without interfering with use cases
- SSH moves to Tailscale-only access (implement during this audit, not deferred to deploy)
  - Contabo VNC console is the emergency fallback
  - Public ports reduced to 80/443 only (for web services like claw-swap)
- Docker container hardening: **research needed** — produce exec summary + recommendation on security/usability tradeoffs (read-only rootfs, dropped capabilities, no-new-privileges, resource limits)
- Secrets: light check only — verify secrets decrypt and are used. No key rotation policy or access scope audit
- Public services (claw-swap) must be strongly isolated from rest of VPS (Docker network isolation is the baseline)

### Plan revision scope
- Review ALL unexecuted phase goals and success criteria for bloat/clarity (Phases 2, 2.1, 4, 5, 6, 7)
- Don't draft plan outlines — that's what /gsd:plan-phase does. Just tighten goals
- Re-evaluate Phase 2.1 TODOs (from Phase 8 neurosys review) with fresh eyes — some may be unnecessary complexity
- Review roadmap structure — consider whether phases should be merged, reordered, or dropped
- Contabo-specific assumptions in Phase 2 plans: defer verification to deploy time

### Audit deliverables
- Apply code changes directly with atomic commits (no findings report)
- Apply roadmap/plan changes directly (no approval gate)
- Git commits are sufficient documentation — no separate summary document
- `nix flake check` must pass after any implementation changes

### Claude's Discretion
- Whether to merge small modules (<20 lines) into parent concern files
- Whether to normalize extraConfig/freeform strings to structured NixOS options (case-by-case)
- Whether the parts cross-flake pattern (curried modules, sops.templates) earns its complexity or should be simplified

</decisions>

<specifics>
## Specific Ideas

- User wants public services strongly isolated from VPS internals — Docker network separation is minimum, but research whether runtime hardening (read-only rootfs, capabilities, etc.) is worth the tradeoff
- SSH-to-Tailscale-only is a firm decision — implement the firewall change in this audit phase

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 09-audit-simplify-implementation-review-plan-optimization*
*Context gathered: 2026-02-15*
