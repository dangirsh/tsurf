# neurosys

## What This Is

A NixOS flake-based configuration that declaratively defines the "acfs" development server — a VPS running AI agent infrastructure, development tools, Docker services, and backup systems. The config enables provisioning an identical replacement server from a single `nixos-anywhere` command, with all services, tools, and repos ready to go.

## Core Value

One command to deploy a fully working development server with all services running, all tools installed, and all infrastructure repos cloned — no manual setup steps.

## Design Philosophy

This is a **generic infrastructure repo** for a beefy VPS that runs the user's life. It provides base system configuration + deployment — NOT project-specific details. Projects plug in via flake inputs (like parts) or are declared in later service phases.

**Use cases the infrastructure must support without interference:**
- Small projects and demos (e.g., claw-swap)
- AI agents running via parts flake
- Lots of personal data storage and sync
- Tailscale connection to home WiFi for home automation
- SSH as the primary management interface

**Security posture:** Best defaults that don't interfere with these use cases. Default-deny firewall, Tailscale for private networking, sops-nix for secrets, fail2ban for SSH.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] NixOS boots and is accessible via SSH and Tailscale
- [ ] All development tools available (Bun, Rust via rustup, Go, Python 3, Git, Zsh)
- [ ] Docker engine running with declared container services (claw-swap stack, grok-mcp)
- [ ] PostgreSQL available (via Docker, matching current setup)
- [ ] Ollama running as a system service
- [ ] Tailscale connected to tailnet
- [ ] Syncthing running for file synchronization
- [ ] Restic automated backups to Backblaze B2
- [ ] CASS indexer running as user-level systemd service
- [ ] Infrastructure repos cloned to /data/projects/ (global-agent-conf, parts, claw-swap)
- [ ] global-agent-conf symlinked to ~/.claude
- [ ] home-manager manages shell (Zsh), git, tmux, Atuin
- [ ] Secrets managed via sops-nix (SSH keys, API keys, B2 credentials, env files)
- [ ] Firewall configured (allow SSH, HTTP/S, Syncthing, Tailscale; deny all else)
- [ ] Disk layout managed by disko for nixos-anywhere compatibility

### Out of Scope

- ACFS shell framework — dropped, home-manager replaces it from scratch
- Converting Docker containers to native NixOS services — containers stay as-is
- claude-memory-daemon — not included (experiment, can add later)
- MCP Agent Mail — not included as a managed service (can add later)
- Multi-host fleet management — single-host config for now, though flake structure supports adding hosts later
- GUI/desktop environment — headless server only
- Ollama model management — models downloaded manually after deploy
- Monitoring stack (Prometheus/Grafana) — add later if needed
- vibe-kanban, finbot, dunbot, and other experimental projects — not auto-cloned

## Context

### Current Server (acfs)

- **Provider:** Contabo VPS — AMD EPYC 12-core, 47GB RAM, 484GB SSD
- **Current OS:** Ubuntu 25.10 (Questing Quokka)
- **Nix already installed:** v2.33.1 (daemon mode) — used for building the grok-mcp container
- **Hostname:** vmi2996850 (will be renamed to `acfs` in NixOS)
- **Public IP:** 212.47.65.220 (eth0)
- **Tailscale IP:** 100.103.164.24 (tailscale0)
- **Timezone:** Europe/Berlin
- **Locale:** C.UTF-8, US keyboard layout

### Running Services to Capture

**System-level:**
- Docker (containerd) — manages 5 containers
- PostgreSQL 18 (native systemd, port 5432) — unclear if actively used vs Docker postgres
- Ollama 0.15.2 (port 11434) — serves nomic-embed-text model
- Tailscale (mesh VPN)
- SSH (port 22)
- Nix daemon

**Docker containers:**
- `claw-swap-caddy` — Caddy 2.10.2 reverse proxy for claw-swap.com (public 80/443)
- `claw-swap-app` — Node.js app (port 3000 internal)
- `claw-swap-db` — PostgreSQL 16-alpine (port 15432)
- `dreamy_lehmann` — PostgreSQL 16-alpine (port 32941) — unclear purpose, investigate
- `codex-grok-mcp` — Grok MCP server built with Nix (port 9601)

**User-level systemd services:**
- Syncthing (port 8384 web UI, 22000 sync)
- CASS indexer (`cass index --watch`)
- claude-memory-daemon (port 8765, depends on Ollama) — NOT included in v1

**Docker networks:**
- bridge (default)
- claw-swap-net (custom bridge for claw-swap stack)

