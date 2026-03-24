# tsurf

An agent-centric [NixOS](https://nixos.org/) configuration. See [example use cases](#example-use-cases).

> This public repo is the base configuration. Real deployments come from a [private overlay](#private-overlay).

> **Warning:** This project is not yet stable. Use it as a reference only.

## Design Principles

The core assumptions behind tsurf are:

1. Agents are now **capable** enough to be the primary interface for most computing tasks.
2. Agents are becoming **cheap** enough to be used heavily and ubiquitously.
3. Agents are **untrusted**, capricious, and hijackable.

These lead to the following design goals:

1. **Optimize the system for use by agents**. Human use is always expected to be agent-mediated.
2. Support the use of **many agents across several machines**. The bottleneck should be compute/token costs, not management complexity.
3. Always deploy agents with **[least privilege](https://en.wikipedia.org/wiki/Principle_of_least_privilege)** and **[defense-in-depth](https://www.cyberark.com/what-is/defense-in-depth/)** to mitigate the risks of compromised/misaligned agents.

## Core Features

- **Agent sandboxing:** [nono](https://github.com/always-further/nono) isolates agents with [Landlock](https://docs.kernel.org/userspace-api/landlock.html) (kernel-level) and [proxy credential injection](https://nono.sh/blog/blog-credential-injection) (phantom token pattern; agents never see real API keys). Interactive sessions are brokered to an unprivileged `agent` user.
- **Fully declarative:** Agents get maximal system context from the source files. Imperative package management is disabled by convention (channels removed, NIX_PATH cleared). Undeclared state is wiped on boot via [BTRFS](https://btrfs.readthedocs.io/) subvolume rollback ([impermanence](https://github.com/nix-community/impermanence)).
- **Robust multi-host deployment:** [deploy-rs](https://github.com/serokell/deploy-rs) with [automatic rollbacks](https://github.com/serokell/deploy-rs?tab=readme-ov-file#magic-rollback) and build-time lockout prevention.
- **Hardened server configuration:** [srvos](https://github.com/nix-community/srvos) [server profile](https://github.com/nix-community/srvos/tree/main/nixos/server) (key-only SSH, immutable users, sudo wheel-only, systemd watchdogs, no emergency mode), [Tailscale](https://tailscale.com/) zero-trust networking (use [tailnet lock](https://tailscale.com/docs/features/tailnet-lock)), nftables default-deny firewall, and localhost-first internal services.
- **Optional batteries** (in [`extras/`](#extras)): dashboard, cost tracking, backups, and file sync. Multi-agent workflows belong in your private overlay.

## Example Use Cases

- Run a hardened Claude coding-agent path on a NixOS host.
- Host personal assistant agents (e.g. [OpenClaw](https://openclaw.org/)).
- Self-host autonomous agent experiments (e.g. [Conway Automata](https://conway.tech/))
- Run [MCP](https://modelcontextprotocol.io/) servers for agents (e.g. access to Google services, DMs, X API)

These are on top of more standard use cases (which can be built/maintained by the agents), including:

- Web services / static sites: agents field change requests, implement, and redeploy.
- Custom dashboards: Agents build visuals on-demand purely from prompts.
- Personal Knowledge Management (PKM): agents help with querying, maintaining, and syncing your knowledge graph(s).
- [Home Assistant](https://www.home-assistant.io/): agents manage the config directly, no UI needed.

## Service Conventions

Service modules declare their own dashboard entries, and localhost-only service ports are tracked in the central `internalOnlyPorts` registry in `modules/networking.nix`. Keep that registry in sync whenever you add or change an internal port.

| Category | Network | Examples |
|----------|---------|----------|
| Web | Public ([nginx](https://nginx.org/) + [ACME](https://letsencrypt.org/)) | personal sites |
| Internal | Localhost-only (`127.0.0.1`) | dashboard, syncthing GUI, restic-status |
| System | Public firewall | SSH (22), Syncthing BEP (22000) |
| Agent | outbound only | claude (core); custom agents in private overlay |
| Worker | none/outbound | restic backup |

## Extras

Optional modules in `extras/`. Import the file, then set the enable option:

```nix
# hosts/my-host/default.nix
imports = [ ../../extras/syncthing.nix ];

# then in config:
services.syncthingStarter.enable = true;
```

`extras/dashboard.nix` and `extras/cost-tracker.nix` are optional utilities. All extras are opt-in via explicit host imports.

| Module | Enable option | Description |
|--------|--------------|-------------|
| [`dashboard.nix`](extras/dashboard.nix) | `services.dashboard.enable` | Service dashboard with live systemd status |
| [`cost-tracker.nix`](extras/cost-tracker.nix) | `services.costTracker.enable` | API cost tracking (Anthropic, OpenAI) |
| [`syncthing.nix`](extras/syncthing.nix) | `services.syncthingStarter.enable` | Cross-host file sync (tailnet-only by default) |
| [`restic.nix`](extras/restic.nix) | `services.resticStarter.enable` | Encrypted backups to Backblaze B2 |
| [`home/`](extras/home/) | _(import as home-manager module)_ | git, SSH, direnv for the operator user |
| [`home/cass.nix`](extras/home/cass.nix) | `programs.cass.enable` | [CASS](https://github.com/Dicklesworthstone/coding_agent_session_search) agent session indexer |

All enable options default to `false`. In a [private overlay](#private-overlay), use `"${inputs.tsurf}/extras/syncthing.nix"` as the import path.

## Intentionally Absent

- `secrets/*.yaml` is intentionally absent from the public repo. Secret declarations are public; encrypted secret files live in your private overlay.
- Real SSH host keys are intentionally absent. Public eval fixtures keep placeholder material; private overlay hosts must provide real persisted keys.

## Private overlay

Personal services, real credentials, and host-specific config go in a separate private flake that imports this repo's modules individually. Core modules live in `modules/`; optional batteries live in `extras/`. The public flake is for reference and CI eval with placeholder fixture data. The private flake is the deployable one. It uses `follows` to share pinned dependencies and can replace modules entirely or import and extend them. See [`examples/private-overlay/`](examples/private-overlay/) for a forkable starting point, or [CLAUDE.md](CLAUDE.md) for the full overlay pattern.

## Getting Started

> Point your agent at [CLAUDE.md](CLAUDE.md) and ask nicely for what you want to do.

- **Requirements:** A VPS or bare-metal host running NixOS, an age key for sops secrets, and a private overlay for anything real. No KVM is needed for sandboxing; tsurf uses Landlock, not VMs.
- **Deploys from this repo are intentionally blocked.** The public flake exposes `.#eval-services`, `.#eval-dev`, and `.#eval-dev-alt-agent` for eval/testing only, and exports no `deploy.nodes`. Real deployments require a [private overlay](#private-overlay) with your credentials and host config.
- **Add your services:** fork [`examples/private-overlay/`](examples/private-overlay/) and import from `modules/` (core) and `extras/` (optional batteries).
- **Agent CLI (core):** `claude` is the only first-class interactive wrapper in public core.
- **Additional agents:** implement in your private overlay (see [private overlay walkthrough](examples/private-overlay/README.md#adding-a-custom-agent)).

## Related projects

- [stereOS](https://github.com/papercomputeco/stereOS) / [agentd](https://github.com/papercomputeco/agentd): NixOS agent OS with lifecycle daemon

## License

MIT
