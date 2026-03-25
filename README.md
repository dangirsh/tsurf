# tsurf

`tsurf` is a NixOS base for running untrusted agent workloads on remote machines.
The public repo is a reference template and test fixture set. Real deployments
live in a private overlay that imports these modules and adds host-specific
networking, secrets, and services.

> Status: useful, but still evolving. Treat the public repo as a base to adapt,
> not a stable product.

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
- Declarative, recovery-oriented base. `srvos`, `nix-mineral`, BTRFS rollback,
  impermanence, lockout-prevention assertions, and private-overlay deploy
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
