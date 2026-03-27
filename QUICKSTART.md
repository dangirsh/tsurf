# QUICKSTART

Start here if you are new to tsurf. There are two paths:

1. Fast quickstart onto an existing NixOS server
2. Full private-overlay setup for production deployments

## Prerequisites

- Nix installed with flakes enabled.
- A separate private Git repository for your real hosts/secrets.

## 1) Fastest Path: Existing NixOS Server

```bash
git clone <your-fork-or-upstream-url> tsurf
cd tsurf
./tsurf init root@your-server
./tsurf deploy
./tsurf status
```

This path generates an ignored local overlay under `.tsurf/overlay/` plus a
saved config in `.tsurf/config`. It is meant for quickly testing tsurf against a
vanilla NixOS box that already allows root SSH access.

Useful variations:

```bash
./tsurf init root@your-server --name lab
./tsurf deploy --fast
./tsurf config
```

## 2) Validate The Public Template

```bash
git config core.hooksPath .githooks
nix flake check
```

## 3) Full Private Overlay

1. Copy [`examples/private-overlay/`](examples/private-overlay/) into a new private repository.
2. Replace placeholders in `flake.nix` (`tsurf.url`, hostname, `REPLACE` values).
3. Generate a real root SSH key:

```bash
nix run .#tsurf-init -- --overlay-dir .
```

If you run initialization on the target host, add `--age` to derive a sops age identity from the persisted SSH host key.

Full template walkthrough: [`examples/private-overlay/README.md`](examples/private-overlay/README.md)

## 4) Configure secrets (sops-nix)

1. Replace placeholder age recipients in `.sops.yaml`.
2. Create a host secrets file (for example `secrets/example.yaml`) and encrypt it with `sops`.
3. Import host networking/secrets modules in your private overlay after SSH host key persistence is configured.

## 5) First deploy (from private overlay)

```bash
./scripts/deploy.sh --node example --first-deploy
```

## 6) Enable extras (opt-in)

Extras are opt-in in private overlays: import the module you want and set its enable option explicitly.
Reference: [`docs/extras.md`](docs/extras.md)

## Next Steps

- Security model: [`SECURITY.md`](SECURITY.md)
- System design: [`docs/architecture.md`](docs/architecture.md)
