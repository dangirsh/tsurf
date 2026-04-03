# Security Model

This document describes the security properties the public repo implements today.
Private overlays can strengthen or weaken them.

## Scope

- The public flake exports only `eval-*` fixtures plus apps, checks, and test
  helpers. It does not export `deploy.nodes`.
- [`scripts/deploy.sh`](scripts/deploy.sh) refuses to deploy unless the current
  flake has a `tsurf.url` input, so the public repo is intentionally
  non-deployable.
- [`hosts/dev/default.nix`](hosts/dev/default.nix) is the sandboxed agent host:
  it enables `agentCompute`, `agentLauncher`, `agentSandbox`, and `nonoSandbox`.
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
        -> scripts/agent-wrapper.sh (loads /run/secrets/* into env vars)
          -> nono run --credential <service> --profile /etc/nono/profiles/tsurf-<name>.json
            -> nono's built-in reverse proxy (reads env:// URIs, issues phantom tokens)
            -> setpriv drop to the configured agent user
              -> real agent binary
```

Security properties of that path:

- `security.sudo.extraRules` exposes only immutable launchers. There is no
  generic root helper.
- The launcher bakes in the real binary path, the nono profile path, and the
  credential secret pairs.
- The launcher rejects any real binary outside `/nix/store`.
- Launch events go to journald only (`journalctl -t agent-launch`).
- The public path has no `--no-sandbox` or `AGENT_ALLOW_NOSANDBOX` escape hatch.

Resource limits:

- Shared slice: `MemoryMax = 8G`, `CPUQuota = 300%`, `TasksMax = 1024`
- Per transient session: `MemoryMax = 4G`, `CPUQuota = 200%`, `TasksMax = 256`

## Filesystem Boundary

The sandbox is implemented with `nono` and Landlock-backed filesystem rules.

Enforced behavior:

- `$PWD` must be inside `services.agentLauncher.projectRoot`
  (default `/data/projects`).
- `$PWD` must be inside a Git worktree.
- The wrapper resolves the Git toplevel with `git rev-parse --show-toplevel`
  and grants read access to that repo root.
- The wrapper refuses to run if the Git toplevel is exactly the project root.
  This prevents blanket read access to all repos under `/data/projects`.
- The base nono profile denies `/run/secrets`, `~/.ssh`, `~/.bash_history`,
  `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.docker`, `~/.npmrc`, `~/.pypirc`,
  `~/.gem`, `~/.config/gh`, `~/.git-credentials`, and `/etc/nono`.

Important nuance:

- The current worktree is still writable. `workdir.access = "readwrite"` is a
  deliberate design choice.
- What is blocked is broad cross-repo access, not writes inside the current repo.
- Avoid pointing agents at infrastructure repos. That is still an operational
  rule, not a technical control.

## Secrets And Credential Flow

Storage:

- `sops-nix` derives its age identity from the host SSH ed25519 key.
- Secrets are decrypted to `/run/secrets`.
- Public defaults keep `anthropic-api-key` and `openai-api-key` root-owned.
- `github-pat`, `google-api-key`, `xai-api-key`, and `openrouter-api-key`
  default to the agent user.

Injection model:

- Each wrapper carries an `AGENT_CREDENTIAL_SECRETS` allowlist of
  `ENV_VAR:secret-file-name` pairs.
- [`scripts/agent-wrapper.sh`](scripts/agent-wrapper.sh) reads only those named
  secret files from `/run/secrets` and exports them as environment variables.
- nono's per-agent profile defines `custom_credentials` with `env://` URIs.
  nono reads the real keys from the parent env before applying the sandbox,
  starts its built-in reverse proxy with 256-bit phantom tokens, and strips
  real keys from the child environment.

What the child gets:

- a per-session phantom token via `NONO_PROXY_TOKEN`
- a localhost base URL such as `ANTHROPIC_BASE_URL=http://127.0.0.1:<port>/anthropic`

What the child does not get:

- the raw `/run/secrets/*` file
- the raw provider key in its environment

## Network Boundary

- nftables is enabled.
- Public ingress is limited to `22`, plus `80` and `443` only when
  `services.nginx.enable = true`.
- Cloud metadata access to `169.254.169.254` is dropped in nftables.
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

- `nono` is not the network allowlist boundary here; `network.block = false`.
- Agent egress is enforced in nftables by `meta skuid`.
- Default allowed traffic for the agent UID is:
  - loopback
  - DNS on TCP/UDP `53`
  - TCP `22`, `80`, and `443`
- Default denied traffic for the agent UID includes:
  - RFC1918 IPv4 ranges
  - `100.64.0.0/10`
  - `169.254.0.0/16`
  - `fc00::/7`
  - `fe80::/10`

## Persistence, Deploy, And Recovery

- The root filesystem rolls back on boot from BTRFS subvolumes.
- Persistent state is declared explicitly under `/persist`.
- Persisted security-critical state includes `/var/lib/nixos`,
  `/etc/ssh/ssh_host_ed25519_key`, `/data/projects`, selected root state, and
  selected agent state.
- [`modules/impermanence.nix`](modules/impermanence.nix) makes `setupSecrets`
  depend on `persist-files`, so `sops-nix` can read the persisted SSH host key.
- Real deployments are expected to generate a root SSH key with
  `nix run .#tsurf-init -- --overlay-dir /path/to/private-overlay`.
- If SSH is lost, recover through console or rescue mode, repair access, and
  redeploy from the private overlay.

## Supply Chain

- Nix inputs are pinned by `flake.lock`.
- Prebuilt binaries are SHA256-pinned, including `nono`. `cass` is an opt-in
  extra (`extras/cass.nix`), not in the default trust path.
- Critical kernel and network hardening (kexec, BPF, sysrq, reverse-path
  filtering, source routing) is set explicitly in `modules/base.nix`.
  `nix-mineral` provides additional depth (~80 settings) but the core claims
  in this document do not depend on it staying enabled.
- Firewall, SSH password auth, keyboard-interactive auth, and X11 forwarding
  defaults are set explicitly in `modules/networking.nix`. `srvos` also sets
  them; the explicit declarations are the trust anchor.
- `nix-mineral` targets nixpkgs-unstable. A compatibility shim stubs
  `services.resolved.settings` for nixos-25.11. This shim is annotated with
  `@decision SEC-160-04` in `flake.nix`.
- `claude-code` and `codex` come from the pinned `llm-agents.nix` input.
- The repo does not add signature verification for these prebuilt binaries.

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

## Accepted Risks

- The service-host role does not include the agent sandbox.
- The sandbox does not make the current workspace immutable.
- The public repo deliberately avoids a separate unattended-agent supervisor.
- The host-level egress allowlist is coarse by design. It is scoped by UID, not
  by individual wrapper or destination hostname.
- Optional extras can widen access. Notably,
  `services.costTracker.enable` grants a DynamicUser service read-only
  `/run/secrets` access plus `CAP_DAC_READ_SEARCH`.
