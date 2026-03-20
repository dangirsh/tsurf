# tsurf

A [NixOS](https://nixos.org/) configuration optimized for agentic computing — deploy and manage AI agents across remote hosts, alongside the services they build and maintain.

> This public repo is the base configuration. Personal services live in a [private overlay](#private-overlay).

## Design Principles

The core assumptions behind tsurf are:

1. Agents are now **capable** enough to be the primary interface for most computing tasks.
2. Agents are becoming **cheap** enough to be used heavily and ubiquotously.
3. Agents are **untrusted**, capricious, and hijackable.

These lead to the following design goals:

1. **Optimize the system for use by agents**. Human use is always expected to be agent-mediated.
2. Support the use of **many agents across several machines**. The bottleneck should be compute/token costs, not management complexity.
3. Always deploy agents with **[least privilege](https://en.wikipedia.org/wiki/Principle_of_least_privilege)** and **[defense-in-depth](https://www.cyberark.com/what-is/defense-in-depth/)** to mitigate the risks of compromised/misaligned agents.

## Core Features

- **Agent sandboxing:** [nono](https://github.com/always-further/nono) isolates agents with [Landlock](https://docs.kernel.org/userspace-api/landlock.html) (kernel-level, irreversible) and [credential injection](https://nono.sh/blog/blog-credential-injection).
- **Fully declarative:** Agents get maximal system context from the source files. Imperative package management is disabled by convention (channels removed, NIX_PATH cleared). Undeclared state is wiped on boot via [BTRFS](https://btrfs.readthedocs.io/) subvolume rollback ([impermanence](https://github.com/nix-community/impermanence)). 
- **Robust multi-host deployment:** [deploy-rs](https://github.com/serokell/deploy-rs) with [automatic rollbacks](https://github.com/serokell/deploy-rs?tab=readme-ov-file#magic-rollback), build-time lockout prevention, and auto-generated service health dashboard.
- **Hardened server configuration:** [srvos](https://github.com/nix-community/srvos) [server profile](https://github.com/nix-community/srvos/tree/main/nixos/server) (key-only SSH, immutable users, sudo wheel-only, systemd watchdogs, no emergency mode), [Tailscale](https://tailscale.com/) zero-trust networking (use [tailnet lock](https://tailscale.com/docs/features/tailnet-lock)), nftables default-deny firewall.
- **Batteries included (opt-in):** Coding agents ([Claude Code](https://claude.com/claude-code), [Codex](https://github.com/openai/codex), [Pi](https://github.com/badlogic/pi-mono)), agent session search ([CASS](https://github.com/Dicklesworthstone/coding_agent_session_search)), token cost tracking, encrypted backups ([Restic](https://restic.net/) + [B2](https://www.backblaze.com/cloud-storage)), cross-host file sync ([Syncthing](https://syncthing.net/)), and secret management ([sops-nix](https://github.com/Mic92/sops-nix)). Non-core services have enable options and default to off.

## Example Use Cases

- Manage coding agents across multiple hosts.
- Host personal assistant agents (e.g. [OpenClaw](https://openclaw.org/)).
- Run periodic "daemon" agents (e.g to reclaim resources / maintain system health).
- Self-host autonomous agent experiments (e.g. [Conway Automata](https://conway.tech/))
- Run [MCP](https://modelcontextprotocol.io/) servers for agents (e.g. access to Google services, DMs, X API)

These are on top of more standard use cases (which can be built/maintained by the agents), including:

- Web services / static sites: agents field change requests, implement, and redeploy.
- Custom dashboards: Agents build visuals on-demand purely from prompts. 
- Personal Knowledge Management (PKM): agents help with querying, maintaining, and syncing your knowledge graph(s).
- [Home Assistant](https://www.home-assistant.io/): agents manage the config directly, no UI needed.

## Service Conventions

Each module declares its own dashboard entry and network exposure directly. Internal ports are registered in `networking.nix` to enforce firewall assertions.

| Category | Network | Examples |
|----------|---------|----------|
| Web | Public ([nginx](https://nginx.org/) + [ACME](https://letsencrypt.org/)) | personal sites |
| Internal | Tailscale-only | dashboard, syncthing GUI, restic-status |
| Bootstrap | Public firewall | SSH (22), Syncthing BEP (22000) |
| Agent | outbound only | claude, codex, pi |
| Worker | none/outbound | restic backup, sshd-liveness-check |

## Private overlay

Personal services, real credentials, and host-specific config go in a separate private flake that imports this repo's modules individually. The private flake uses `follows` to share pinned dependencies and can replace modules entirely or import and extend them. See [`examples/private-overlay/`](examples/private-overlay/) for a forkable starting point, or [CLAUDE.md](CLAUDE.md) for the full overlay pattern.

## Getting Started

Point your agent at [CLAUDE.md](CLAUDE.md) and then ask nicely for what you want to do.

## Related projects

- [nono](https://github.com/always-further/nono) — Landlock sandbox + credential injection (used directly)
- [llm-agents.nix](https://github.com/numtide/llm-agents.nix) — agent CLI packaging for NixOS (used directly)
- [zmx](https://github.com/neurosnap/zmx) — terminal session persistence (used directly)
- [Netclode](https://github.com/angristan/netclode) — self-hosted agent server; credential proxy pattern origin
- [stereOS](https://github.com/papercomputeco/stereOS) / [agentd](https://github.com/papercomputeco/agentd) — NixOS agent OS and lifecycle daemon
- [Misterio77/nix-config](https://github.com/Misterio77/nix-config) — impermanence + BTRFS rollback patterns
- [EmergentMind/nix-config](https://github.com/EmergentMind/nix-config) — private secrets and multi-host sops

## License

MIT
