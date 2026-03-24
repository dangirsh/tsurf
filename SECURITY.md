# Security Model

This document describes the security properties that this repository actually
implements today. It is about the public repo as shipped. Private overlays can
strengthen or weaken these properties, so host-specific statements are called out.

## Scope

- The public flake exports only eval fixtures:
  `eval-services`, `eval-dev`, and `eval-dev-alt-agent`.
- The public flake exports no `deploy.nodes`; all exported
  `nixosConfigurations` are prefixed with `eval-`.
- [`examples/scripts/deploy.sh`](examples/scripts/deploy.sh)
  refuses to deploy unless it is being run from a private overlay flake that
  contains a `tsurf.url` input.
- [`hosts/services/default.nix`](hosts/services/default.nix)
  is the service-host role. It does **not** import
  [`modules/agent-sandbox.nix`](modules/agent-sandbox.nix)
  or [`modules/nono.nix`](modules/nono.nix).
- [`hosts/dev/default.nix`](hosts/dev/default.nix) is the
  agent-execution role. It imports both sandbox modules and enables:
  - `services.agentCompute.enable = true`
  - `services.agentSandbox.enable = true`
  - `services.nonoSandbox.enable = true`
  - `extras/dev-agent.nix` is imported, but `services.devAgent.enable` remains opt-in

## Core Security Invariants

- The public repo is intentionally non-deployable. Real deployments are expected
  to come from a private overlay.
- The operator and agent identities are separate:
  - `dev` is the human/operator account.
  - `tsurf.agent.user` defaults to `agent` and is the sandboxed agent account.
- Build-time assertions enforce that the agent user:
  - is not `dev`
  - is not in `wheel`
- `users.mutableUsers = false`.
- `security.sudo.execWheelOnly = true`.
- Raw agent binaries are not installed in `PATH` by
  [`modules/agent-compute.nix`](modules/agent-compute.nix).
  The intended interactive entrypoints are wrapper binaries such as `claude` and,
  if enabled, `codex`, `pi`, or `opencode`.
- The public repo also ships a first-class unattended agent path:
  [`extras/dev-agent.nix`](extras/dev-agent.nix), which supervises a
  parameterized Claude task inside the same sandbox boundary.
- The public wrapper/launcher path has no `--no-sandbox` or
  `AGENT_ALLOW_NOSANDBOX` escape hatch.

## User And Privilege Model

| Identity | Default groups | Purpose | Enforced by |
| --- | --- | --- | --- |
| `dev` | `wheel` | human admin, deploy, maintenance | `modules/users.nix` |
| `agent` | `users` | sandboxed agent execution | `modules/users.nix` assertions |
| `root` | n/a | activation, secrets, deploy, recovery | NixOS/systemd |

Important nuances:

- `dev` is always an administrative user in the template. The
  `allowUnsafePlaceholders` flag does **not** remove `dev` from `wheel`; it only
  controls placeholder-key assertions plus:
  - `users.allowNoPasswordLogin`
  - `security.sudo.wheelNeedsPassword`
- Base Nix daemon policy is:
  - `allowed-users = [ "root" "@wheel" ]`
  - `trusted-users = [ "root" ]`
- The public core does **not** grant the agent user direct Nix daemon access.
  Private overlays can loosen that boundary, but this repo does not ship such an
  option today.

## Template And Fixture Safety

- `tsurf.template.allowUnsafePlaceholders` defaults to `false`.
- Host source files do **not** set that flag. The public flake injects it only
  into the clearly named eval fixtures so `nix flake check` can evaluate without
  real credentials.
- When the flag is enabled, it permits placeholder bootstrap/break-glass keys and
  flips:
  - `users.allowNoPasswordLogin = true`
  - `security.sudo.wheelNeedsPassword = false`
- The public repo still contains placeholder bootstrap and break-glass keys in
  source. That is acceptable only because:
  - real deploy targets are not exported here
  - the public deploy script refuses to run
  - real deployments are expected to replace these values in a private overlay

## Agent Sandbox

This section applies only to hosts that import and enable both
[`modules/agent-sandbox.nix`](modules/agent-sandbox.nix)
and [`modules/nono.nix`](modules/nono.nix). In the public
repo, that is the dev-host role.

### Launch Path

Interactive wrapper execution is brokered:

```text
dev
  -> wrapper stub (exports AGENT_* env)
    -> sudo tsurf-launch-<agent>
      -> systemd-run --uid=<agent> --gid=<agent gid> --same-dir --collect
         --slice=tsurf-agents.slice
        -> scripts/agent-wrapper.sh
          -> nono run --profile /etc/nono/profiles/tsurf.json
            -> real agent binary
```

Security properties of that path:

- `security.sudo.extraRules` exposes only immutable per-agent launchers such as
  `tsurf-launch-claude`. There is no generic root helper.
