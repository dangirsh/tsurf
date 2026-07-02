# Security Model

This document describes the security properties the public repo implements today.
Private overlays can strengthen or weaken them.

## Reporting Vulnerabilities

Please use GitHub Security Advisories for private vulnerability reports when
available. If that is unavailable, open a minimal public issue asking for a
private reporting channel and do not include exploit details, secrets, or host
identifiers in the issue.

## Scope

- The public flake exports only `eval-*` fixtures plus apps, checks, and test
  helpers. It does not export `deploy.nodes`.
- [`scripts/deploy.sh`](scripts/deploy.sh) refuses to deploy unless the current
  flake has a `tsurf.url` input, so the public repo is intentionally
  non-deployable.
- [`hosts/dev/default.nix`](hosts/dev/default.nix) is the sandboxed agent host:
  it enables `agentCompute`, `agentLauncher`, `agentEgressProxy`,
  `agentSandbox`, and `nonoSandbox`.
- [`hosts/services/default.nix`](hosts/services/default.nix) is the service host:
  it omits the sandbox modules and imports only `extras/restic.nix`, which stays
  disabled by default.
- The public repo does not ship file sync, unattended-agent orchestration, or a
  default home-manager profile for the agent user.

## Principals And Privileges

| Identity | Default groups | Purpose |
| --- | --- | --- |
| `root` | n/a | operator, deploy, secrets, recovery |
| `agent` | `users` | sandboxed agent execution |

Important properties:

- The `agent` user is not in `wheel`.
- Build-time assertions keep the `agent` user out of `docker`.
- `users.mutableUsers = false`.
- Sudo access is limited to immutable per-agent launchers such as
  `tsurf-launch-claude`.
- Base Nix daemon policy is `allowed-users = [ "root" "<agent>" ]` and
  `trusted-users = [ "root" ]`, so the agent can use Nix but cannot extend the
  trust root.
- `tsurf.template.allowUnsafePlaceholders` exists only for eval fixtures. Real
  host source files do not set it.

## Brokered Launch Path

On sandboxed hosts, wrappers follow this path:

```text
caller
  -> wrapper
    -> sudo tsurf-launch-<agent>
      -> systemd-run transient unit
        -> scripts/agent-wrapper.sh
          -> nono run --profile /etc/nono/profiles/tsurf-<name>.json
            -> setpriv drop to the configured agent user
              -> real agent binary
                -> iron-proxy on loopback (credential replacement and egress policy)
```

The legacy `nono` credential-proxy path remains available per agent via
`credentialProxy = "nono"` and is still covered by the VM credential-proxy test.

Security properties of that path:

- `security.sudo.extraRules` exposes only immutable launchers. There is no
  generic root helper.
- The launcher bakes in the real binary path, the nono profile path, and the
  credential secret pairs.
- The launcher rejects any real binary outside `/nix/store`.
- Launch events go to journald only (`journalctl -t agent-launch`).
- The public path has no `--no-sandbox` or `AGENT_ALLOW_NOSANDBOX` escape hatch.

Verification status:

- Eval checks verify the wrapper, profile, and `env://` credential wiring.
- The repo includes a VM fake-provider test that exercises the brokered
  request path and proves the child does not receive the real provider key.

Resource limits:

- Shared slice: `MemoryMax = 8G`, `CPUQuota = 300%`, `TasksMax = 1024`
- Per transient session: `MemoryMax = 4G`, `CPUQuota = 200%`, `TasksMax = 256`

## Filesystem Boundary

The sandbox is implemented with `nono` and Landlock-backed filesystem rules.

Enforced behavior:

- `$PWD` must be inside `services.agentLauncher.projectRoot`
  (default `/data/projects`).
- The wrapper derives the sandbox read scope as the first path component beneath
  that project root, so `/data/projects/foo/subdir` is scoped to
  `/data/projects/foo`.
- The wrapper refuses to run if `$PWD` is exactly the project root. This
  prevents blanket read access to all workspaces under `/data/projects`.
- The base nono profile denies `/run/secrets`, `~/.ssh`, `~/.bash_history`,
  `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.docker`, `~/.npmrc`, `~/.pypirc`,
  `~/.gem`, `~/.config/gh`, `~/.git-credentials`, and `/etc/nono`.

Important nuance:

- The current workspace is still writable. `workdir.access = "readwrite"` is a
  deliberate design choice.
- What is blocked is broad cross-workspace access, not writes inside the current
  workspace.
- Avoid pointing agents at infrastructure repos. That is still an operational
  rule, not a technical control.

## Secrets And Credential Flow

Storage:

- `sops-nix` derives its age identity from the host SSH ed25519 key.
- Secrets are decrypted to `/run/secrets`.
- Public defaults keep brokered provider keys root-owned:
  `anthropic-api-key`, `openai-api-key`, `xai-api-key`, and
  `openrouter-api-key`.
