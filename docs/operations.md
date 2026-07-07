# Operations

This page covers the public commands, the expected private-overlay workflow, and
the checks that should pass before you trust a change.

## Initial Setup

After cloning the repo:

1. Use the repo-local skills:
   `skills/tsurf-host-discovery`
   `skills/tsurf-overlay-authoring`
   `skills/tsurf-deploy-validation`
2. Create or update a private overlay from the discovered host facts.
3. Deploy from the private overlay:
   `./scripts/deploy.sh --node <host>`
4. Check status:
   `nix run .#tsurf-status -- <host>`
5. For repo validation and contributions, also enable hooks and run:
   `git config core.hooksPath .githooks`
   `nix flake check`
6. If you add new tracked files before running Nix evaluation again, stage them
   first. Flake evaluation only sees tracked paths.

## Private Overlay Workflow

1. Copy [`examples/private-overlay/`](../examples/private-overlay/) into a
   private repository.
2. Update the private `flake.nix` to point `tsurf.url` at the repo you want to
   import and replace all placeholder host values.
3. Run `nix run .#tsurf-init -- --overlay-dir /path/to/private-overlay` from a
   TTY to generate a real passphrase-protected root SSH key and materialize
   `modules/root-ssh.nix`. Automation should use `--passphrase-file`; an
   unencrypted key requires the explicit `--no-passphrase` flag.
4. Replace the placeholder age recipients in `.sops.yaml`, create your encrypted
   secrets file, and set `sops.defaultSopsFile` in the host config.
5. Import `modules/networking.nix` first. Import `modules/secrets.nix`, or use
   an exported `*-with-secrets` role, only after the host has the persisted
   SSH-host-key and encrypted sops file those modules expect.
6. Deploy from the private overlay with `./scripts/deploy.sh --node <host>`.
   Magic rollback is enabled by default; use `--first-deploy` for initial
   adoption when rollback cannot be used safely. Deploy-rs checks run by
   default; `--skip-checks` is an explicit unsafe fast path.

## Public Commands

| Command | Purpose |
|---------|---------|
| `nix run .#tsurf-init -- --overlay-dir /path/to/private-overlay` | Generate the root SSH key for a private overlay; prompts for a passphrase unless `--passphrase-file` or `--no-passphrase` is passed |
| `nix run .#tsurf-status -- <node\|host\|all>` | Check persistent fleet status over SSH |
| `nix run .#test-live -- --host <host>` | Run live BATS checks against a deployed host |
| `nix run .#persistence-audit` | Print the merged `/persist` manifest for the eval fixtures |
| `nix run .#nixos-anywhere -- ...` | Use the pinned `nixos-anywhere` input |
| `nix build .#vm-test-sandbox` | Run the VM sandbox smoke test (requires KVM) |
| `nix build .#vm-test-credential-proxy` | Run the VM Iron credential replacement proof (requires KVM) |

## Testing

The main validation paths in the public repo are:

- `nix flake check`
  Runs eval checks, nixfmt/deadnix gates, shellcheck coverage, and unit tests.
- `./scripts/run-tests.sh`
  Wrapper around current-system `nix flake check` plus
  `nix flake check --all-systems --no-build`; writes `.test-status`.
- `./scripts/run-tests.sh --live --host <host>`
  Runs eval checks plus live BATS tests.
- `nix run .#test-live -- --host <host> tests/live/sandbox-behavioral.bats`
  Runs the sandbox-specific live suite only.
- `nix build .#vm-test-sandbox`
  Reproducible VM-level smoke test for user and secret separation.
- `nix build .#vm-test-credential-proxy`
  VM-level proof for Iron credential replacement through the launcher and nono
  sandbox path.

The repository also ships `.github/CODEOWNERS`. Keep branch protection or a
repository ruleset enabled so normal changes land through PRs with `eval-checks`
passing; turn on CODEOWNERS review when the repo has a separate reviewer.

The hooks expect a fresh `.test-status` file in the repo root. The normal way to
produce it is `./scripts/run-tests.sh`.

## Deploy Safety

- `scripts/deploy.sh` blocks deploys from the public repo by checking for a
  private-overlay `tsurf.url` input.
- `--target user@host` overrides both the deploy-rs hostname/user and the
  SSH target used for locking and health checks.
- `TSURF_DEPLOY_SSH_OPTS_FILE` may point at a newline-delimited option file for
  SSH options that contain spaces, such as `ProxyCommand`.
- The script adds a remote lock, runs `deploy-rs`, and performs post-deploy SSH
  and service checks.
- For flaky public SSH paths, use `--mode remote-detached`. It copies the
  deploy-rs activation derivation to the target, starts the build and activation
  under `systemd-run`, and polls a host-side log. The remote unit owns lock
  cleanup and rolls back to the previous system if configured service checks
  fail after activation.
- Normal deploys should use the private-overlay script, not
  `nixos-rebuild switch`.

## Status And Recovery

- Use `nix run .#tsurf-status -- <host>` for a quick persistent-unit health
  check.
- Keep the root SSH private key out of every repo and off every target host.
- If a deploy breaks SSH, recover via console/rescue mode, repair access, and
  redeploy from the private overlay.
