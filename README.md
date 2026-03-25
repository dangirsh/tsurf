# tsurf

A suite of tools for agentic computing, implemented as a [NixOS](https://nixos.org/) configuration. See [example use cases](#example-use-cases).

I use tsurf to manage coding/assistant agents across several remote servers. It enables me to rapidly experiment with new tools and approaches in agentic computing, without feeling like [this](TODO broom mickey phantasia clip).

> This public repo is the base configuration. Real deployments come from a [private overlay](#private-overlay).

> **Warning:** This project is not yet stable. Use it as a reference only.

## Design Principles

The core assumptions behind tsurf are:

1. Agents are now **capable** enough to be the primary interface for most computing tasks.
2. Agents are becoming **cheap** enough to be used heavily and ubiquitously.
3. Agents are **untrusted**, capricious, and hijackable.

These lead to the following design goals:

1. **Optimize the operating system for use by agents**. Human use is always expected to be agent-mediated.
2. Support the effective management of **many agents across several machines**. The bottleneck should be compute/token costs, not management complexity.
3. Always deploy agents with **[least privilege](https://en.wikipedia.org/wiki/Principle_of_least_privilege)** and **[defense-in-depth](https://www.cyberark.com/what-is/defense-in-depth/)** to mitigate the risks of compromised/misaligned agents.

## Core Features

- **Generic agent launcher:** `modules/agent-launcher.nix` provides a typed option interface — each agent is ~15 lines of config (binary path, nono profile, credentials, default args) on top of shared infrastructure (wrapper, systemd-run broker, credential proxy, resource limits).
- **Agent sandboxing:** [nono](https://github.com/always-further/nono) isolates agents with [Landlock](https://docs.kernel.org/userspace-api/landlock.html) (kernel-level). A root-owned per-session credential proxy keeps raw provider keys out of the `agent` principal and gives the child only loopback base URLs plus opaque session tokens.
- **Core agent paths:** public core ships the sandboxed interactive `claude` wrapper plus a first-class `dev-agent` service for unattended work on a dedicated workspace repo. `codex` is an opt-in extra using the same generic launcher.
- **Fully declarative:** Agents get maximal system context from the source files. Imperative package management is disabled by convention (channels removed, NIX_PATH cleared). Undeclared state is wiped on boot via [BTRFS](https://btrfs.readthedocs.io/) subvolume rollback ([impermanence](https://github.com/nix-community/impermanence)).
- **Two-user privilege model:** root (operator/deploy/admin) and agent (sandboxed tools). Agent is in wheel for sudo to immutable launcher binaries only. No separate operator user — all administration is agent-mediated or via root emergency access.
- **Robust deployment:** [deploy-rs](https://github.com/serokell/deploy-rs) with [automatic rollbacks](https://github.com/serokell/deploy-rs?tab=readme-ov-file#magic-rollback), build-time lockout prevention, and `scripts/deploy.sh` as a ready-to-use template.
- **Hardened server configuration:** [srvos](https://github.com/nix-community/srvos) [server profile](https://github.com/nix-community/srvos/tree/main/nixos/server) (key-only SSH, immutable users, tightly scoped sudo rules), nftables default-deny firewall, coredumps disabled, `protectKernelImage` enabled, and localhost-first internal services. Tailscale and other networking belongs in your private overlay.
- **Agent-aware outbound control:** agent traffic is allowlisted at the host firewall by UID. The default policy allows DNS plus TCP `22/80/443` and blocks private/link-local ranges.
- **CLI tools:** `nix run .#tsurf-init` bootstraps SSH keys and sops age keys. `nix run .#tsurf-status -- <host>` checks service health across hosts.
- **Complexity guard:** a post-commit hook tracks effective lines of code and warns when a commit increases complexity by more than 50 eLOC.
- **Optional batteries** (in [`extras/`](#extras)): `dev-agent`, `codex` wrapper, cost tracking, backups, and session search. Additional agents and services belong in your private overlay.

## Example Use Cases

- Run a hardened Claude coding-agent path on a NixOS host.
- Run a supervised dev agent against a dedicated workspace repo on a remote host.
- Host personal assistant agents (e.g. [OpenClaw](https://openclaw.org/)).
- Self-host autonomous agent experiments (e.g. [Conway Automata](https://conway.tech/))
- Run [MCP](https://modelcontextprotocol.io/) servers for agents (e.g. access to Google services, DMs, X API)

These are on top of more standard use cases (which can be built/maintained by the agents), including:

- Web services / static sites: agents field change requests, implement, and redeploy.
- Personal Knowledge Management (PKM): agents help with querying, maintaining, and syncing your knowledge graph(s).
- [Home Assistant](https://www.home-assistant.io/): agents manage the config directly, no UI needed.

## Service Conventions

Localhost-only service ports are tracked in the central `internalOnlyPorts` registry in `modules/networking.nix`. Keep that registry in sync whenever you add or change an internal port.

| Category | Network | Examples |
|----------|---------|----------|
| Web | Public ([nginx](https://nginx.org/) + [ACME](https://letsencrypt.org/)) | personal sites |
| Internal | Localhost-only (`127.0.0.1`) | cost-tracker |
| System | Public firewall | SSH (22) |
| Agent | outbound only | `claude`, `dev-agent`; opt-in `codex` |
| Worker | none/outbound | restic backup |

## Extras

Optional modules in `extras/`. Import the file, then set the enable option:

```nix
# hosts/my-host/default.nix
imports = [ ../../extras/codex.nix ];

# then in config:
services.codexAgent.enable = true;
```

`extras/dev-agent.nix` is the supported unattended agent path. `codex` is an opt-in wrapper using the generic launcher. `cost-tracker` and `restic` are optional utilities. All extras are opt-in.

| Module | Enable option | Description |
|--------|--------------|-------------|
| [`dev-agent.nix`](extras/dev-agent.nix) | `services.devAgent.enable` | Unattended Claude service (supervised `zmx` session on a workspace repo) |
| [`codex.nix`](extras/codex.nix) | `services.codexAgent.enable` | Opt-in Codex wrapper (OpenAI, uses generic launcher) |
| [`cost-tracker.nix`](extras/cost-tracker.nix) | `services.costTracker.enable` | API cost tracking (Anthropic, OpenAI) |
| [`restic.nix`](extras/restic.nix) | `services.resticStarter.enable` | Encrypted backups to Backblaze B2 |
| [`home/`](extras/home/) | _(import as home-manager module)_ | git, SSH, direnv, CASS session indexer (enabled by default) |

## Intentionally Absent

- `secrets/*.yaml` is intentionally absent from the public repo. Secret declarations are public; encrypted secret files live in your private overlay.
- Real SSH host keys are intentionally absent. Run `nix run .#tsurf-init` to generate keys, then add them to your private overlay.
- Tailscale, file sync, and deployment-specific networking belong in your private overlay.

## Private overlay

Personal services, real credentials, and host-specific config go in a separate private flake that imports this repo's modules individually. Core modules live in `modules/`; optional batteries live in `extras/`. The public flake is for reference and CI eval with placeholder fixture data. The private flake is the deployable one. It uses `follows` to share pinned dependencies and can replace modules entirely or import and extend them. See [`examples/private-overlay/`](examples/private-overlay/) for a forkable starting point, or [CLAUDE.md](CLAUDE.md) for the full overlay pattern.

## Getting Started

> Point your agent at [CLAUDE.md](CLAUDE.md) and ask nicely for what you want to do.

1. **Bootstrap:** `nix run .#tsurf-init` — generates root SSH key and optionally derives sops age key.
2. **Fork the overlay:** copy [`examples/private-overlay/`](examples/private-overlay/) and add your credentials/host config.
3. **Deploy:** `cd your-private-overlay && ./scripts/deploy.sh --node <host>`
4. **Interactive agent:** `claude` is the sandboxed wrapper in public core.
5. **Unattended agent:** import `extras/dev-agent.nix`, set `services.devAgent.enable = true`.
6. **Add custom agents:** define them via `services.agentLauncher.agents.<name>` — see [`examples/private-overlay/modules/code-review.nix`](examples/private-overlay/modules/code-review.nix).
7. **Check status:** `nix run .#tsurf-status -- <host>`
8. **Git hooks:** `git config core.hooksPath .githooks` — enables pre-commit guards and complexity tracking.

- **Deploys from this repo are intentionally blocked.** The public flake exposes `.#eval-services`, `.#eval-dev`, and `.#eval-dev-alt-agent` for eval/testing only. Real deployments require a [private overlay](#private-overlay).

## Related projects

- [stereOS](https://github.com/papercomputeco/stereOS) / [agentd](https://github.com/papercomputeco/agentd): NixOS agent OS with lifecycle daemon

## License

MIT