- `github-pat` and `google-api-key` default to the agent user.
- Optional Restic/B2 backup secrets are declared by `extras/restic.nix` only
  when `services.resticStarter.enable = true`; they are not part of the core
  secrets module.

Injection model:

- Each wrapper carries an `AGENT_CREDENTIAL_SECRETS` allowlist of
  `ENV_VAR:secret-file-name` pairs.
- Iron-backed agents do not read those files in the wrapper. They receive
  provider-shaped placeholder credentials and explicit proxy/CA environment
  variables. `iron-proxy` reads real provider keys from a sops-rendered
  environment file and replaces placeholders at egress.
- Legacy `nono` credential-proxy agents read only the named secret files from
  `/run/secrets`. nono's per-agent profile defines `custom_credentials` with
  `env://` URIs, reads the real keys from the parent env before applying the
  sandbox, starts its built-in reverse proxy with 256-bit phantom tokens, and
  strips real keys from the child environment for supported wrapper paths.

For Iron-backed wrapper paths, the child should get:

- provider-shaped placeholder variables such as `ANTHROPIC_API_KEY`
- `HTTP_PROXY` / `HTTPS_PROXY` pointing at the loopback Iron tunnel listener
- CA trust variables scoped to the child environment

For legacy `nono` credential-proxy wrapper paths, the child should get:

- a per-session phantom token via `NONO_PROXY_TOKEN`
- a localhost base URL such as `ANTHROPIC_BASE_URL=http://127.0.0.1:<port>/anthropic`

For supported wrapper paths, the child should not get:

- the raw `/run/secrets/*` file
- the raw provider key in its environment

## Network Boundary

- nftables is enabled.
- Public ingress is limited to `22`, plus `80` and `443` only when
  `services.nginx.enable = true`.
- Cloud metadata access to `169.254.169.254` and `fd00:ec2::254` is dropped in
  nftables.
- The effective trusted interface set in the public eval fixtures is loopback only.

SSH defaults:

- key-only auth
- `PermitRootLogin = prohibit-password`
- ed25519 host key only
- `PasswordAuthentication = false`
- `KbdInteractiveAuthentication = false`
- `MaxAuthTries = 3`
- `fail2ban` disabled

These SSH and firewall defaults are set explicitly in `modules/networking.nix`.
`srvos` also sets them; the explicit declarations ensure the security model is
self-backing.

Agent egress:

- When `services.agentEgressProxy.enable = true`, direct agent-UID egress is
  mediated-only: nftables allows loopback proxy ports and drops direct DNS and
  public `22/80/443` from the agent UID. `iron-proxy` enforces host allowlists,
  credential replacement, upstream deny CIDRs, and structured per-request logs.
- The dev fixture enables this Iron-backed mode by default.
- The base `nono` profile sets `network.block = true`. Iron-backed generated
  profiles disable nono network blocking so the child can reach only the
  host-allowed loopback proxy ports. Legacy `nono` credential-proxy wrappers
  still get nono reverse-proxy routes for configured providers, and arbitrary
  CONNECT traffic through nono's root-side proxy is strict-filtered.
- Host egress for direct agent-UID traffic is enforced in nftables by
  `meta skuid`. Drops are logged by default with `tsurf-agent-egress-*`
  prefixes before being dropped.
- Default allowed traffic for the agent UID in legacy direct-egress mode is:
  - loopback TCP ports `20000-20199`, reserved for per-launch nono credential
    proxies
  - DNS on TCP/UDP `53`
  - TCP `22`, `80`, and `443`
- Default denied traffic for the agent UID includes:
  - other loopback TCP ports unless explicitly added to
    `tsurf.agentEgress.allowedLoopbackTCPPorts`
  - RFC1918 IPv4 ranges
  - `100.64.0.0/10`
  - `169.254.0.0/16`
  - `fc00::/7`
  - `fe80::/10`

Iron-backed mode is the preferred destination-level mediation path. Private
overlays that disable `services.agentEgressProxy`, enable
`services.nonoSandbox.allowDirectNetwork`, or add direct egress paths must treat
that as an explicit risk.

## Persistence, Deploy, And Recovery

- The root filesystem rolls back on boot from BTRFS subvolumes.
- Persistent state is declared explicitly under `/persist`.
- Persisted security-critical state includes `/var/lib/nixos`,
  `/persist/etc/ssh/ssh_host_ed25519_key`, `/data/projects`, selected root state, and
  selected agent state.
- [`modules/impermanence.nix`](modules/impermanence.nix) makes `setupSecrets`
  depend on `persist-files`, so `sops-nix` can read the persisted SSH host key.
- Real deployments are expected to generate a root SSH key with
  `nix run .#tsurf-init -- --overlay-dir /path/to/private-overlay`.
  The helper prompts for a passphrase on a TTY; noninteractive generation must
  use `--passphrase-file` or explicitly accept the unencrypted-key risk with
  `--no-passphrase`.
