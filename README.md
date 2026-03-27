# tsurf

A suite of tools for agentic computing, implemented as a [NixOS](https://nixos.org/) configuration. See [example use cases](#example-use-cases).

I use tsurf to manage coding/assistant agents across several remote servers. It enables me to rapidly experiment with new tools and approaches in agentic computing, without feeling like [this](https://youtu.be/GFiWEjCedzY?si=BhtI8varawf4qMh-&t=30).

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

- **Sandboxed agent execution.** Agents run inside a deny-by-default
  [Landlock](https://landlock.io/) sandbox with restricted filesystem and
  network access. Real credentials never enter the agent process; a separate
  broker supplies short-lived, per-session tokens.
- **Declarative agent launcher.** Define a new agent type in a few lines of config
  and get a sandboxed wrapper, credential brokering, resource controls, and
  persistent storage automatically.
- **Hardened, stateless base.** Kernel hardening, encrypted secrets ([sops](https://github.com/getsops/sops)),
  strict firewall rules, and a root filesystem that rolls back to a clean
  snapshot on every boot, so a misbehaving agent (or operator) can't
  permanently corrupt the system.
- **Deploy safety.** Lockout-prevention assertions catch misconfigurations
  (e.g., missing SSH keys, exposed ports) before they reach a live machine.
  Deploys are locked, health-checked, and rollback-aware.
- **Public base / private overlay model.** This repo is the reusable
  foundation. Real credentials, host-specific services, and personal config
  live in a separate private repo that imports what it needs.

## Available Extras

| Extra | Enable |
|------|--------|
| `extras/cass.nix` | Import + `services.cassIndexer.enable = true` |
| `extras/codex.nix` | Import + `services.codexAgent.enable = true` |
| `extras/cost-tracker.nix` | Import + `services.costTracker.enable = true` |
| `extras/restic.nix` | Import + `services.resticStarter.enable = true` |
| `extras/home/` | `home-manager.users.<name> = import ./extras/home;` |

tsurf supports custom agents via the generic launcher; see
[`docs/extras.md`](docs/extras.md#extending-tsurf-custom-agents) for the extension API.

## Quick Start

See [`QUICKSTART.md`](QUICKSTART.md) for setup and private overlay creation, or continue below for a summary.

1. Enable the project hooks once after cloning:
   `git config core.hooksPath .githooks`
2. Validate the public fixtures:
   `nix flake check`
3. Copy [`examples/private-overlay/`](examples/private-overlay/) into a private
   repository and replace the placeholders.
4. Generate a real root SSH key for the private overlay:
   `nix run .#tsurf-init -- --overlay-dir /path/to/private-overlay`
5. If you run `tsurf-init` on the target host, add `--age` to derive the sops
   age identity from the persisted SSH host key.
6. Deploy from the private overlay only. The public repo intentionally blocks
   real deploys in [`scripts/deploy.sh`](scripts/deploy.sh).

## Documentation

- Quickstart (newcomer path): [`QUICKSTART.md`](QUICKSTART.md)
- Architecture: [`docs/architecture.md`](docs/architecture.md)
- Operations and commands: [`docs/operations.md`](docs/operations.md)
- Optional modules and home profile: [`docs/extras.md`](docs/extras.md)
- Security model: [`SECURITY.md`](SECURITY.md)
- Private overlay template:
  [`examples/private-overlay/README.md`](examples/private-overlay/README.md)

## License

MIT
