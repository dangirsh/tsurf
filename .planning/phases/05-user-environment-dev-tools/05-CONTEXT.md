# Phase 5: User Environment + Dev Tools - Context

**Gathered:** 2026-02-16
**Status:** Ready for planning

<domain>
## Phase Boundary

The server provides a complete, agent-optimized compute environment. SSH in, launch AI coding agents (Claude Code, Codex), and manage them via tmux. This is NOT a human development environment — 100% of code interactions are agent-mediated. The human's role is launching agents, monitoring via btop, and managing mosh+tmux sessions.

**Key reframe from original roadmap:** The success criteria in ROADMAP.md assume a human developer (zsh, starship, neovim, etc.). These are superseded by the decisions below. The roadmap criteria should be updated during planning to reflect agent-first design.

**VPS target:** Contabo Cloud VPS 60 — 18 vCPU (AMD EPYC), 96GB RAM, 350GB NVMe.

</domain>

<decisions>
## Implementation Decisions

### Agent isolation via cgroups v2
- Each agent session runs in a systemd cgroup slice for resource isolation
- **CPU: CPUWeight (dynamic fair-share)** — inherently proportional. 1 agent = 100%, 2 = 50/50, 10 = 10% each. No static allocation needed.
- **Memory: skip limits for now** — 96GB is ample. Add MemoryHigh soft limits later only if OOM becomes an issue.
- No memory limits, no microvm.nix, no per-agent user accounts
- Single user (`dangirsh`) for all agent sessions

### Shell: bash, not zsh
- Default shell is bash — agents don't care about shell features
- No oh-my-zsh, no starship, no syntax-highlighting, no autosuggestions
- No prompt customization at all
- direnv + nix-direnv is the ONLY shell integration (for auto-loading project devShells)

### No human-comfort tools
- No neovim, no starship, no zsh plugins, no atuin
- No prompt theme
- If the human needs an editor in a pinch, `nano` is fine (already in NixOS base)

### Generic compute — project deps from devShells
- The server provides base utilities only: git, gh, curl, wget, jq, yq, ripgrep, fd, tmux, mosh
- Language runtimes, LSPs, formatters etc. come from each project's `flake.nix` / devShell
- Node.js is the ONE runtime installed globally (required by Codex CLI and MCP servers)
- direnv + nix-direnv auto-loads project devShells when agents cd into project dirs

### Agent CLIs: Nix-managed via llm-agents.nix
- Add `numtide/llm-agents.nix` as a flake input
- Claude Code and Codex CLI installed declaratively from this overlay
- Nix-managed means reproducible, pinnable, and part of the system config

### MCP servers: per-project only
- No global/system-wide MCP server configuration
- Each project repo defines its own MCP servers in `.claude/settings.json` or similar

### Git identity: Dan Girshovich
- `git config user.name "Dan Girshovich"` / `user.email` set via home-manager or global gitconfig
- All agents commit as Dan — Co-Authored-By trailers distinguish which agent wrote the code
- No separate agent git identity

### GitHub auth: PAT via sops-nix
- GitHub Personal Access Token stored as a sops-nix secret
- `gh auth login --with-token` uses the decrypted token
- No SSH key auth for GitHub — token-based only

### Launcher script: `agent-spawn`
- Basic launcher: creates named tmux session + cgroup slice, cd's to project dir, launches specified agent CLI
- Usage: `agent-spawn <name> <project-dir> [claude|codex]`
- No worktree management, no monitoring registry, no cleanup on exit

### Mosh: primary entrypoint
- mosh-server enabled in NixOS config
- Human always connects via mosh for roaming and persistence
- Regular SSH still available as fallback

### Tmux: minimal config
- Mouse mode ON (for easy pane switching when human is monitoring)
- Otherwise stock tmux defaults — no custom prefix, no status bar theming
- Agent sessions are separate tmux sessions (not panes in one session)

### API keys: sops-nix
- ANTHROPIC_API_KEY, OPENAI_API_KEY, and any other agent API keys stored as sops-nix secrets
- Exposed as environment variables to agent sessions (via the launcher script or shell profile)
- No `.env` files — sops-nix is the single source of truth

### Agent session logs: deferred to Phase 6
- No session indexing or log aggregation in Phase 5
- Claude Code and Codex maintain their own session logs
- Phase 6 will evaluate CASS and alternatives for searchable session history

### Coordination tooling: lean Phase 5
- No Agent Mail, no NTM dashboard, no new coordination infrastructure
- Existing tools (beads, guard.sh) continue to work
- Full coordination tooling evaluated in a future phase when multi-agent same-repo work becomes a bottleneck

</decisions>

<specifics>
## Specific Ideas

- "The 'agent' in agent-neurosys is the key. Humans should never need to use tools directly ever again."
- "100% of interactions are agent-mediated, so 100% of tool choice boils down to 'does this help the agent be more effective?'"
- "The most I'll do is launch btop and a bunch of mosh + tmux sessions to control a team of agents"
- Jeffrey Emanuel's ACFS flywheel researched — relevant patterns (Agent Mail, CASS, NTM) noted but deferred. The key insight is agent coordination infrastructure, not human developer ergonomics.
- numtide/llm-agents.nix provides Nix-packaged agent CLIs with daily auto-updates — use as flake input
- Michael Stapelberg's microvm.nix approach noted for future agent isolation if needed

</specifics>

<deferred>
## Deferred Ideas

- **Session indexing** (CASS or alternatives) — Phase 6. Evaluate options during Phase 6 research.
- **Agent Mail** (inter-agent messaging + file reservation) — future phase, when multi-agent same-repo coordination becomes a bottleneck
- **NTM dashboard** (tmux orchestration with agent health metrics) — future phase
- **Dynamic memory limits** — add MemoryHigh soft limits if agents cause OOM issues
- **microvm.nix** — if untrusted agents are ever needed, or for stronger isolation
- **`agent-list` monitoring command** — could complement `agent-spawn` in a future phase

</deferred>

---

*Phase: 05-user-environment-dev-tools*
*Context gathered: 2026-02-16*
