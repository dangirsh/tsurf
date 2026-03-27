# QUICKSTART

Start here if you are new to tsurf. This covers both paths:

1. Validate the public template
2. Bootstrap a private overlay for real deployments

## Prerequisites

- Nix installed with flakes enabled.
- A separate private Git repository for your real hosts/secrets.

## 1) Explore the public template

```bash
git clone <your-fork-or-upstream-url> tsurf
cd tsurf
git config core.hooksPath .githooks
nix flake check
```

This validates the public fixtures only. Real deploys are intentionally blocked in the public repo.

## 2) Create your private overlay

1. Copy [`examples/private-overlay/`](examples/private-overlay/) into a new private repository.
2. Replace placeholders in `flake.nix` (`tsurf.url`, hostname, `REPLACE` values).
3. Generate a real root SSH key:

```bash
nix run .#tsurf-init -- --overlay-dir .
```

If you run initialization on the target host, add `--age` to derive a sops age identity from the persisted SSH host key.

Full template walkthrough: [`examples/private-overlay/README.md`](examples/private-overlay/README.md)

## 3) Configure secrets (sops-nix)

1. Replace placeholder age recipients in `.sops.yaml`.
2. Create a host secrets file (for example `secrets/example.yaml`) and encrypt it with `sops`.
3. Import host networking/secrets modules in your private overlay after SSH host key persistence is configured.

## 4) First deploy (from private overlay)

```bash
./scripts/deploy.sh --node example --first-deploy
```

## 5) Enable extras (opt-in)

Extras are opt-in in private overlays: import the module you want and set its enable option explicitly.
Reference: [`docs/extras.md`](docs/extras.md)

## Next Steps

- Security model: [`SECURITY.md`](SECURITY.md)
- System design: [`docs/architecture.md`](docs/architecture.md)
