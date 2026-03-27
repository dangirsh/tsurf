# CLAUDE.md - tsurf

This repo is the public `tsurf` core: eval fixtures, reusable modules, test
helpers, and the example private overlay.

## Layout

```text
flake.nix                    # Public outputs: eval fixtures, apps, checks
hosts/{dev,services}/        # Public example hosts
modules/                     # Core NixOS modules
extras/                      # Optional overlay modules
scripts/                     # Bootstrap, deploy, test, and status helpers
tests/                       # Eval, VM, live, and unit coverage
examples/private-overlay/    # Forkable starting point for a real deployment
```

Important current truths:

- Public outputs are `eval-*` only. There are no public `deploy.nodes`.
- `hosts/dev` is the sandboxed agent fixture.
- `hosts/services` is the unsandboxed service-host fixture.
- No public fixture enables CASS, Codex, cost tracking, or a home-manager
  profile by default.
- The example private overlay imports `extras/cass.nix`, but still leaves it disabled.

## Editing Rules

- Keep host imports explicit.
- Prefer editing an existing module over creating a new one for a small change.
- Keep secrets in `modules/secrets.nix` or an overlay secrets module, never in
  committed plaintext.
- Preserve `@decision` annotations on security-relevant modules.
- Use `tmp/` in the repo root for temporary files.
- Do not rewrite the README introduction above `## Quick Start`. Only make small
  correctness fixes there when necessary.

## Security Rules

- Do not weaken the public sandbox path in `modules/nono.nix`,
  `modules/agent-launcher.nix`, `modules/agent-sandbox.nix`, or
  `scripts/agent-wrapper.sh`.
- Do not add a public `--no-sandbox` path.
- Do not put the agent user in `wheel` or `docker`.
- Do not expose new public ports casually. Keep public ingress limited to the
  policy in `modules/networking.nix`.
- Do not embed credentials in URLs, command lines, or committed files.

See [`SECURITY.md`](SECURITY.md) for the current security model.

## Testing

Before finishing a change:

```bash
git config core.hooksPath .githooks
git add <new-files>
nix flake check
./scripts/run-tests.sh
```

Additional coverage when relevant:

- `nix build .#vm-test-sandbox`
- `nix run .#test-live -- --host <host>`
- `nix run .#test-live -- --host <host> tests/live/sandbox-behavioral.bats`

`./scripts/run-tests.sh` writes `.test-status`, which the local guard expects.

## Deploy Model

- Real deploys happen from a private overlay, not from this repo.
- The public [`scripts/deploy.sh`](scripts/deploy.sh) exists as a guarded helper
  and refuses to deploy without a private-overlay `tsurf.url` input.
- The example private overlay does not copy that helper automatically. If you
  want it there, vendor it into the overlay deliberately.

## Docs

Keep these files in sync with the implementation:

- [`README.md`](README.md)
- [`QUICKSTART.md`](QUICKSTART.md)
- [`docs/architecture.md`](docs/architecture.md)
- [`docs/operations.md`](docs/operations.md)
- [`docs/extras.md`](docs/extras.md)
- [`SECURITY.md`](SECURITY.md)
- [`examples/private-overlay/README.md`](examples/private-overlay/README.md)
