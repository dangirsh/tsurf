# tsurf

A suite of tools for agentic computing, implemented as a [NixOS](https://nixos.org/) configuration. See [example use cases](#example-use-cases).

I use tsurf to manage coding/assistant agents across several remote servers. It enables me to rapidly experiment with new tools and approaches in agentic computing, without feeling like [this](https://www.youtube.com/watch?v=ipWuz6eZSl4).

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

- Sandbox-first agent execution. Public core ships a brokered `claude` wrapper
  built from `modules/agent-sandbox.nix`, `modules/agent-launcher.nix`,
  `modules/nono.nix`, and `scripts/agent-wrapper.sh`.
- Generic agent launcher. `services.agentLauncher.agents.<name>` turns a small
  Nix attrset into a wrapper, launcher, nono profile, sudo rule, and
  persistence entries.
- Two public host roles. `hosts/dev` is the agent-execution fixture;
  `hosts/services` is the service-host fixture. The public flake exports
  `eval-*` configurations only, not deploy targets.
- Declarative, recovery-oriented base. [srvos](https://github.com/nix-community/srvos), [nix-mineral](https://github.com/cynicsketch/nix-mineral), [BTRFS](https://btrfs.readthedocs.io/) rollback,
  [impermanence](https://github.com/nix-community/impermanence), lockout-prevention assertions, and private-overlay deploy
  tooling are built in.
- Optional batteries. Public extras include `dev-agent`, `codex`,
  `cost-tracker`, `restic`, and a home-manager profile for the agent user.

## Quick Start

1. Enable the project hooks once after cloning:
   `git config core.hooksPath .githooks`
2. Validate the public fixtures:
   `nix flake check`
3. Copy [`examples/private-overlay/`](examples/private-overlay/) into a private
   repository and replace the placeholders.
4. Generate a break-glass key with `nix run .#tsurf-init`. If you run it on the
   target host, add `--age` to derive the sops age identity from the persisted
   SSH host key.
5. Deploy from the private overlay only. The public repo intentionally blocks
   real deploys in [`scripts/deploy.sh`](scripts/deploy.sh).

## Documentation

- Architecture: [`docs/architecture.md`](docs/architecture.md)
- Operations and commands: [`docs/operations.md`](docs/operations.md)
- Optional modules and home profile: [`docs/extras.md`](docs/extras.md)
- Security model: [`SECURITY.md`](SECURITY.md)
- Claim-level technical spec: [`spec/README.md`](spec/README.md)
- Private overlay template:
  [`examples/private-overlay/README.md`](examples/private-overlay/README.md)
- Repo-specific agent guidance: [`CLAUDE.md`](CLAUDE.md)

## License

MIT
