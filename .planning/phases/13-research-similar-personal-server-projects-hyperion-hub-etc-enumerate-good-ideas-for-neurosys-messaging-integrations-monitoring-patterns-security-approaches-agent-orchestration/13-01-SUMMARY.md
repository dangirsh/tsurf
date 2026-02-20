# Plan 13-01 Summary: Research Findings Presentation + User Cherry-Pick

## What Was Done
Presented 11 curated ideas from Phase 13 ecosystem research across 6 categories to the user for cherry-picking. Each idea was discussed case-by-case with effort/value ratings, NixOS implementation details, and recommendations.

## Decisions

### Adopted (5)

| # | Idea | Rationale | Captured As |
|---|------|-----------|-------------|
| 1 | ntfy Push Notifications | Foundational notification layer. Android push for urgent, email for non-urgent. | Phase 14 |
| 2 | Prometheus + node_exporter + Grafana | Persistent metrics history, Tailscale-only dashboards. Battle-tested NixOS modules. | Phase 14 |
| 4 | Claude Code Agent Teams | Native multi-agent, just env var. No external deps. | Quick task |
| 6 | CrowdSec (community sharing) | Collaborative threat intel for public-facing services (claw-swap). Share back approved. | Phase 15 |
| + | Tailnet Key Authority (TKA) | Self-custody Tailscale signing keys. Prevents Tailscale from adding rogue nodes. | Quick task |

### Evaluated (1)

| # | Idea | Rationale | Captured As |
|---|------|-----------|-------------|
| 3 | MCP-NixOS Server | Tool-call-only MCP (not injected into every prompt). Test locally, remove if context-polluting. | Quick task (.mcp.json) |

### Deferred (4)

| # | Idea | Revisit Condition |
|---|------|-------------------|
| 5 | Uptime Kuma | If Grafana proves insufficient for simple "is it running?" status |
| 8 | Caddy Reverse Proxy | When services need DNS-based routing (currently all Tailscale IP:port) |
| 9 | Authelia SSO | When services are internet-facing (Tailscale provides implicit auth) |
| 11 | Loki + Alloy | When specific log search needs arise beyond journalctl |

### Rejected (2)

| # | Idea | Rationale |
|---|------|-----------|
| 7 | endlessh-go SSH Tarpit | Minimal value with Tailscale-primary SSH access |
| 10 | Headscale | TKA covers key sovereignty concern without operational complexity of self-hosted coordination |

## Open Questions — Answers

| Q | Question | Answer |
|---|----------|--------|
| Q1 | Notification channel preference? | Email for non-urgent, Android push for urgent. Telegram acceptable if native push is hard. |
| Q2 | Grafana access? | Tailscale only |
| Q3 | CrowdSec collaborative model? | Approved — share back to community. Public-facing services (claw-swap) justify it. |
| Q4 | MCP-NixOS scope? | Local .mcp.json only (not global-agent-conf). Evaluate first — concern about context pollution. |
| Q5 | Bundling into existing phases? | New phases preferred. Phase 14 (monitoring+notifications), Phase 15 (CrowdSec). |

## Tailscale Trust Model Discussion

User asked about Tailscale trust model. Key findings presented:
- **With current setup**: Tailscale can add rogue nodes, MITM key exchange, modify ACLs, see metadata
- **With TKA**: Reduced to metadata-aware relay — cannot forge node identities or inject into network
- User decided to adopt TKA based on this analysis

## Architecture Patterns Preserved

For future implementers:
- **Layered monitoring**: Layer 1 (metrics) -> Layer 2 (alerting+ntfy) -> Layer 3 (logs) — add incrementally
- **Notification hierarchy**: CRITICAL (phone push), WARNING (notification), INFO (badge only)
- **vars.nix centralized config**: single file for all ports/paths/hostnames (consider for Phase 14)

## Pitfalls Preserved

- Over-engineering monitoring: more monitoring services than app services
- Notification fatigue: start with critical alerts only (disk >90%, service down >5min, backup failure)
- Agent orchestration complexity creep: Agent Teams first, custom tooling only if insufficient
- Promtail is EOL March 2026: use Alloy or Fluent Bit for any new log collection

## New Phases Created

- **Phase 14: Monitoring + Notifications** — Prometheus + node_exporter + Grafana + ntfy
- **Phase 15: CrowdSec Intrusion Prevention** — collaborative threat intelligence with community sharing

## Quick Tasks Created

- Agent Teams env var (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=true` in agent-spawn)
- MCP-NixOS evaluate (add to `.mcp.json`, test, remove if noisy)
- Tailnet Key Authority (`tailscale lock init` + sign nodes)

## Self-Check: PASSED

- [x] All 11 ideas have user-confirmed dispositions
- [x] Approved ideas appear in ROADMAP.md as new phases (14, 15) or quick tasks
- [x] Deferred ideas documented with revisit conditions
- [x] Open questions answered
- [x] STATE.md updated with decisions and phase completion
- [x] No NixOS configuration files modified (planning phase only)
