# QUICKSTART

Start here if you are new to tsurf. There are three paths:

1. Agent-guided host discovery and private-overlay authoring
2. Fast compatibility setup onto an existing NixOS server
3. Full private-overlay setup for production deployments

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

## 2) Compatibility Path: Existing NixOS Server

```bash
git clone <your-fork-or-upstream-url> tsurf
cd tsurf
./tsurf init root@your-server
./tsurf deploy
./tsurf status
./tsurf ssh
```

This path generates an ignored local overlay under `.tsurf/overlay/` plus a
saved config in `.tsurf/config`. `tsurf init` SSH-probes the target host first,
verifies it is NixOS, and reuses the host's current hostname and release as the
defaults. It is meant for quickly testing tsurf against a vanilla NixOS box
that already allows root SSH access.

Useful variations:

```bash
./tsurf init root@your-server --name lab
./tsurf deploy --fast
./tsurf config
./tsurf ssh journalctl -u sshd -n 50
```

## 3) Validate The Public Template

```bash
git config core.hooksPath .githooks
nix flake check
```

## 4) Full Private Overlay

1. Copy [`examples/private-overlay/`](examples/private-overlay/) into a new private repository.
2. Replace placeholders in `flake.nix` (`tsurf.url`, hostname, `REPLACE` values).
3. Generate a real root SSH key:

```bash
nix run .#tsurf-init -- --overlay-dir .
```

If you run initialization on the target host, add `--age` to derive a sops age identity from the persisted SSH host key.

Full template walkthrough: [`examples/private-overlay/README.md`](examples/private-overlay/README.md)

## 5) Configure secrets (sops-nix)

1. Replace placeholder age recipients in `.sops.yaml`.
2. Create a host secrets file (for example `secrets/example.yaml`) and encrypt it with `sops`.
3. Import host networking/secrets modules in your private overlay after SSH host key persistence is configured.

## 6) First deploy (from private overlay)

```bash
./scripts/deploy.sh --node example --first-deploy
```

## 7) Enable extras (opt-in)

Extras are opt-in in private overlays: import the module you want and set its enable option explicitly.
Reference: [`docs/extras.md`](docs/extras.md)

## Next Steps

- Security model: [`SECURITY.md`](SECURITY.md)
- System design: [`docs/architecture.md`](docs/architecture.md)