- If SSH is lost, recover through console or rescue mode, repair access, and
  redeploy from the private overlay.
- Deploys run deploy-rs checks by default. The `--skip-checks` flag is an
  explicit unsafe fast path for emergencies or known-good out-of-band checks.

## Supply Chain

- Nix inputs are pinned by `flake.lock`.
- A scheduled GitHub Actions workflow opens lock-update pull requests so input
  bumps are reviewed explicitly instead of accumulating silently.
- The public base trusts `https://cache.numtide.com` via the configured
  `niks3.numtide.com-1` public key. Treat that cache as part of the build trust
  root for binaries it serves.
- `nono` is built from pinned source (`rustPlatform.buildRustPackage`).
  The build runs bounded tests for tsurf's carried `env://` credential patch
  and the removed broad `/run` default-policy grants, plus an install-time CLI
  smoke check. Patch files live under `packages/` and should be reviewed when
  upstream nono is updated.
- `iron-proxy` is built from pinned source (`buildGoModule`). Its install check
  verifies the reported version and CA generation command.
  Remaining prebuilt binaries are SHA256-pinned. `cass` is an opt-in extra
  (`extras/cass.nix`), not in the default trust path.
- Critical kernel and network hardening (kexec, BPF, sysrq, reverse-path
  filtering, source routing) is set explicitly in `modules/base.nix`.
  `nix-mineral` provides additional depth (~80 settings) but the core claims
  in this document do not depend on it staying enabled.
- Firewall, SSH password auth, keyboard-interactive auth, and X11 forwarding
  defaults are set explicitly in `modules/networking.nix`. `srvos` also sets
  them; the explicit declarations are the trust anchor.
- `claude-code` and `codex` come from the pinned `llm-agents.nix` input.
- The repo does not add signature verification for these remaining prebuilt
  binaries.
- The optional Harmonia cache client defaults to HTTPS URLs. Plain HTTP clients
  or direct public server exposure require `allowInsecureHttp = true`.
  Integrity still relies on Nix nar signatures, but HTTP metadata and
  availability can be observed or interfered with by the network path.

## Verification

The security claims above are backed by eval checks plus VM and live tests.

Eval-time checks:

- [`tests/eval/config-checks.nix`](tests/eval/config-checks.nix)
  covers public-output safety, placeholder isolation, firewall exposure,
  root-key requirements, Nix daemon restrictions, sandbox structure, launcher
  hardening, and root-side credential broker structure.

Runtime checks:

- [`tests/live/security.bats`](tests/live/security.bats)
  verifies SSH hardening, metadata blocking, and firewall exposure.
- [`tests/live/secrets.bats`](tests/live/secrets.bats)
  verifies `/run/secrets` presence, ownership, and permissions.
- [`tests/live/networking.bats`](tests/live/networking.bats)
  verifies DNS reachability, metadata blocking, and the egress allowlist.
- [`tests/live/sandbox-behavioral.bats`](tests/live/sandbox-behavioral.bats)
  probes the sandbox from inside the agent context.
- [`tests/live/agent-sandbox.bats`](tests/live/agent-sandbox.bats)
  is structural coverage for wrapper contents, not full behavioral proof.
- [`tests/live/service-health.bats`](tests/live/service-health.bats)
  verifies persistent unit health when those units exist.
- [`tests/live/impermanence.bats`](tests/live/impermanence.bats)
  verifies `/persist` and related persistence behavior.
- [`tests/vm/sandbox-behavioral.nix`](tests/vm/sandbox-behavioral.nix)
  is the reproducible VM smoke test.
- [`tests/vm/credential-proxy.nix`](tests/vm/credential-proxy.nix)
  proves a brokered fake-provider request keeps the raw provider key out of the
  child environment while the upstream receives the injected header.

## Accepted Risks

- The service-host role does not include the agent sandbox.
- The sandbox does not make the current workspace immutable.
- The public repo deliberately avoids a separate unattended-agent supervisor.
- The host-level egress allowlist is coarse by design. It is scoped by UID, not
  by individual wrapper or destination hostname.
- Private overlays can weaken the network model by enabling
  `services.nonoSandbox.allowDirectNetwork` or adding broad direct egress.
- The persisted SSH host key at `/persist/etc/ssh/ssh_host_ed25519_key` is
  plaintext on disk unless the private overlay adds disk encryption. That key is
  also the default sops age identity, so compromise affects both SSH host
  identity and secret decryption.
- Operator root SSH keys generated with `tsurf-init --no-passphrase` are
  intentionally unencrypted. Prefer the interactive prompt or
  `--passphrase-file`.
- The public disk layout does not enable full-disk encryption by default.
- Harmonia cache clients trust the configured signing key; incorrect or
  over-broad cache trust can freeze, roll back, or leak build provenance through
  served paths even when Nix signature checks hold.
