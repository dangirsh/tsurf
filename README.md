# tsurf

A security-first, minimal [NixOS](https://nixos.org/) base for agent-centric personal computing. See [example use cases](#example-use-cases).

I use tsurf to manage coding/assistant agents across several remote servers. It enables me to rapidly experiment with new tools and approaches in agentic computing, without feeling like [this](https://youtu.be/GFiWEjCedzY?si=BhtI8varawf4qMh-&t=30).

> This public repo is the base configuration. Real deployments come from a [private overlay](#private-overlay).

> **Warning:** This project is not yet stable. Use it as a reference only.

## Design Principles

The core assumptions behind tsurf are:

1. Agents are now **capable** enough to be the primary interface for most computing tasks.
2. Agents are becoming **cheap** enough to be used heavily and ubiquitously.
3. Agents are **untrusted**, capricious, and hijackable.

These lead to the following design goals:

1. **Optimize the operating system for use by agents**. Human-use is always expected to be agent-mediated.
2. Support the effective management of **many agents across several machines**. The bottleneck should be compute/token costs, not management complexity.
3. Always deploy agents with **[least privilege](https://en.wikipedia.org/wiki/Principle_of_least_privilege)** and **[defense-in-depth](https://www.cyberark.com/what-is/defense-in-depth/)** to mitigate the risks of compromised/misaligned agents.

## Core Features

- **Sandboxed agent execution.** Agents run through
  [nono](https://github.com/always-further/nono), using
  [Landlock](https://landlock.io/)-backed filesystem rules and coarse
  host-level egress limits. Supported API-backed wrappers are designed to keep
  real provider credentials on the broker side and give the child only
  per-session proxy tokens.
- **Declarative agent launcher.** Define a new agent type in a few lines of config
  and get a sandboxed wrapper, credential brokering, resource controls, and
  persistent storage automatically.
- **Hardened, stateless base.** Kernel hardening with
  [nix-mineral](https://github.com/cynicsketch/nix-mineral) and
  [srvos](https://github.com/nix-community/srvos), encrypted secrets via
  [sops-nix](https://github.com/Mic92/sops-nix) / [sops](https://github.com/getsops/sops),
  strict firewall rules, and an
  [impermanence](https://github.com/nix-community/impermanence)-style root
  filesystem that rolls back to a clean snapshot on every boot.
- **Self-hosted Nix cache layer.** Private overlays can import the public
  `harmonia-cache` module to trust or serve a
  [Harmonia](https://github.com/nix-community/harmonia) binary cache with a
  SOPS-managed signing key and an nftables client allowlist.
- **Deploy safety.** Lockout-prevention assertions catch misconfigurations
  (e.g., missing SSH keys, exposed ports) before they reach a live machine.
  [deploy-rs](https://github.com/serokell/deploy-rs)-based deploys are locked,
  health-checked, and rollback-aware.
- **Public base / private overlay model.** This repo is the reusable
  foundation. Real credentials, host-specific services, and personal config
  live in a separate private repo that imports what it needs.

## Example Use Cases

- Run hardened, supervised coding agents against dedicated workspace repos on remote NixOS hosts.
- Host personal assistant agents (e.g. [OpenClaw](https://openclaw.org/)).
- Self-host autonomous agent experiments (e.g. [Conway Automata](https://conway.tech/))

These are on top of more standard use cases (which can be built/maintained by the agents), including:

- Web services / static sites: agents field change requests, implement, and redeploy.
- Personal Knowledge Management (PKM): agents help with querying, maintaining, and syncing your knowledge graph(s).
- [Home Assistant](https://www.home-assistant.io/): agents manage the config directly, no UI needed.
- Cost visibility: private overlays can add lightweight token/API spend reporting when useful.

## Setup

Start with the repo-local skills in [`skills/`](skills/):

- `tsurf-host-discovery`: inspect the target host and classify storage,
  networking, and role needs.
- `tsurf-overlay-authoring`: turn discovered facts into a private overlay using
  exported public modules and roles.
- `tsurf-deploy-validation`: validate the public repo or private overlay before
  any deploy.
See [`QUICKSTART.md`](QUICKSTART.md) and
[`examples/private-overlay/`](examples/private-overlay/) for the private-overlay
workflow.

## Documentation

- Architecture: [`docs/architecture.md`](docs/architecture.md)
- Operations and commands: [`docs/operations.md`](docs/operations.md)
- Optional modules and home profile: [`docs/extras.md`](docs/extras.md)
- Roadmap and deferred security work: [`docs/roadmap.md`](docs/roadmap.md)
- Security model: [`SECURITY.md`](SECURITY.md)
- Private overlay template:
  [`examples/private-overlay/README.md`](examples/private-overlay/README.md)
- Repo-specific agent guidance: [`CLAUDE.md`](CLAUDE.md)

## License

MIT
