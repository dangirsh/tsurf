# Operations

This page covers the public commands, the expected private-overlay workflow, and
the checks that should pass before you trust a change.

## Initial Setup

After cloning the repo:

1. For the shortest path onto an existing NixOS host:
   `./tsurf init root@your-server`
2. Deploy:
   `./tsurf deploy`
3. Check status:
   `./tsurf status`
4. Open an SSH session or run a remote command with the saved target:
   `./tsurf ssh`
   `./tsurf ssh journalctl -u sshd -n 50`
5. For repo validation and contributions, also enable hooks and run:
   `git config core.hooksPath .githooks`
   `nix flake check`
6. If you add new tracked files before running Nix evaluation again, stage them
   first. Flake evaluation only sees tracked paths.

## Private Overlay Workflow

The quickstart wrapper hides the private-overlay details by generating a local
overlay under `.tsurf/overlay/`. For long-lived/production deployments, the
intended explicit workflow is still:

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
| `./tsurf init root@host` | Generate a local quickstart overlay, root SSH key, and saved config |
| `./tsurf deploy` | Deploy the generated quickstart overlay with the saved defaults |
| `./tsurf status` | Check persistent fleet status for the saved node |
| `./tsurf ssh [command]` | SSH to the saved target or run a one-off remote command |
| `./tsurf config` | Print the saved quickstart defaults |
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

- `./tsurf deploy` always deploys from the generated local overlay, not directly
  from the public repo root.
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
