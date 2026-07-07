# QUICKSTART

Start here if you are new to tsurf. The intended shape is one-owner,
self-sovereign agent infrastructure; read
[`docs/base-contract.md`](docs/base-contract.md) before adding services.

## Prerequisites

- Nix installed with flakes enabled.
- A separate private Git repository for your real hosts/secrets.

## 1) Agent-Guided Setup

Use the repo-local skills in [`skills/`](skills/) when an agent is doing the
setup work:

1. `tsurf-host-discovery`: inspect the host and classify storage/networking.
2. `tsurf-overlay-authoring`: write or update the private overlay.
3. `tsurf-deploy-validation`: validate and prepare the deploy.

This is the preferred path when the host may differ from the public examples.

## 2) Validate The Public Template

```bash
git config core.hooksPath .githooks
./scripts/run-tests.sh
```

## 3) Private Overlay

1. Copy [`examples/private-overlay/`](examples/private-overlay/) into a new private repository.
2. Replace placeholders in `flake.nix` (`tsurf.url`, hostname, `REPLACE` values).
3. Generate a real root SSH key:

```bash
nix run .#tsurf-init -- --overlay-dir .
```

Run this from a TTY to enter a root-key passphrase. For automation, pass
`--passphrase-file <path>` or make the unencrypted-key risk explicit with
`--no-passphrase`.

If you run initialization on the target host, add `--age` to derive a sops age identity from the persisted SSH host key.

Full template walkthrough: [`examples/private-overlay/README.md`](examples/private-overlay/README.md)

## 4) Configure secrets (sops-nix)

1. Replace placeholder age recipients in `.sops.yaml`.
2. Create a host secrets file (for example `secrets/example.yaml`) and encrypt it with `sops`.
3. Import host networking/secrets modules in your private overlay after SSH host key persistence is configured.

## 5) First deploy

```bash
./scripts/deploy.sh --node example --first-deploy
```

## 6) Enable extras (opt-in)

Extras are opt-in in private overlays: import the module you want and set its enable option explicitly.
Reference: [`docs/extras.md`](docs/extras.md)

Headscale and Harmonia cache are core base modules, but they still need private
overlay settings for domains, keys, ACLs, and allowlists before deployment.

## Next Steps

- Security model: [`SECURITY.md`](SECURITY.md)
- System design: [`docs/architecture.md`](docs/architecture.md)
- Public/private base contract: [`docs/base-contract.md`](docs/base-contract.md)
