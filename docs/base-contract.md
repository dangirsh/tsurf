# Public Base Contract

`tsurf` is an opinionated public base for one-owner, self-sovereign agent
infrastructure. It is not a general multi-tenant platform, team control plane,
or collection of personal app deployments.

## In Scope

The public base owns these primitives:

- hardened NixOS defaults for a small fleet operated by one owner
- a dedicated `agent` principal with no general root access
- sandboxed agent execution through the generated launcher path
- Iron-backed egress and provider credential mediation
- declarative deploy safety checks for private overlays
- self-hosted Nix binary cache plumbing through Harmonia
- self-hosted mesh coordination through Headscale
- a narrow public/private overlay boundary

The public repo should keep these primitives small, readable, and boring. Prefer
one supported path over multiple compatibility paths.

## Out Of Scope

The public base does not own:

- real deploy targets
- real secrets
- Mini Registry or any other private app registry
- personal web apps, assistants, comms bridges, or business/project services
- Matrix rooms, DM MCP wiring, Signal/WhatsApp/Telegram bridge policy, or Hermes
- file sync topology, home LAN policy, or production Headscale ACLs
- project-specific development environments
- broad provider-specific agent wrapper families

Those belong in a private overlay or in the project repo that owns them.

## Required Private Overlay Responsibilities

A real deployment must provide:

- hostnames, IP addresses, hardware, disks, and boot policy
- encrypted sops files and real age recipients
- Headscale domain, public IP, nameservers, and ACL policy
- Harmonia cache host, signing key, trust key, and client allowlist
- provider secrets consumed by Iron
- any private services, app vhosts, background jobs, and app deploy scripts

## Credential Contract

Iron is the public credential and model-key mediation path. The child process
gets provider-shaped placeholder credentials plus proxy/CA environment variables;
`iron-proxy` owns the real provider keys and replaces placeholders at egress.

`nono` remains the local filesystem/process sandbox. Public modules do not carry
a second nono-backed provider credential path.

## Cache Contract

The self-hosted Harmonia cache is core infrastructure, not an optional extra in
the design sense. It still needs host-specific settings, so public fixtures keep
it disabled until a private overlay supplies the cache host, keys, and allowlist.

Do not replace the public recommendation with Cachix. Public docs may mention
Cachix only as a non-goal or contrast, not as the preferred path.

## Mesh Contract

Headscale is core infrastructure, not an optional extra in the design sense.
The public base should provide the simple self-hosted control-plane shape;
private overlays own actual ACLs, subnet routers, DNS choices, and home/network
exposure.

## Simplicity Rule

When a feature is only useful for one private deployment, move it private. When a
feature is useful for the base but needs uncommon branches, keep one public happy
path and make the private overlay own the branches.
