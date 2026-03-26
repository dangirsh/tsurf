# Security Model

This document describes the security properties that this repository actually
implements today. It is about the public repo as shipped. Private overlays can
strengthen or weaken these properties, so host-specific statements are called out.

## Scope

- The public flake exports only eval fixtures:
  `eval-services`, `eval-dev`, and `eval-dev-alt-agent`.
- The public flake exports no `deploy.nodes`; all exported
  `nixosConfigurations` are prefixed with `eval-`.
- [`scripts/deploy.sh`](scripts/deploy.sh)
  refuses to deploy unless it is being run from a private overlay flake that
  contains a `tsurf.url` input.
- The public repo does not ship a file-sync module. Sync topology and exposure
  policy are private-overlay concerns.
- [`hosts/services/default.nix`](hosts/services/default.nix)
  is the service-host role. It does **not** import
  [`modules/agent-sandbox.nix`](modules/agent-sandbox.nix)
  or [`modules/nono.nix`](modules/nono.nix).
- [`hosts/dev/default.nix`](hosts/dev/default.nix) is the
  agent-execution role. It imports both sandbox modules and enables:
  - `services.agentCompute.enable = true`
  - `services.agentSandbox.enable = true`
  - `services.nonoSandbox.enable = true`
  - `extras/cass.nix` is imported so CASS indexing runs as a low-priority system timer

## Core Security Invariants

- The public repo is intentionally non-deployable. Real deployments are expected
  to come from a private overlay.
- Two-user model: `root` (operator/admin) and `agent` (sandboxed tools).
  - `root` handles deploy, maintenance, and SSH access.
  - `tsurf.agent.user` defaults to `agent` and is the sandboxed agent account.
  - The agent user is not in `wheel`; launcher sudo access comes from explicit sudoers rules only.
- Build-time assertions enforce that the agent user is not in `docker`.
- `users.mutableUsers = false`.
- `security.sudo.execWheelOnly = false`, but sudo rules are limited to
  explicit immutable-launcher commands.
- Agents must not be given access to deploy changes to their own security
  boundaries. This is enforced by operational policy, not technical controls.
- Raw agent binaries are not installed in `PATH` by
  [`modules/agent-compute.nix`](modules/agent-compute.nix).
  The intended interactive entrypoints are wrapper binaries such as `claude` and,
  if enabled, `codex`.
- A generic agent launcher ([`modules/agent-launcher.nix`](modules/agent-launcher.nix))
  provides the shared sandbox infrastructure. Agent-specific modules like
  [`modules/agent-sandbox.nix`](modules/agent-sandbox.nix) declare their
  configuration on top of it.
- The public repo does not ship a separate unattended-agent supervisor. Use the
  generated wrappers directly with `systemd` or `tmux` in private overlays.
- The public wrapper/launcher path has no `--no-sandbox` or
  `AGENT_ALLOW_NOSANDBOX` escape hatch.

## User And Privilege Model

| Identity | Default groups | Purpose | Enforced by |
| --- | --- | --- | --- |
| `root` | n/a | operator, deploy, maintenance, secrets, recovery | NixOS/systemd |
| `agent` | `users` | sandboxed agent execution, SSH access | `modules/users.nix` |

Important nuances:

- The agent user is not in `wheel`. `security.sudo.extraRules` grants `NOPASSWD`
  access only to specific immutable launcher binaries such as `tsurf-launch-claude`.
- The `allowUnsafePlaceholders` flag exists only for eval fixtures. It relaxes
  the root-login safety checks just enough for public evaluation by permitting
  an empty root `authorized_keys` list and setting `users.allowNoPasswordLogin = true`.
- Base Nix daemon policy is:
  - `allowed-users = [ "root" "<agent-user>" ]`
  - `trusted-users = [ "root" ]`
- The agent user has Nix daemon access via its explicit username in
  `allowed-users`, but is not in `trusted-users`.

## Template And Fixture Safety

- `tsurf.template.allowUnsafePlaceholders` defaults to `false`.
- Host source files do **not** set that flag. The public flake injects it only
  into the clearly named eval fixtures so `nix flake check` can evaluate without
  real credentials.
- When the flag is enabled, eval fixtures may leave
  `users.users.root.openssh.authorizedKeys.keys` empty and bypass the NixOS
  "no root login method configured" assertion.
- Real deployments are expected to generate a root SSH key with
  `nix run .#tsurf-init -- --overlay-dir /path/to/private-overlay`.

## Agent Sandbox

This section applies only to hosts that import and enable both
[`modules/agent-sandbox.nix`](modules/agent-sandbox.nix)
and [`modules/nono.nix`](modules/nono.nix). In the public
repo, that is the dev-host role.

### Launch Path

Interactive wrapper execution is brokered:

