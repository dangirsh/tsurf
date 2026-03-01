# Phase 53: Conway Dashboard Auth + Prompt Editor - Context

**Gathered:** 2026-03-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Two features for the existing Conway automaton dashboard: (1) Token-based authentication enabling public internet access via nginx HTTPS reverse proxy at `conway.dangirsh.org`. (2) A UI to edit the genesis prompt, view prompt history, and control agent lifecycle (start/stop/restart) — without requiring a NixOS rebuild. Changes span `conway-dashboard` repo (server.py + dashboard.html) and `private-neurosys` overlay (automaton-dashboard.nix, automaton.nix, nginx.nix).

</domain>

<decisions>
## Implementation Decisions

### Auth flow
- Token passed via **query parameter** (e.g., `conway.dangirsh.org/?token=abc123`) — simplest, bookmarkable
- Token validated at **nginx level** before proxying to Python server — dashboard server stays auth-free
- **Dual access**: Tailscale = no auth (existing behavior preserved), public internet = token required. Two nginx server blocks.
- Public domain: **conway.dangirsh.org** — subdomain of existing dangirsh.org, uses same ACME/nginx infrastructure on OVH
- Token stored in sops-nix, injected into nginx config

### Prompt editing UX
- **Plain textarea** — large textarea showing current genesis prompt, edit and save
- **Simple rollback list** — show last 5-10 prompts with timestamps, click to restore a previous one
- **Save and restart are separate actions** — save updates the prompt on disk, restart is a separate button. Allows editing without disrupting a running agent.

### Agent restart behavior
- **Full lifecycle control** — start, stop, restart buttons on the dashboard
- **Confirmation dialog before restart/stop** — show agent uptime and turn count to prevent accidental disruption (e.g., "Are you sure? Agent has been running for 3h with 12 turns.")
- Restart mechanism and status feedback are Claude's discretion

### Public access scope
- **Full access with token** — token grants same capabilities as Tailscale (view status, edit prompt, start/stop/restart agent)
- **All endpoints require auth** on the public domain — including /api/status. Nothing leaks without the token.
- **Same ACME setup** as dangirsh.org — add `conway.dangirsh.org` as another nginx virtualHost with Let's Encrypt

### Claude's Discretion
- Prompt storage mechanism (flat file vs SQLite — pick based on existing automaton architecture)
- Restart mechanism (systemctl subprocess vs signal file vs other)
- Restart status feedback UX (spinner + poll vs simple toast)
- Rate limiting on public endpoint (nginx limit_req vs none)

</decisions>

<specifics>
## Specific Ideas

- Dashboard currently polls `/api/status` every 5 seconds — auth token should be included in these polls on the public domain
- The automaton's genesis prompt is currently hardcoded in Nix config (requires NixOS rebuild to change) — this phase makes it runtime-editable
- Existing dashboard is a single self-contained HTML file — keep this pattern (no build step, no npm)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 53-conway-dashboard-auth-prompt-editor*
*Context gathered: 2026-03-01*
