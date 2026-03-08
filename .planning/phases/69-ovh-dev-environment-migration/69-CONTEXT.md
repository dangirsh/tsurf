# Phase 69: OVH Dev Environment Migration - Context

**Gathered:** 2026-03-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Migrate daily development workflow from acfs (local machine) to OVH VPS (neurosys-dev). OVH becomes the primary dev host — all project repos, agent tooling, sandbox environment, and coding workflow run there. Contabo (neurosys) keeps running services (HA, claw-swap, Matrix, Spacebot, Conway, MCP, Prometheus). acfs goes unused after migration.

This phase does NOT move services between hosts, change hostnames, or redeploy OVH from scratch. OVH already has NixOS gen-3 with impermanence + Tailscale — this deploys updated config on top.

</domain>

<decisions>
## Implementation Decisions

### Service allocation
- **Two-host split**: Contabo = services host, OVH = dev host. Services stay on Contabo.
- **No agentd on OVH** — remove agentd from OVH config entirely. Conway/autonomous agents stay on Contabo.
- **Dev agents in sandboxes on OVH** — agent-compute with bwrap sandbox for interactive Claude/Codex sessions.
- **Secret-proxy for all agents on OVH** — wire Phase 66 generic secret-proxy module so dev agents use placeholder keys + proxy, not direct API key injection.
- **MCP server stays on Contabo** — Claude Android / remote tool access connects to Contabo.
- **Single dashboard on Contabo covers both hosts** — no separate homepage instance on OVH.
- **Syncthing on OVH** — joins existing cluster for Logseq vault and shared folders.

### Data migration strategy
- **Git clone on activation** — populate repos list in private overlay's repos.nix for OVH. Fresh clone from GitHub on deploy.
- **All repos from acfs except archive folder** — comprehensive repo list mirroring current /data/projects (minus archive).
- **agentic-dev-base symlinks only** — no dotfile migration. User state comes from Nix config declaratively.
- **Maximally declarative** — track all repos, configs, and tool setup in Nix. Minimize manual post-deploy steps.

### Agent & dev workflow
- **Access: SSH via Tailscale + Claude Code remote, interchangeably** — both `ssh root@neurosys-dev` and Claude Code SSH remote should work.
- **Keep current hostnames** — Contabo stays `neurosys`, OVH stays `neurosys-dev`. No renaming.
- **agent-compute same as acfs** — bwrap sandbox, coding CLIs (claude, codex), API key injection via secret-proxy.

### Cutover & validation
- **Deploy on top of existing** — no nixos-anywhere wipe. OVH gen-3 install is the base.
- **Acceptance test: sandboxed Claude Code session works on OVH** — SSH in, start sandboxed Claude, confirm it can operate.
- **No DNS/Tailscale changes** — hostnames unchanged.

### Claude's Discretion
- OVH private overlay config structure (which modules to import, how to wire secret-proxy)
- Exact repo list derivation (enumerate from acfs or define manually)
- Deploy sequence and intermediate validation steps
- Whether to update Contabo dashboard to show OVH agent status

</decisions>

<specifics>
## Specific Ideas

- "Mission control repo + all projects hosted there" — OVH is the home base for all development.
- "This present acfs server is no longer in use" — clear success signal: acfs becomes idle.
- "rm agentd" — explicit removal of agentd from OVH. Keep agent-compute for interactive sandbox sessions.
- "Maximally track all repos/configs in nix as declaratively as possible" — strong preference for Nix-managed state over manual setup.

</specifics>

<deferred>
## Deferred Ideas

- Converting acfs into another NixOS/neurosys node — user explicitly said out of scope for this phase.
- Service migration from Contabo to OVH — separate future phase if ever needed.
- Hostname swap (OVH becoming primary `neurosys`) — not needed now, could revisit later.

</deferred>

---

*Phase: 69-ovh-dev-environment-migration*
*Context gathered: 2026-03-08*
