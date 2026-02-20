# Phase 18: VPS Consolidation - Context

**Gathered:** 2026-02-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Merge two VPSes (acfs dev + agent-neurosys prod) into a single agent-neurosys VPS. Decommission acfs after 1-week parallel run. Design (not build) the neurosys-ctl management interface. The consolidated VPS serves as: development environment, personal services (Parts), production services (claw-swap), monitoring, backups, and agent infrastructure.

</domain>

<decisions>
## Implementation Decisions

### Migration triage
- **6 repos to keep**: parts, parts-awig, agent-neurosys, agent-base, worldcoin-ai, global-agent-conf — all clean, re-clone from GitHub
- **Drop everything else**: all other project dirs (~27 repos), AgentBox, codex-monitor-daemon, agent-mail, GitHub Actions runner, PostgreSQL 18 instance
- **Secrets**: migrate any acfs-only secrets into sops-nix. No database state to preserve
- **Non-project state**: researcher should enumerate non-repo state on acfs (~/bin scripts, cron jobs, systemd user services, /etc customizations) for triage
- **No external traffic on acfs**: dev-only, accessed via SSH/Tailscale. No DNS records to migrate
- **Decommission**: keep acfs alive 1 week after consolidation as fallback, then kill

### Dev+prod cohabitation
- **Production gets resource priority**: claw-swap and Parts containers get guaranteed CPU/memory reservations via cgroup slices. Agent sandboxes are capped to remaining resources
- **Agent access to prod services**: agents need to develop against prod repos effectively while sandboxed — researcher should investigate best approaches for sandbox-to-production-service access patterns (e.g., test endpoints, Docker network bridging, port forwarding)
- **Deploy during agent work**: prefer seamless approach — deploy should not disrupt running mosh+zmx sessions or active agent sandboxes. Researcher should investigate NixOS switch behavior with running bubblewrap sandboxes and Docker containers

### Self-deploy safety
- **Local deploys on VPS**: run nixos-rebuild directly on the VPS for speed. No remote deploy from laptop as primary path
- **Auto-rollback on connectivity loss**: if SSH/Tailscale/networking breaks after switch, auto-detect and rollback to previous generation. Researcher should investigate NixOS rollback mechanisms (systemd watchdog, network health checks, boot-based rollback)
- **Never need Contabo web console**: the rollback mechanism must be robust enough that manual console access is never required
- **Pre-switch validation**: deploy script always runs `nix flake check` before switching
- **Agent-triggered deploys**: agents can request a deploy, but it requires human approval (via ntfy) before switching. Build can be pre-staged without approval
- **Rollback policy**: auto-rollback ONLY if remote access is broken. For other service failures (claw-swap won't start, etc.), alert via ntfy and wait for human decision

### neurosys-ctl design (design only, build is follow-up phase)
- **Name**: `neurosys-ctl`
- **Interface**: CLI on the VPS with built-in `help` subcommand
- **Capability model — tiered**:
  - **Tier 1 (auto-approve)**: read-only operations — query Prometheus metrics, read logs, check service status, list snapshots
  - **Tier 2 (auto-approve)**: safe writes — restart own containers, trigger backups, send notifications
  - **Tier 3 (approval required for agents)**: dangerous writes — deploy, modify NixOS config, delete data, restart system services
- **Caller-aware**: humans get full access without approval. Agents need ntfy approval for Tier 3 operations. Design of caller detection needs user approval during planning
- **Approval flow**: ntfy action buttons (Approve/Deny). Timeout = deny (fail-safe)
- **Audit logging**: all operations logged to systemd journal with `neurosys-ctl` identifier
- **Discoverability**: `neurosys-ctl help` and `neurosys-ctl <cmd> --help` — standard CLI patterns

### Claude's Discretion
- Sandbox blast radius policy (current bubblewrap scope is the baseline — Claude can refine)
- neurosys-ctl implementation language/approach (shell script vs Nix package)
- NixOS auto-rollback mechanism selection (systemd watchdog vs custom health check vs boot-based)
- Docker network topology for agent-to-prod-service access

</decisions>

<specifics>
## Specific Ideas

- "I never want to have to resort to the Contabo web console (it's dogshit)" — rollback must be bulletproof
- "Ideally I want dev agents to be able to develop those repos effectively, while still being sandboxed" — the sandbox model must not cripple developer agent workflows
- Using mosh + zmx — deploy must not break these sessions
- neurosys-ctl named explicitly (not acfs-ctl or generic)
- neurosys-ctl is design-only for Phase 18 — implementation is a follow-up phase, but Phase 18 must not paint into a corner

</specifics>

<deferred>
## Deferred Ideas

- neurosys-ctl implementation (follow-up phase after Phase 18 design)
- MCP server wrapper for neurosys-ctl (agents could use MCP instead of CLI — evaluate after CLI exists)
- Exportable schema for agent consumption (`neurosys-ctl schema`) — evaluate if built-in help is insufficient

</deferred>

---

*Phase: 18-vps-consolidation-merge-acfs-dev-environment-into-agent-neurosys*
*Context gathered: 2026-02-20*