### Development Tools Inventory

| Tool | Current Version | NixOS Plan |
|------|----------------|------------|
| Git | 2.51.0 | nixpkgs |
| Zsh | system | nixpkgs + home-manager |
| Bun | 1.3.6 | nixpkgs or overlay |
| Node.js | via Bun | nixpkgs (separate from Bun) |
| pnpm | 10.28.0 | nixpkgs |
| Python 3 | 3.13.7 | nixpkgs |
| Rust | nightly 1.95.0 | rustup (Nix installs rustup) |
| Go | 1.24.4 | nixpkgs |
| Docker | 28.2.2 | NixOS module |
| Neovim | system | nixpkgs |
| GitHub CLI (gh) | system | nixpkgs |
| Atuin | installed | home-manager program |
| fd | system | nixpkgs |
| ripgrep | system | nixpkgs |
| jq | system | nixpkgs |
| git-lfs | system | nixpkgs |

### Agent Tooling

- **global-agent-conf** — repo at `/data/projects/global-agent-conf`, symlinked to `~/.claude`
- **Claude Code CLI** — installed at `~/.local/bin/claude` (v2.1.41)
- **Codex CLI** — config at `~/.codex/` with AGENTS.md, hooks
- **CASS** — indexer at `~/.local/bin/cass`, runs as user service

### SSH Keys

- `~/.ssh/id_ed25519` — primary key (GitHub, general use)
- `~/.ssh/id_ed25519_contabo` — provider-specific key
- `~/.ssh/authorized_keys` — 1 key (personal access)
- No `~/.ssh/config` file

### Caddy Configuration

Caddy runs inside Docker (claw-swap stack), not as a system service. Caddyfile:
```
claw-swap.com {
  encode gzip
  reverse_proxy claw-swap-app:3000
}
```
SSL handled automatically by Caddy. Data/config persisted via bind mounts from `/data/projects/claw-swap/deploy/`.

### Git Identity

- Name: Dan Girshovich
- Email: dangirsh@users.noreply.github.com
- Credential helper: `gh auth git-credential` (GitHub CLI)
- LFS: enabled

### Cron (to evaluate)

- `ubs --update` (Ultimate Bug Scanner) — probably drop on NixOS

### What's NOT Being Migrated

- Snap/snapd (nothing meaningful installed)
- ACFS shell framework (replacing with home-manager)
- 1700+ pip-installed Python packages (reinstall as needed per-project)
- claude-memory-daemon (experiment)
- MCP Agent Mail (can add later)
- Various ad-hoc node/bun/python processes

## Constraints

- **Provider:** Contabo VPS — same provider, new instance. Must work with their UEFI/BIOS boot and network setup.
- **Deployment:** nixos-anywhere over SSH — requires the new server to be accessible via SSH first (Contabo provides Ubuntu, we convert).
- **Secrets:** sops-nix with age keys — secrets encrypted in repo, decrypted at activation time.
- **Disk:** Single disk, simple partition scheme (EFI + root). No separate /data partition.
- **Network:** Must support both public IP (HTTP/S) and Tailscale overlay network.
- **Firewall:** Explicit allow-list. Default deny. Tailscale traffic must be permitted.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Flakes + home-manager | Modern, reproducible, lockfile-pinned. Industry standard for NixOS configs. | — Pending |
| Docker stays, declared in Nix | Lower migration risk. Containers work. Nix manages Docker + networks. | — Pending |
| sops-nix for secrets | Secrets encrypted in-repo with age. Most popular NixOS secrets approach. | — Pending |
| nixos-anywhere for deployment | One-command remote install. Wipes target, installs NixOS. Production-proven. | — Pending |
| Drop ACFS, home-manager for shell | ACFS barely used. Home-manager is the NixOS-native way to manage dotfiles. | — Pending |
| rustup over Nix rust-overlay | More flexible for nightly workflows. Nix just ensures rustup is installed. | — Pending |
| Restic to Backblaze B2 | Cheap (~$5/TB/month), reliable, well-supported by Restic and NixOS module. | — Pending |
| Core infra first, services incremental | "Done" = boots + core tools + networking. Services added phase by phase. | — Pending |
| /data/projects/ as regular directory | Simple. No separate partition. disko manages EFI + root only. | — Pending |
| Firewall default-deny | Current server has NO firewall. NixOS should ship secure by default. | — Pending |

---
*Last updated: 2026-02-13 after initialization*
