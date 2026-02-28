# Phase 40: agentd Integration — Supervised Agent Lifecycle - Context

**Gathered:** 2026-02-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace one-shot `agent-spawn` (bash script) with agentd — a supervised, reconciliation-loop daemon from the stereOS ecosystem. Adds restart policy, hash-based config watching, HTTP API for live agent status, and declarative jcard.toml agent config. Bubblewrap sandbox is preserved. Phase goal is agent lifecycle management only — agent isolation hardening (Phase 41), VM-based sandboxing (Phase 42), and session telemetry (Phase 43) are separate phases.

**Design philosophy:** Maximize stereOS ecosystem leverage. neurosys is agent-first — humans talk to agents via APIs and dashboards, not terminals. Session multiplexers are infrastructure, not interfaces.

</domain>

<decisions>
## Implementation Decisions

### agent-spawn transition
- **Hard cutover** — `agent-spawn` removed entirely when agentd is deployed. No fallback.
- agentd + bubblewrap replaces every invocation of agent-spawn across both hosts.
- **zmx vs. tmux:** User strongly prefers zmx; tmux is overly complex for an agent-first system where humans never attach to terminals. agentd uses tmux internally for session tracking — research phase must investigate whether zmx supports the required subcommands (`has-session`, `send-keys`, `new-session`) as a drop-in replacement inside agentd. If compatible, use zmx. If not, accept tmux as agentd's invisible internal detail (it owns its own socket, never exposed to users).
- **Both hosts:** agentd runs on Contabo (for autonomous agents — Conway Automaton, future background agents) AND OVH (for coding agents — interactive Claude/Codex sessions). Not OVH-only.
- **Multi-agent model:** Multiple agentd instances — one per agent, each with its own NixOS systemd service and jcard.toml. No single agentd managing multiple agents.

### jcard.toml config ownership
- **NixOS-generated** (Claude's Discretion) — agent configs declared in Nix (`services.agentd.agents`), rendered to `/etc/agentd/<name>/jcard.toml` at activation. Declarative, in git, no hand-edited TOML files on the server.
- **Named persistent configs** — known recurring agents are declared by name in Nix: e.g. `neurosys-dev`, `conway-automaton`, `claw-swap-dev`. Named agents have a defined purpose. New agents can always be added.
- **Startup prompt is optional** — both models supported:
  - Ad-hoc coding agents: no prompt, interactive mode (user or orchestrating agent directs after launch)
  - Autonomous agents: prompt field set (genesis directive, e.g. Conway Automaton's seed hypothesis)
- **Restart policy by agent class:**
  - Ad-hoc coding agents: `restart = "no"` — session ends when agent exits; human decides whether to relaunch
  - Autonomous/long-running agents (Conway Automaton, etc.): `restart = "always"` — runs until explicitly stopped
- **Config-change restart:** Only autonomous agents trigger a restart when their jcard.toml changes (reconciliation loop). Ad-hoc agents are not auto-restarted on config change — too disruptive to an active session.

### bubblewrap integration
- **Mandatory for all agents** — agentd's `custom` harness always wraps the agent binary in the existing bwrap invocation. No agent runs outside the sandbox.
- **Secrets hidden from sandbox** — agents receive secrets as env vars only (e.g. `ANTHROPIC_BASE_URL`, `OPENAI_API_KEY`). `/run/secrets/` is never bind-mounted into the sandbox. Same policy as current agent-spawn.
- **Harness model:** agentd's `custom` harness invokes: `bwrap <existing-args> -- claude` (or codex). The bwrap wrapper is the top-level process agentd tracks.

### Observability surface
- **Homepage widget** — agents section on the homepage dashboard showing all running agents from both hosts in a single unified view.
- **Detail level:** name + status (running/stopped) + restart count + uptime. Standard agentd `/v1/agents` fields.
- **Single view across hosts** — Contabo agents and OVH agents in one flat section, not split by host.
- Prometheus scraping, ntfy crash alerts, and Conway dashboard integration are out of scope for this phase.

### Claude's Discretion
- NixOS option schema design for `services.agentd.agents` — researcher should propose a schema that covers harness, prompt (optional), workdir, restart policy, and maps cleanly to jcard.toml output
- Whether agentd's HTTP socket should be per-instance or shared (likely per-instance given one agentd per agent)
- Homepage widget implementation approach (static config polling vs. live proxy)
- How to wire sops-nix secrets as env vars into agentd's environment (likely via `EnvironmentFile` pointing to a sops template)

</decisions>

<specifics>
## Specific Ideas

- User directive: **maximize stereOS ecosystem leverage** for agent management, dashboards, and security throughout this phase and related phases
- zmx is preferred over tmux wherever humans might see or interact with a session — tmux is acceptable only as agentd's invisible internal session tracker
- The philosophy: humans talk to agents via APIs and dashboards. Terminal multiplexers are plumbing, not interfaces.
- Named agents like `neurosys-dev`, `conway-automaton`, `claw-swap-dev` should feel like declaring services in NixOS — same idiom as `services.postgresql.enable = true`

</specifics>

<deferred>
## Deferred Ideas

- Prometheus scraping of agentd `/v1/agents` — not selected for this phase; could be added in Phase 41 or as a quick task
- ntfy alert on autonomous agent crash-loop — out of scope for Phase 40; natural follow-on
- Conway dashboard integration with agentd API — Phase 39 uses SQLite state; agentd API integration is a future enhancement
- Agent-facing agentd API access (can agents query `/v1/agents` from inside the sandbox?) — interesting but out of scope

</deferred>

---

*Phase: 40-agentd-integration-supervised-agent-lifecycle*
*Context gathered: 2026-02-28*
