# Current Parts Deployment Mechanism

**Documented:** 2026-02-17
**Status:** Pre-pipeline (no standalone deploy workflow)

## Trigger

Manual. A developer runs `nix flake lock --recreate-lock-file` (to pick up `path:` input changes) followed by the established Phase 2 deploy pattern from the dev machine. There is no CI/CD, no deploy script, no automation.

## Mechanism

1. Parts repo (`/data/projects/parts`) exports `nixosModules.default` via its `flake.nix`
2. Agent-neurosys imports it as a flake input: `parts.url = "path:/data/projects/parts"`
3. The module is included in `nixosConfigurations.acfs` via `inputs.parts.nixosModules.default`
4. Deploy uses the Phase 2 pattern: `nix copy --to ssh://root@acfs` + remote `switch-to-configuration switch`
5. NixOS restarts only changed systemd services (container services are managed by `oci-containers`)

The `path:` input means Nix resolves the parts flake from the local filesystem at `/data/projects/parts`. Changes to the parts repo require `nix flake lock --recreate-lock-file` to force narHash recomputation (see DEPLOY-03 from Phase 2).

## Components Deployed

| Component | Type | Declared In |
|-----------|------|-------------|
| parts-tools | Docker container (oci-container) | `nix/module.nix` |
| parts-agent | Docker container (oci-container) | `nix/module.nix` |
| agent_net | Docker network (internal) | `nix/module.nix` |
| tools_net | Docker network (external) | `nix/module.nix` |
| 10 sops secrets | Decrypted to /run/secrets/ | `nix/module.nix` |
| 2 sops templates | Container env files | `nix/module.nix` |
| tmpfiles rules | Host directories (/var/lib/parts/*) | `nix/module.nix` |

Docker images are built via `dockerTools.buildLayeredImage` in `nix/parts-agent.nix` and `nix/parts-tools.nix`.

## Limitations

- **`path:` input only works locally:** The dev machine must have `/data/projects/parts` checked out. Cannot deploy from the server or any other machine.
- **No standalone deploy script:** Deployment requires remembering the exact sequence of nix commands.
- **narHash caching:** Changes to parts require `--recreate-lock-file` workaround with `path:` inputs.
- **No health verification:** After switching, there's no automated check that containers came up.
- **No rollback guidance:** If something breaks, the operator must know to use `nixos-rebuild switch --rollback`.
- **No `nixos-rebuild`:** Build machine is Ubuntu; uses manual `nix copy` + `switch-to-configuration` instead of atomic `nixos-rebuild`.
