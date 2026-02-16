---
phase: 04-docker-services
plan: 01
subsystem: claw-swap
tags: [flake, nixos-module, sops-nix, sops, secrets, docker, dockerTools, buildNpmPackage, hono]

requires:
  - phase: 03.1-parts-migration
    provides: flake exports (nixosModules.default + packages) + sops-nix secrets pattern + dockerTools images pattern
provides:
  - claw-swap flake exporting nixosModules.default and packages.x86_64-linux.claw-swap-app
  - sops-encrypted secrets file with admin + host age recipients
  - Nix-built Docker image tarball for the claw-swap Hono app
affects: [phase-04-docker-services]

tech-stack:
  added: []
  patterns: [flake-module-export, sops-nix-secrets-file, buildNpmPackage, dockerTools-buildLayeredImage]

key-files:
  created:
    - /data/projects/claw-swap/flake.nix
    - /data/projects/claw-swap/flake.lock
    - /data/projects/claw-swap/.sops.yaml
    - /data/projects/claw-swap/secrets/claw-swap.yaml
    - /data/projects/claw-swap/nix/claw-swap-app.nix
    - /data/projects/claw-swap/nix/module.nix
  modified:
    - /data/projects/claw-swap/.gitignore

key-decisions:
  - "Match the proven parts flake pattern: export nixosModules.default + packages.${system}.claw-swap-app"
  - "Use sops-nix with dual recipients (admin local + acfs host) for secrets encryption/decryption"
  - "Use buildNpmPackage + dockerTools.buildLayeredImage; pass --ignore-scripts to avoid sharp postinstall fetching binaries"
  - "Add a placeholder nix/module.nix now so the flake evaluates cleanly; real module lands in 04-02"

duration: ~25min
completed: 2026-02-16
---

# Phase 4 Plan 01: Claw-Swap Flake + Secrets + Docker Image Foundation

**Shipped claw-swap as an importable flake (module + package), with sops-encrypted secrets and a Nix-built Docker image tarball that loads into Docker.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-02-16
- **Tasks:** 2 (plus 1 small follow-up lockfile commit)
- **Repos touched:** /data/projects/claw-swap

## Accomplishments

- Created `/data/projects/claw-swap/flake.nix` exporting `nixosModules.default` and `packages.x86_64-linux.claw-swap-app`
- Added `/data/projects/claw-swap/.sops.yaml` + `/data/projects/claw-swap/secrets/claw-swap.yaml` encrypted for both admin + host age keys
- Implemented `/data/projects/claw-swap/nix/claw-swap-app.nix` to build the Hono app and produce a `claw-swap:latest` Docker image tarball via Nix
- Verified:
  - `nix flake check` passes in claw-swap
  - `sops --decrypt secrets/claw-swap.yaml` outputs all 5 secrets
  - Docker image builds and `docker load < result` succeeds

## Task Commits (claw-swap repo)

1. **Task 1: Flake + sops secrets scaffold** - `29c8bd2`
2. **Follow-up: Commit flake.lock** - `4d86156`
3. **Task 2: Docker image expression + npmDepsHash** - `b16750f`

## Files Created/Modified

- `/data/projects/claw-swap/flake.nix` - Flake outputs (module + package)
- `/data/projects/claw-swap/flake.lock` - Pinned nixpkgs + sops-nix
- `/data/projects/claw-swap/.sops.yaml` - sops creation rules (admin + acfs host recipients)
- `/data/projects/claw-swap/secrets/claw-swap.yaml` - Encrypted secrets (DB password, R2 creds, World ID)
- `/data/projects/claw-swap/nix/module.nix` - Placeholder module (04-02 will fill)
- `/data/projects/claw-swap/nix/claw-swap-app.nix` - buildNpmPackage + dockerTools layered image
- `/data/projects/claw-swap/.gitignore` - Ignore `result` symlink

## Deviations From Plan

- `flake.lock` landed in its own small commit because it was initially left unstaged when committing Task 1.
- The machine has empty `NIX_PATH`; used `nix build .#claw-swap-app` for the initial npmDepsHash bootstrap, then verified a full `nix-build` run by pointing `NIX_PATH` at the flake-pinned nixpkgs source.

## Issues Encountered

- `sops --encrypt` initially failed due to a mismatched `.sops.yaml` `path_regex`; fixed to match `secrets/claw-swap.yaml`.

## Next Phase Readiness

- Ready for Phase 4 Plan 02: implement the real NixOS module (containers, networks, templates) and integrate claw-swap into agent-neurosys.

---
*Phase: 04-docker-services*
*Completed: 2026-02-16*

