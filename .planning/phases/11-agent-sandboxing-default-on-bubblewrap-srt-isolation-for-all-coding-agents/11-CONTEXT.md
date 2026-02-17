# Phase 11: Agent Sandboxing - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Default-on bubblewrap sandbox for every coding agent spawned on acfs. Agents get filesystem isolation (secrets hidden, sibling projects read-only), rootless Podman for Docker workflows, unrestricted network (including Tailscale), PID limits, and audit logging. `--no-sandbox` is an explicit opt-out. The sandbox prevents prompt-injected agents from reading secrets, escalating via Docker, or moving laterally — while keeping normal development workflows fully functional.

</domain>

<decisions>
## Implementation Decisions

### Filesystem Policy
- `/data/projects/` visible read-only; agent's specific project directory is read-write
- `/nix/store` fully visible read-only (no security concern — content-addressed, no secrets)
- Nix daemon socket bind-mounted — agents can `nix build`, `nix develop`, `nix-shell`
- Per-agent isolated tmpfs at `/tmp` (ephemeral, dies with agent)
- `/run/secrets/` completely invisible (sops-nix secrets hidden)
- `~/.ssh/` completely invisible (no SSH agent forwarding either)
- No Docker socket inside sandbox (Docker socket = root-equivalent = sandbox escape)
- No Tailscale CLI/interface (network access via regular routing, not tailscale tooling)
- Curated home directory bind-mounts: fixed list of common dotfiles (e.g., `~/.gitconfig`, `~/.npmrc`) — read-only. Not configurable per-project.
- Minimal `/dev`: only `/dev/null`, `/dev/zero`, `/dev/urandom`, `/dev/tty`, `/dev/pts`
- `/etc` handling: Claude's discretion — selective bind-mount of resolv.conf, passwd, group, ssl certs, nix configs
- Shared PID namespace (agent can see host processes, useful for debugging)
- Run as host user (dangirsh) — correct file ownership on project dir writes
- Multiple agents on same project: shared workspace view (they coordinate via git/worktrees)
- Fully ephemeral: when agent exits, all non-project-dir state is gone
- All permissions fixed at spawn time — no runtime escalation

### Docker Access via Rootless Podman
- No raw Docker socket in sandbox (prevents sandbox escape via privileged containers / host mounts)
- Rootless Podman as the container runtime for agents
- Daemonless architecture — no per-agent daemon overhead (unlike rootless Docker)
- Agents get full `podman build` / `podman run` / `podman-compose` workflow
- User namespace isolation: even container escape = unprivileged user
- Containers launched via Podman inherit host network (including Tailscale for testing)
- Containers cannot access `/run/secrets/` or `~/.ssh/` (rootless user namespace + filesystem permissions)
- NixOS module: `virtualisation.podman = { enable = true; dockerCompat = true; }`

### Network Policy
- Unrestricted internet access (no domain allowlisting, no proxy filtering)
- Tailscale network accessible directly from agent process
- No network namespace isolation (`--unshare-net` NOT used)
- Rationale: agents need npm, pip, cargo, nix, GitHub, Tailscale URLs, documentation — a static allowlist would constantly break in YOLO mode with no human to approve new domains
- Filesystem isolation (hidden secrets/SSH keys) is the primary exfiltration defense
- Block link-local/metadata addresses (169.254.169.254) via iptables as cheap defense

### Resource Limits
- Best-effort resource sharing — no hard reservation split between agents and production
- Core services (SSH, Tailscale, Podman) protected from starvation via systemd slice weights
- Per-agent PID limit (e.g., 4096) — prevents fork bombs
- Per-agent tmpfs size cap (e.g., 4GB) — prevents disk exhaustion
- No per-agent memory or CPU hard caps — Linux OOM killer handles runaway processes
- Existing agent-spawn cgroup slice configuration from Phase 5 provides the foundation

### Agent UX & Opt-out
- Sandbox ON by default: `agent-spawn <name> <dir>` is sandboxed
- `--no-sandbox` for explicit opt-out (no reason required)
- Sandbox-aware error messages: when sandbox blocks access, agent sees helpful error (e.g., "Blocked by sandbox: ~/.ssh/ is not accessible. Use --no-sandbox if needed.")
- `agent-spawn --show-policy` for introspecting what the sandbox allows (visible paths, network, limits, Podman status)
- Audit log: records all sandbox policy denials (blocked paths, blocked access attempts). Stored per-agent session.

### Claude's Discretion
- Exact `/etc` bind-mount set (resolv.conf, passwd, group, ssl certs, nix-related configs)
- Exact curated home dotfile list for bind-mounting
- Secrets access mechanism (completely hidden vs opt-in env var injection at spawn time)
- Audit log format and storage location
- Sandbox-aware error message implementation (custom wrapper vs LD_PRELOAD vs bubblewrap config)
- PID limit and tmpfs size exact values (4096 PIDs and 4GB tmpfs are starting points)
- OPA authz plugin as optional defense-in-depth layer on rootless Podman (research showed it's fragile as sole defense but useful as additional layer)

</decisions>

<specifics>
## Specific Ideas

- Agent's zmx sessions (not tmux) — zmx is the terminal multiplexer in use
- Worktree management is handled by repo-level agent configs (CLAUDE.md), NOT by the sandbox
- The `tmp/` in project root convention from CLAUDE.md is being removed since the sandbox provides proper /tmp isolation
- Research copy-on-write overlayfs for per-agent project isolation — user is interested in this as a future enhancement. Find resources from people who have tried overlayfs-based agent workspace isolation.
- Claude Code's sandbox-runtime (proxy-based domain filtering) is the industry reference implementation for agent network isolation — relevant if network filtering is added later
- Vercel Sandbox's dynamic policy model (open for dep install, locked for code execution) is the most elegant production approach — relevant for future network filtering
- CVE-2025-55284 demonstrated DNS-based exfiltration from Claude Code sandbox — relevant for future hardening

</specifics>

<deferred>
## Deferred Ideas

- **Network monitoring/filtering** — Start with no restrictions, revisit later. Consider: proxy-based domain allowlisting (Claude Code model), monitor-then-alert baselines (StepSecurity model), or dynamic policies (Vercel model)
- **Copy-on-write overlay workspaces** — Per-agent overlayfs snapshots of project directory for full isolation between concurrent agents. Research resources and feasibility.
- **DNS exfiltration prevention** — Block DNS tools from auto-approve, restrict to trusted resolvers
- **Docker socket proxy with OPA** — If rootless Podman proves insufficient, add OPA authz plugin for granular container creation filtering (block --privileged, dangerous mounts). Note: Docker authz had CVE-2024-41110 (CVSS 10.0, unpatched 5 years) — not trustworthy as sole defense.
- **gVisor/Sysbox integration** — If Contabo adds KVM support or Sysbox gets NixOS packaging, these provide stronger isolation than rootless Podman

</deferred>

---

*Phase: 11-agent-sandboxing-default-on-bubblewrap-srt-isolation-for-all-coding-agents*
*Context gathered: 2026-02-17*