- Those sudo rules use `NOPASSWD` only. They do **not** use `SETENV`, and the
  wrapper no longer uses `sudo --preserve-env`.
- Each root-owned launcher bakes in:
  - the real binary path
  - the nono profile path
  - the credential allowlist
  - whether Nix daemon access is enabled
- The launcher still rejects any baked `AGENT_REAL_BINARY` outside `/nix/store`.
- The caller cannot swap binaries, profiles, or credential tuples across the
  privileged sudo boundary.
- If the wrapper is already running as the agent user, it skips the sudo/systemd
  hop and execs `agent-wrapper.sh` directly. This is how `dev-agent` runs its
  prompt or command payloads.
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
- The optional `dev-agent` service also runs inside `tsurf-agents.slice` with
  per-unit `4G / 200% / 256` and `OOMPolicy=kill`.

### Filesystem Boundary

The sandbox is implemented by `nono` with a pinned profile and Landlock-backed
filesystem rules.

Enforced behavior:

- The wrapper requires `$PWD` to be inside `services.agentSandbox.projectRoot`
  (default `/data/projects`).
- The wrapper requires `$PWD` to be inside a Git worktree.
- The wrapper resolves the Git toplevel with `git rev-parse --show-toplevel` and
  passes that path to nono with `--read`.
- The wrapper refuses to run if the resolved Git root is exactly the project root.
  This prevents granting blanket read access to all repos under `/data/projects`.
- The wrapper also refuses any Git repo whose root:
  - matches an entry in `services.agentSandbox.protectedRepoRoots`, or
  - carries a marker file from `services.agentSandbox.protectedRepoMarkers`
    (default: `.tsurf-control-plane`)
- This repo ships that marker at its root, so sandboxed agents cannot be launched
  from the tsurf control-plane checkout by default.
- The shipped nono profile denies:
  - `/run/secrets`
  - `~/.ssh`
  - `~/.bash_history`
  - `~/.config/syncthing`
  - `~/.gnupg`
  - `~/.aws`
  - `~/.kube`
  - `~/.docker`

Critical nuance:

- The boundary is still "current worktree is writable". The nono profile sets
  `workdir.access = "readwrite"`.
- What changed is the supported definition of "current worktree": protected
  control-plane repos are blocked up front by marker/root checks, so the default
  public path is now "workspace repo vs control-plane repo".
- What is blocked is broad cross-repo access:
  - no blanket `/data/projects` read grant
  - no sibling-repo read access from the wrapper path
- Private overlays should keep infrastructure repos operator-owned, carry the
  marker file where possible, and launch agents from dedicated workspace repos.

Because deny behavior depends on nono/Landlock behavior on the target host, the
repo backs these claims with live sandbox tests on the dev host.

## Secrets And Credential Flow

### Secret Storage

- sops-nix derives its age identity from the host SSH ed25519 key.
- Secrets are decrypted to `/run/secrets`.
- Repo-defined ownership is:

| Secret | Owner |
| --- | --- |
| `anthropic-api-key` | agent user |
| `openai-api-key` | agent user |
| `google-api-key` | `dev` |
| `xai-api-key` | `dev` |
| `openrouter-api-key` | `dev` |
| `github-pat` | `dev` |
| `tailscale-authkey` | root/default |
| `b2-account-id`, `b2-account-key`, `restic-password` | root/default |

### Injection Model

- Each wrapper carries a per-wrapper `AGENT_CREDENTIALS` allowlist of
  `SERVICE:ENV_VAR:secret-file-name` triples.
- `scripts/agent-wrapper.sh` reads only those named secret files from
  `/run/secrets`.
- Missing secret files produce a warning and an empty env var.
- Values prefixed with `PLACEHOLDER` are not passed to nono as live credentials.
- [`modules/nono.nix`](modules/nono.nix) defines proxy-style
  `custom_credentials` for Anthropic and OpenAI using `env://` URIs.
- `nono` then injects per-session phantom tokens into the sandboxed child via
  `--credential <service>`.

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
- `pi` — Anthropic only
- `opencode` — Anthropic + OpenAI
- extra agents must opt into credentials explicitly

## Network Model

- nftables is enabled.
- `trustedInterfaces = [ ]`.
- `tailscale0` is **not** trusted.
- Public TCP exposure is limited to:
  - `22` always
  - `22000` only when `services.syncthingStarter.publicBep = true`
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

Syncthing defaults:

- GUI binds `127.0.0.1:8384`
- global announce, local announce, relays, and NAT are disabled
- public BEP exposure is opt-in

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
- This boundary applies to both interactive wrappers and the unattended
  `dev-agent` service because both run as the dedicated agent UID.

## Deployment, Recovery, And Lockout Prevention

