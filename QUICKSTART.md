# Quickstart

Use `tsurf` as a public base plus a private overlay. The public repo does not
deploy real hosts.

## Prerequisites

- Nix with flakes enabled.
- A private Git repo for real hosts, secrets, domains, and app config.

## 1. Create A Private Overlay

```bash
cp -R examples/private-overlay /path/to/private-tsurf
cd /path/to/private-tsurf
```

Edit the copied files:

- point `tsurf.url` at the public base you want to use
- replace `REPLACE` placeholders
- add real host hardware, disks, IPs, and DNS

## 2. Initialize Root SSH

```bash
nix run /path/to/tsurf#tsurf-init -- --overlay-dir .
```

Use a TTY so the helper can prompt for a passphrase. For automation, use
`--passphrase-file <path>`. Use `--no-passphrase` only when you explicitly
accept an unencrypted root key.

## 3. Configure Secrets

1. Replace placeholder age recipients in `.sops.yaml`.
2. Create and encrypt the host secrets file with `sops`.
3. Import secret modules only after the host has persisted SSH host keys and a
   real encrypted sops file.

## 4. Deploy From The Overlay

```bash
./scripts/deploy.sh --node <node> --first-deploy
```

After first adoption, normal deploys are:

```bash
./scripts/deploy.sh --node <node>
```

## Agent-Guided Setup

When an agent is doing the setup work, use the repo-local skills:

- `tsurf-host-discovery`
- `tsurf-overlay-authoring`
- `tsurf-deploy-validation`

## Public Repo Validation

```bash
git config core.hooksPath .githooks
./scripts/run-tests.sh
```

## Next

- Boundary: [`docs/base-contract.md`](docs/base-contract.md)
- Example overlay: [`examples/private-overlay/`](examples/private-overlay/)
- Operations: [`docs/operations.md`](docs/operations.md)
- Security: [`SECURITY.md`](SECURITY.md)
