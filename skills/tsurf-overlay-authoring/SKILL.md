---
name: tsurf-overlay-authoring
description: Create or update a private tsurf overlay from discovered host facts. Use when an agent needs to author NixOS modules, choose public tsurf role modules, preserve private services, or migrate away from copied quickstart/template wiring without breaking existing private-overlay use cases.
---

# Tsurf Overlay Authoring

Use this skill after host discovery. The output should be a private overlay
change, not a deploy.

## Workflow

1. Read the private overlay first: `flake.nix`, role files, host file, deploy
   nodes, and any private module replacing a public module.
2. Prefer exported public modules:
   `inputs.tsurf.nixosModules.base`, `boot`, `networking`, `impermanence`,
   `agent-launcher`, `agent-sandbox`, `nono`, and role modules when they match.
3. Preserve private overrides. If a private repo replaces a public module for a
   real host constraint, do not force it back to the public role.
4. Keep secrets and host identity private. Do not add real hostnames, keys,
   service credentials, or personal users to the public repo.
5. Keep host facts local to the host config:
   disk devices, network interfaces, provider routing, ACME domains, and state
   version belong beside the host that needs them.
6. When adding agent workloads, use `services.agentLauncher.agents.<name>`
   unless the public launcher lacks a needed extension point. If it lacks one,
   prefer improving the public launcher API over copying launcher code.
7. Hand off to `tsurf-deploy-validation` before any deploy.

## Module Selection

- Use `agent-host` only for hosts that should run brokered prompt-controlled
  agents.
- Use `service-host` for service machines that should inherit public base
  hardening without the agent sandbox.
- Use individual `nixosModules` when the private overlay already has a mature
  role split and role modules would hide important provider-specific overrides.

## Guardrails

- Do not import `modules/secrets.nix` until `sops.defaultSopsFile` and persisted
  SSH host-key assumptions are true for the host.
- Do not put raw agent CLIs in global `environment.systemPackages`; expose them
  through generated wrappers.
- Do not widen `services.agentLauncher.scopeAccess` or `extraAllowPaths` without
  documenting why the workflow needs that access.