Public-repo safety properties:

- The public flake exports no deploy targets.
- [`examples/scripts/deploy.sh`](examples/scripts/deploy.sh)
  refuses to deploy from the public repo, so public eval fixtures cannot be
  installed through the shipped deploy path.

Build-time lockout-prevention assertions require:

- `sshd` enabled
- root login not set to `no`
- at least one root SSH authorized key
- SSH port `22` reachable
- Tailscale enabled
- SSH host keys configured and persisted
- a break-glass emergency SSH key present

Recovery mechanisms:

- [`modules/break-glass-ssh.nix`](modules/break-glass-ssh.nix)
  adds a hardcoded break-glass root key. In the public repo this key is
  placeholder material and must be replaced in a private overlay before any real
  deployment.
- The private-overlay deploy path implemented in
  [`examples/scripts/deploy.sh`](examples/scripts/deploy.sh)
  schedules a 5-minute rollback watchdog via `systemd-run` before every deploy.
  The watchdog auto-reverts to the previous NixOS generation if SSH connectivity
  is not verified post-deploy. The public copy of that script refuses to run.

## Persistence And Supply Chain

- Root rollback uses a BTRFS post-resume rollback script.
- Persisted security-critical state includes:
  - `/var/lib/nixos`
  - `/var/lib/tailscale`
  - `/etc/ssh/ssh_host_ed25519_key`
  - `/data/projects`
  - selected operator and agent home state
- [`modules/impermanence.nix`](modules/impermanence.nix)
  makes `setupSecrets` depend on `persist-files` so sops-nix can read the
  persisted SSH host key before decrypting `/run/secrets` after a hard reboot.

Supply-chain properties:

- Nix inputs are pinned by `flake.lock`.
- Prebuilt binaries are SHA256-pinned, including `nono` and `zmx`.
- `claude-code` and `codex` come from the pinned `llm-agents.nix` input.
- No signature verification is implemented for these prebuilt binaries.

## Verification

Security claims in this file are backed by both eval checks and live tests.

Eval-time checks:

- [`tests/eval/config-checks.nix`](tests/eval/config-checks.nix)
  covers public-output safety, placeholder isolation, firewall exposure,
  break-glass requirements, Nix daemon restrictions, sandbox structure, read-scope
  fail-closed behavior, sudo-boundary hardening, and proxy credential configuration.

Live checks:

- [`tests/live/security.bats`](tests/live/security.bats)
  verifies SSH hardening, kernel sysctls, metadata blocking, and firewall exposure.
- [`tests/live/secrets.bats`](tests/live/secrets.bats)
  verifies `/run/secrets` presence, ownership, and non-world-readable permissions.
- [`tests/live/networking.bats`](tests/live/networking.bats)
  verifies Tailscale state, the metadata-block nftables rule, and the agent
  egress allowlist table.
- [`tests/live/sandbox-behavioral.bats`](tests/live/sandbox-behavioral.bats)
  proves that sandboxed agent code cannot read denied paths and can read/write the
  expected worktree paths, and that protected control-plane repos are refused.
- [`tests/live/agent-sandbox.bats`](tests/live/agent-sandbox.bats)
  verifies wrapper script structure: nono invocation, journald logging, and absence
  of secret mounts.
- [`tests/live/service-health.bats`](tests/live/service-health.bats)
  verifies systemd unit health (tailscaled, syncthing, sshd, dashboard, restic timer)
  and Tailscale backend state.
- [`tests/live/impermanence.bats`](tests/live/impermanence.bats)
  verifies /persist mount, BTRFS filesystem type, critical persist directories, and
  machine-id persistence.
- [`tests/live/api-endpoints.bats`](tests/live/api-endpoints.bats)
  verifies HTTP endpoint health for localhost-bound services (syncthing GUI, dashboard).

## Non-Goals And Accepted Risks

- The service-host role does not include the agent sandbox at all.
- The sandbox does not make the current workspace immutable. If an operator
  points an agent at a normal workspace repo, that repo is writable by design.
- `dev` remains a trusted administrative user with `wheel`.
- The public core does not grant the agent user Nix daemon access. Private
  overlays can loosen this boundary if needed.
- [`extras/dev-agent.nix`](extras/dev-agent.nix) runs Claude
  Code with `--permission-mode=bypassPermissions` inside the sandbox by default.
  That is an explicit unattended-workflow tradeoff; operators can override
  `services.devAgent.permissionMode`.
- The host-level agent egress allowlist is coarse by design. It is scoped by UID,
  not by individual wrapper or destination hostname.
- Optional extras can widen access. Notable example:
  `services.costTracker.enable` grants a DynamicUser service read-only
  `/run/secrets` access plus `CAP_DAC_READ_SEARCH` so it can read provider keys.
