# tsurf

`tsurf` is a public NixOS base for one-owner, self-sovereign agent
infrastructure. It is the reusable core: hardened host defaults, sandboxed
agent execution, brokered model credentials, deploy guardrails, and the
public/private overlay boundary.

It is intentionally not a deployable fleet repo. Real hosts, secrets, domains,
apps, and policy live in a private overlay. See
[`docs/base-contract.md`](docs/base-contract.md).

> This project is still evolving. Treat it as a reference base, not a stable
> product interface.

## Architecture

```text
private overlay
  -> imports public tsurf modules
  -> provides hosts, secrets, domains, ACLs, apps
  -> deploys real machines

public tsurf
  -> exports modules, eval fixtures, tests, skills, and examples
  -> does not export deploy targets
```

## Core Features

- **Sandboxed agents:** generated wrappers launch agents through `systemd-run`,
  `nono`, Landlock filesystem policy, resource limits, and a dedicated `agent`
  user with no general root access.
- **One credential path:** supported model/API keys go through Iron-backed
  egress and credential replacement. Children get placeholder provider tokens
  plus proxy/CA env vars, not raw provider keys.
- **Hardened NixOS base:** `srvos`, `nix-mineral`, nftables, explicit SSH
  hardening, sops-nix secrets, and impermanent-root support.
- **Self-hosted cache:** Harmonia cache client/server plumbing is core. Private
  overlays provide keys, hostnames, and allowlists.
- **Self-hosted mesh:** Headscale is the core answer for private agent
  networking. Private overlays own ACLs, DNS, subnet routers, and exposure.
- **Deploy safety:** guarded deploy scripts, eval checks, rollback-aware deploy
  flow, and live/VM test hooks.

## What Goes Private

Keep these out of the public base:

- real deploy nodes and secrets
- personal apps, registries, websites, assistants, and comms bridges
- Matrix/DM MCP policy, Signal/Telegram/WhatsApp details, and Hermes
- Mini Registry and app-specific deploy accelerators
- home LAN routes, broad Headscale ACLs, and project-specific dev environments
- provider experiments beyond small public recipes

## Getting Started

1. Read [`QUICKSTART.md`](QUICKSTART.md).
2. Copy [`examples/private-overlay/`](examples/private-overlay/) into a private
   repo.
3. Replace placeholders, configure sops, and deploy from the private overlay.

For agent-assisted setup, use the repo-local skills:

- `skills/tsurf-host-discovery`
- `skills/tsurf-overlay-authoring`
- `skills/tsurf-deploy-validation`

## Validation

```bash
git config core.hooksPath .githooks
./scripts/run-tests.sh
```

## Docs

- Public/private boundary: [`docs/base-contract.md`](docs/base-contract.md)
- Quick setup: [`QUICKSTART.md`](QUICKSTART.md)
- Architecture: [`docs/architecture.md`](docs/architecture.md)
- Operations: [`docs/operations.md`](docs/operations.md)
- Security model: [`SECURITY.md`](SECURITY.md)
- Extras: [`docs/extras.md`](docs/extras.md)

## License

MIT
