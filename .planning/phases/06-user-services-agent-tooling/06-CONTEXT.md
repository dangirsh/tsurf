# Phase 6: User Services + Agent Tooling - Context

**Gathered:** 2026-02-16
**Status:** Ready for planning

<domain>
## Phase Boundary

The AI agent development infrastructure is operational with file sync, code indexing, and config repos in place. Syncthing syncs files across devices, CASS indexes code for search, infrastructure repos are cloned, and agent config (Claude Code + Codex) is symlinked from a shared repo.

</domain>

<decisions>
## Implementation Decisions

### Syncthing configuration
- Single "Sync" folder shared across devices (not multiple named folders)
- Send-receive direction — full bidirectional sync (acfs is an active participant, not just an archive)
- Staggered versioning enabled — keep deleted/modified file versions with time-based decay
- Web UI bound to Tailscale IP only — not accessible on public interface or localhost
- 4 devices declared in Nix: MacBook-Pro.local, DC-1, Pixel 10 Pro, MacBook-Pro-von-Theda.local (from Phase 8 decisions)
- Receive-only mode NOT used — user explicitly chose send-receive

### CASS indexer
- Install from pre-built GitHub binary release, wrapped in a Nix derivation
- Index `/data/projects/` only — focused on code repos the agents work with
- Run as periodic systemd timer (not continuous daemon) — every 30 minutes
- User-level systemd service (`systemctl --user`)

### Repo management
- Clone 3 repos: `parts`, `claw-swap`, `global-agent-conf`
- All repos live under `/data/projects/<repo-name>`
- NixOS activation script handles cloning — checks if repo exists, clones if missing (self-healing)
- Clone-only — never pull/update existing repos (safest, no surprise force-pulls on dirty working trees)
- Clone via HTTPS using GH_TOKEN (already set up in Phase 5), not SSH

### Agent config layout
- `global-agent-conf` is a shared Claude Code config repo (CLAUDE.md, skills, hooks, keybindings)
- `~/.claude` is a whole-directory symlink → `/data/projects/global-agent-conf` (not individual file symlinks)
- `~/.codex` also symlinked from the same repo (Codex config lives alongside Claude config)
- No machine-specific overrides needed on acfs — shared config works as-is

### Claude's Discretion
- Syncthing staggered versioning decay parameters (hourly/daily/weekly retention)
- Syncthing rescan interval
- CASS binary fetch mechanism (fetchurl vs fetchzip in Nix derivation)
- Activation script error handling (what happens if clone fails — log and continue vs fail activation)
- Exact symlink creation method (home-manager vs activation script)

</decisions>

<specifics>
## Specific Ideas

- Syncthing uses single "Sync" folder — matches current device setup (confirmed in Phase 8 Q1)
- 4 specific device IDs need to be declared fresh in Nix config (not ported from old neurosys)
- GH_TOKEN from sops-nix secrets (Phase 5) is used for HTTPS cloning — no need for SSH key auth for repo cloning
- CASS is a binary from GitHub — research phase needs to verify availability and determine exact repo/release URL

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 06-user-services-agent-tooling*
*Context gathered: 2026-02-16*