```text
agent (or root)
  -> wrapper stub (checks uid, calls sudo if needed)
    -> sudo tsurf-launch-<agent>
      -> systemd-run --same-dir --collect --slice=tsurf-agents.slice
        -> scripts/agent-wrapper.sh
          -> credential-proxy.py (root-owned, per-session tokens)
          -> nono run --profile /etc/nono/profiles/tsurf-<name>.json
            -> setpriv --reuid=<agent>
              -> real agent binary
```

Security properties of that path:

- `security.sudo.extraRules` exposes only immutable per-agent launchers such as
  `tsurf-launch-claude`. There is no generic root helper.
- Those sudo rules use `NOPASSWD` only. They do **not** use `SETENV`, and the
  wrapper does not use `sudo --preserve-env`.
- Each root-owned launcher bakes in:
  - the real binary path
  - the nono profile path
  - the credential allowlist
- The launcher rejects any `AGENT_REAL_BINARY` outside `/nix/store`.
- The caller cannot swap binaries, profiles, or credential tuples across the
  privileged sudo boundary.
- Launch events go to journald only (`journalctl -t agent-launch`).
  Logged fields are limited to `mode`, `agent`, `user`, `uid`, and `repo_scope`.
  Raw arguments, prompts, and file paths are not logged.

### Resource Limits

- The shared `tsurf-agents.slice` aggregate ceiling is:
  - `MemoryMax = 8G`
  - `CPUQuota = 300%`
  - `TasksMax = 1024`
- Each brokered interactive session gets tighter transient-unit limits:
  - `MemoryMax = 4G`
  - `CPUQuota = 200%`
  - `TasksMax = 256`
### Filesystem Boundary

The sandbox is implemented by `nono` with a pinned profile and Landlock-backed
filesystem rules.

Enforced behavior:

- The wrapper requires `$PWD` to be inside `services.agentLauncher.projectRoot`
  (default `/data/projects`).
- The wrapper requires `$PWD` to be inside a Git worktree.
- The wrapper resolves the Git toplevel with `git rev-parse --show-toplevel` and
  passes that path to nono with `--read`.
- The wrapper refuses to run if the resolved Git root is exactly the project root.
  This prevents granting blanket read access to all repos under `/data/projects`.
- The shipped nono profile denies:
  - `/run/secrets`
  - `~/.ssh`
  - `~/.bash_history`
  - `~/.gnupg`
  - `~/.aws`
  - `~/.kube`
  - `~/.docker`

Critical nuance:

- The boundary is still "current worktree is writable". The nono profile sets
  `workdir.access = "readwrite"`.
- What is blocked is broad cross-repo access:
  - no blanket `/data/projects` read grant
  - no sibling-repo read access from the wrapper path
- Agents must not be given access to deploy changes to their own security
  boundaries. This is enforced by operational policy (launch agents from
  workspace repos, not infrastructure repos), not technical controls.

Because deny behavior depends on nono/Landlock behavior on the target host, the
repo backs these claims with live sandbox tests on the dev host.

## Secrets And Credential Flow

### Secret Storage

- sops-nix derives its age identity from the host SSH ed25519 key.
- Secrets are decrypted to `/run/secrets`.
- Repo-defined ownership is:

| Secret | Owner |
| --- | --- |
| `anthropic-api-key` | root |
| `openai-api-key` | root |
| `github-pat` | `agent` |
| `restic-password`, `restic-b2-*` | root/default |

### Injection Model

- Each wrapper carries a per-wrapper `AGENT_CREDENTIALS` allowlist of
  `SERVICE:ENV_VAR:secret-file-name` triples.
- `scripts/agent-wrapper.sh` runs on the root-owned brokered launch path and
  reads only those named secret files from `/run/secrets`.
- Missing secret files produce a warning and an empty env var.
- Values prefixed with `PLACEHOLDER` are skipped.
- The wrapper starts a root-owned loopback credential proxy for the requested
  providers, generates per-session random tokens, then launches the actual
  agent binary as the `agent` user inside `nono` via `setpriv`.

What the child process gets:

- a per-session token such as `ANTHROPIC_API_KEY=<64-hex-token>`
- a localhost base URL such as `ANTHROPIC_BASE_URL=http://127.0.0.1:<port>/anthropic`

What the child process does **not** get:

- the raw `/run/secrets/*` file
- the raw provider API key in its environment

Credential scoping is least-privilege by wrapper. Core default: `claude`
(Anthropic only). Optional extras when enabled:

- `claude` — Anthropic only
- `codex` — OpenAI only
- extra agents must opt into credentials explicitly via the generic launcher

## Network Model

- nftables is enabled.
- `trustedInterfaces = [ ]`.
- `trustedInterfaces = [ ]`.
- Public TCP exposure is limited to:
  - `22` always
  - `80` and `443` only when `services.nginx.enable = true`
- Cloud metadata access to `169.254.169.254` is dropped in nftables.

SSH defaults:

- enabled
- key-only auth
- `PermitRootLogin = prohibit-password`
- ed25519 host key only
- `PasswordAuthentication = false`
- `KbdInteractiveAuthentication = false`
- `MaxAuthTries = 3`
- `fail2ban` is disabled

### Agent Egress

- `nono` itself is configured with `network.block = false`; it is not the egress
  allowlist boundary here.
- The public repo enforces agent egress in nftables by `meta skuid` for the
  dedicated agent user.
- Default allowed outbound traffic for sandboxed agents is:
  - loopback
  - DNS on TCP/UDP `53`
  - TCP `22`, `80`, and `443`
- Default denied outbound traffic for sandboxed agents includes:
  - RFC1918 IPv4 ranges
  - Tailscale CGNAT range `100.64.0.0/10`
  - link-local IPv4 `169.254.0.0/16`
  - IPv6 ULA `fc00::/7`
  - IPv6 link-local `fe80::/10`
- This boundary applies to every process running as the dedicated agent UID.

## Deployment, Recovery, And Lockout Prevention

Public-repo safety properties:

- The public flake exports no deploy targets.
- [`scripts/deploy.sh`](scripts/deploy.sh)
  refuses to deploy from the public repo, so public eval fixtures cannot be
  installed through the shipped deploy path.

Build-time lockout-prevention assertions require:

- `sshd` enabled
- root login not set to `no`
- at least one root SSH authorized key
- SSH port `22` reachable
- SSH host keys configured and persisted

Recovery mechanisms:

- Root SSH access is supplied by the private overlay. The recommended path is
  `nix run .#tsurf-init -- --overlay-dir /path/to/private-overlay`, which writes
  `modules/root-ssh.nix` for that overlay.
- The deploy path implemented in
  [`scripts/deploy.sh`](scripts/deploy.sh)
  supports magic rollback via deploy-rs with a 300s confirm timeout.
  The public copy of that script refuses to run from the public repo.

## Persistence And Supply Chain

- Root rollback uses a BTRFS post-resume rollback script.
- Persisted security-critical state includes:
  - `/var/lib/nixos`
  - `/etc/ssh/ssh_host_ed25519_key`
  - `/data/projects`
  - selected root and agent home state
- [`modules/impermanence.nix`](modules/impermanence.nix)
  makes `setupSecrets` depend on `persist-files` so sops-nix can read the
  persisted SSH host key before decrypting `/run/secrets` after a hard reboot.

Supply-chain properties:

- Nix inputs are pinned by `flake.lock`.
- Prebuilt binaries are SHA256-pinned, including `nono` and `cass`.
- `claude-code` and `codex` come from the pinned `llm-agents.nix` input.
- No signature verification is implemented for these prebuilt binaries.

## Verification

Security claims in this file are backed by both eval checks and live tests.

Eval-time checks:

- [`tests/eval/config-checks.nix`](tests/eval/config-checks.nix)
  covers public-output safety, placeholder isolation, firewall exposure,
  root-key requirements, Nix daemon restrictions, sandbox structure, read-scope
  fail-closed behavior, launcher hardening, and root-side credential broker structure.

Live checks:

- [`tests/live/security.bats`](tests/live/security.bats)
  verifies SSH hardening, kernel sysctls, metadata blocking, and firewall exposure.
- [`tests/live/secrets.bats`](tests/live/secrets.bats)
  verifies `/run/secrets` presence, root ownership for brokered provider keys,
  and non-world-readable permissions.
- [`tests/live/networking.bats`](tests/live/networking.bats)
  verifies DNS reachability, the metadata-block nftables rule, and the agent
  egress allowlist table.
- [`tests/live/sandbox-behavioral.bats`](tests/live/sandbox-behavioral.bats)
  proves that sandboxed agent code cannot read denied paths and can read/write the
  expected worktree paths.
- [`tests/live/agent-sandbox.bats`](tests/live/agent-sandbox.bats)
  verifies wrapper script structure: nono invocation, journald logging, and absence
  of secret mounts.
- [`tests/live/service-health.bats`](tests/live/service-health.bats)
  verifies systemd unit health (`sshd`, backup timers, and the CASS timer when present).
- [`tests/live/impermanence.bats`](tests/live/impermanence.bats)
  verifies /persist mount, BTRFS filesystem type, critical persist directories, and
  machine-id persistence.

## Non-Goals And Accepted Risks

- The service-host role does not include the agent sandbox at all.
- The sandbox does not make the current workspace immutable. If a user
  points an agent at a normal workspace repo, that repo is writable by design.
- The public repo deliberately avoids a separate unattended-agent supervisor.
  Private overlays can schedule the generated wrappers however they want.
- The host-level agent egress allowlist is coarse by design. It is scoped by UID,
  not by individual wrapper or destination hostname.
- Optional extras can widen access. Notable example:
  `services.costTracker.enable` grants a DynamicUser service read-only
  `/run/secrets` access plus `CAP_DAC_READ_SEARCH` so it can read provider keys.
