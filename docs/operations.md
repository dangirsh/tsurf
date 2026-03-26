# Operations

This page covers the public commands, the expected private-overlay workflow, and
the checks that should pass before you trust a change.

## Initial Setup

After cloning the repo:

1. Enable the project hooks:
   `git config core.hooksPath .githooks`
2. Run the public eval checks:
   `nix flake check`
3. If you add new tracked files before running Nix evaluation again, stage them
   first. Flake evaluation only sees tracked paths.

## Private Overlay Workflow

The public repo is not deployable by design. The intended workflow is:

1. Copy [`examples/private-overlay/`](../examples/private-overlay/) into a
   private repository.
2. Update the private `flake.nix` to point `tsurf.url` at the repo you want to
   import and replace all placeholder host values.
3. Run `nix run .#tsurf-init -- --overlay-dir /path/to/private-overlay` to
   generate a real root SSH key and materialize `modules/root-ssh.nix`.
4. Replace the placeholder age recipients in `.sops.yaml`, create your encrypted
   secrets file, and set `sops.defaultSopsFile` in the host config.
5. Import `modules/networking.nix` and `modules/secrets.nix` only after the host
   has the networking and persisted SSH-host-key setup those modules expect.
6. Deploy from the private overlay with `./scripts/deploy.sh --node <host>`.
   Use `--first-deploy` for initial migration when you need magic rollback
   disabled.

## Public Commands

| Command | Purpose |
|---------|---------|
| `nix run .#tsurf-init -- --overlay-dir /path/to/private-overlay` | Generate the root SSH key for a private overlay and optionally derive an age key with `--age` |
| `nix run .#tsurf-status -- <node\|host\|all>` | Check persistent fleet status over SSH |
| `nix run .#test-live -- --host <host>` | Run live BATS checks against a deployed host |
| `nix run .#persistence-audit` | Print the merged `/persist` manifest for the eval fixtures |
| `nix run .#nixos-anywhere -- ...` | Use the pinned `nixos-anywhere` input |
| `nix build .#vm-test-sandbox` | Run the VM sandbox smoke test (requires KVM) |

## Testing

The main validation paths in the public repo are:

- `nix flake check`
  Runs eval checks, shellcheck coverage, and unit tests.
- `./scripts/run-tests.sh`
  Wrapper around `nix flake check`; writes `.test-status` for the git hooks.
- `./scripts/run-tests.sh --live --host <host>`
  Runs eval checks plus live BATS tests.
- `nix run .#test-live -- --host <host> tests/live/sandbox-behavioral.bats`
  Runs the sandbox-specific live suite only.
- `nix build .#vm-test-sandbox`
  Reproducible VM-level smoke test for user and secret separation.

The hooks expect a fresh `.test-status` file in the repo root. The normal way to
produce it is `./scripts/run-tests.sh`.

## Deploy Safety

- `scripts/deploy.sh` blocks deploys from the public repo by checking for a
  private-overlay `tsurf.url` input.
- The script adds a remote lock, runs `deploy-rs`, and performs post-deploy SSH
  and service checks.
- Normal deploys should use the private-overlay script, not
  `nixos-rebuild switch`.

## Status And Recovery

- Use `nix run .#tsurf-status -- <host>` for a quick persistent-unit health
  check.
- Keep the root SSH private key out of every repo and off every target host.
- If a deploy breaks SSH, recover via console/rescue mode, repair access, and
  redeploy from the private overlay.
