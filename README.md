# tsurf

A security-first, minimal [NixOS](https://nixos.org/) base for one-owner,
self-sovereign agent-centric personal computing. See
[`docs/base-contract.md`](docs/base-contract.md) for the public/private
boundary.

I use tsurf to manage coding/assistant agents across several remote servers. It enables me to rapidly experiment with new tools and approaches in agentic computing, without feeling like [this](https://youtu.be/GFiWEjCedzY?si=BhtI8varawf4qMh-&t=30).

> This public repo is the base configuration. It exports eval fixtures and reusable modules, not deploy targets. Real deployments come from a private overlay; start with [`QUICKSTART.md`](QUICKSTART.md) and [`examples/private-overlay/`](examples/private-overlay/).

> **Warning:** This project is not yet stable. Use it as a reference only.

## Design Principles

The core assumptions behind tsurf are:

1. Agents are now **capable** enough to be the primary interface for most computing tasks.
2. Agents are becoming **cheap** enough to be used heavily and ubiquitously.
3. Agents are **untrusted**, capricious, and hijackable.

These lead to the following design goals:

1. **Optimize the operating system for use by agents**. Human-use is always expected to be agent-mediated.
2. Support the effective management of a **small owner-operated fleet** of
   agent hosts. The bottleneck should be compute/token costs, not management
   complexity.
3. Always deploy agents with **[least privilege](https://en.wikipedia.org/wiki/Principle_of_least_privilege)** and **[defense-in-depth](https://www.cyberark.com/what-is/defense-in-depth/)** to mitigate the risks of compromised/misaligned agents.

## Core Features

- **Sandboxed agent execution.** Agents run through
  [nono](https://github.com/nolabs-ai/nono), using
  [Landlock](https://landlock.io/)-backed filesystem rules, per-workspace
  launch scoping, and systemd resource limits.
- **Iron-backed egress and credential brokering.** Supported API-backed
  wrappers use [iron-proxy](https://github.com/ironsh/iron-proxy) on loopback
  for destination allowlists, credential replacement, proxy CA state, and
  per-request logs. Raw provider keys stay in the Iron service environment; the
  child gets provider-shaped placeholders plus proxy/CA environment variables.
  The legacy `nono` credential-proxy mode is compatibility debt, not the public
  happy path.
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
- **Self-hosted Nix cache layer.** The public base includes the
  `harmonia-cache` module to trust or serve a
  [Harmonia](https://github.com/nix-community/harmonia) binary cache with a
  SOPS-managed signing key and an nftables client allowlist. This is the
  recommended cache path for real overlays.
- **Self-hosted mesh coordination.** The public base includes Headscale for a
  self-hosted Tailscale-compatible control plane. Private overlays provide the
  real domain, ACLs, nameservers, subnet routers, and exposure policy.
- **Optional extras.** Reusable opt-ins include Restic/B2 backups, OpenAI Codex,
  OpenRouter Codex, CASS session indexing, and a home-manager profile for the
  dedicated agent user.
- **Deploy safety.** Lockout-prevention assertions catch misconfigurations
  (e.g., missing SSH keys, exposed ports) before they reach a live machine.
  [deploy-rs](https://github.com/serokell/deploy-rs)-based deploys are locked,
  health-checked, and rollback-aware.
- **Public base / private overlay model.** This repo is the reusable
  foundation. Real credentials, host-specific services, and personal config
  live in a separate private repo that imports what it needs.

## Shipped Agent Paths

- Core exports a sandboxed interactive `claude` wrapper through the
  `agent-host` / `agent-sandbox` role.
- Custom wrappers use `services.agentLauncher.agents.<name>`, which produces a
  wrapper, immutable launcher, `nono` profile, sudo rule, resource limits, and
  persistence wiring.
- Opt-in public extras provide `codex`, `codex-openrouter`, CASS indexing,
  Restic backups, and the agent home profile.
- Core public modules include `headscale` and `harmonia-cache`; private overlays
  supply the real host settings that make them deployable.

## Example Use Cases

- Run hardened, supervised coding agents against dedicated workspace repos on remote NixOS hosts.
- Host personal assistant agents (e.g. [OpenClaw](https://openclaw.org/)).
- Self-host autonomous agent experiments without putting private app code in the
  public base.

These are on top of more standard use cases (which can be built/maintained by the agents), including:

- Web services / static sites: agents field change requests, implement, and redeploy.
- Personal Knowledge Management (PKM): agents help with querying, maintaining, and syncing your knowledge graph(s).
- [Home Assistant](https://www.home-assistant.io/): agents manage the config directly, no UI needed.

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

To validate the public template or a docs-adjacent contribution:

```bash
git config core.hooksPath .githooks
./scripts/run-tests.sh
```

## Documentation

- Architecture: [`docs/architecture.md`](docs/architecture.md)
- Operations and commands: [`docs/operations.md`](docs/operations.md)
- Public/private base contract: [`docs/base-contract.md`](docs/base-contract.md)
- Optional modules and home profile: [`docs/extras.md`](docs/extras.md)
- Roadmap and deferred security work: [`docs/roadmap.md`](docs/roadmap.md)
- Security model: [`SECURITY.md`](SECURITY.md)
- Private overlay template:
  [`examples/private-overlay/README.md`](examples/private-overlay/README.md)
- Repo-specific agent guidance: [`CLAUDE.md`](CLAUDE.md) and
  [`AGENTS.md`](AGENTS.md)

## License

MIT
