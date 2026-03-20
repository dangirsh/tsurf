# Security Model

This document describes the actual security boundaries, secret flow, privilege model,
and network model of tsurf. It is the authoritative source for security claims.

## Trust Boundaries

### What the sandbox guarantees

- **Filesystem isolation**: [nono](https://github.com/always-further/nono) uses
  [Landlock](https://docs.kernel.org/userspace-api/landlock.html) (kernel-level,
  irreversible per-process) to restrict agent filesystem access.
- **Read access scoped to current git repo root**, not all of `/data/projects`.
- **Denied paths**: `/run/secrets/`, `~/.ssh`, `~/.bash_history`, `~/.gnupg`,
  `~/.aws`, `~/.docker`, `~/.config/syncthing`.
- **`--no-sandbox` blocked** unless `AGENT_ALLOW_NOSANDBOX=1` is set in the environment.
- **Launch audit logging** to `/data/projects/.agent-audit/agent-launches.log`.

### What the sandbox does NOT guarantee

- **No egress filtering**: agents have unrestricted outbound network access. nono does
  not yet support allowlist-based outbound filtering on headless servers.
- **No memory/CPU isolation**: agents share host resources. No cgroup limits enforced.
- **Sandbox escape via `--no-sandbox`**: any user with `AGENT_ALLOW_NOSANDBOX=1` in
  their environment can bypass the sandbox entirely.
- **`dev` user has effective root access**: `dev` is in `wheel` with passwordless sudo
  in the public template. Production deployments must replace `users.nix` with proper
  user separation.

## Secret Flow

API keys are stored as sops-nix secrets, decrypted at activation to `/run/secrets/`.
The agent wrapper scripts (in `agent-sandbox.nix`) load secrets from `/run/secrets/`
and inject them as environment variables into the sandboxed child via nono
`--env-credential-map`. The sandboxed process receives real API keys as environment
variables. There is no credential proxy or token exchange.

## Privilege Model

The public template uses a single `dev` user with `wheel` + `docker` groups and
passwordless sudo. This is intentionally insecure for template evaluation purposes.

For production deployments:
- Replace `users.nix` entirely in your private overlay
- Split into operator (human admin, `wheel`) and agent (runs wrappers, no `wheel`,
  no `docker`) users
- Remove `tsurf.template.allowUnsafePlaceholders = true`

### Recommended Production Split

| User | Groups | Purpose |
|------|--------|---------|
| operator | wheel | Human admin, deploy, maintenance |
| agent | (none) | Runs agent wrappers, owns /data/projects |
| service-specific | (varies) | Long-lived services (optional) |

The `agent` user should NOT have `wheel` or `docker` access. Agent wrappers
run via nono sandbox; no sudo is needed for agent workloads.

## Template Safety

The public repo ships with `tsurf.template.allowUnsafePlaceholders` (default: `false`).

When enabled (`true`), the flag:
- Allows placeholder bootstrap and break-glass SSH keys (build-time assertions
  reject these placeholders when the flag is `false`)
- Sets `users.allowNoPasswordLogin = true` and `security.sudo.wheelNeedsPassword = false`
  (these are directly configured based on the flag value, not assertion-guarded)

When disabled (`false`, the default), the flag:
- Rejects placeholder SSH keys via build-time assertions
- Sets `users.allowNoPasswordLogin = false` and `security.sudo.wheelNeedsPassword = true`

The public host configs set `allowUnsafePlaceholders = true` so `nix flake check` works.
Real deployments via private overlay must not set this flag.

## Network Model

- **Default**: SSH (22) on public interface (key-only auth, hardened).
- **Conditional**: Syncthing BEP (22000) when `services.syncthing.enable` is true.
- **Conditional**: HTTP/HTTPS (80/443) when `services.nginx.enable` is true.
- **Everything else**: Tailscale-only. Internal services bind `127.0.0.1`,
  accessible only via `tailscale0` trusted interface.
- **Metadata endpoint**: `169.254.169.254` blocked at nftables level.
- **fail2ban**: disabled. SSH brute-force mitigation relies on key-only auth,
  MaxAuthTries 3, and srvos defaults.

## Agent Egress Controls

UID-based nftables egress filtering is available as opt-in via
`services.agentSandbox.egressControl.enable`. When enabled:

- The configured user (default: `dev`) is restricted to a whitelist of TCP
  destination ports (default: 53, 80, 443, 22, 9418 -- DNS, HTTP/S, SSH, git).
- UDP port 53 (DNS) is always allowed regardless of the TCP port list.
- Loopback and established/related connections are always allowed.
- Traffic on the `tailscale0` interface is unrestricted (internal service access).
- All other outbound traffic from the agent user is logged with prefix
  `agent-egress-deny:` and dropped.
- Non-agent users are unaffected (policy accept for other UIDs).

Configure the allowed port list via `services.agentSandbox.egressControl.allowedPorts`.

## Accepted Risks

See the "Accepted Risks" section in [CLAUDE.md](CLAUDE.md) for the full list.
Key items:

- Unrestricted agent network egress (SEC105-02)
- `dev` user in `wheel` + `docker` with passwordless sudo (template only)
- Pre-built binaries (zmx, cass, nono) use SHA256 hash pinning, not signatures
- `bypassPermissions` inside nono sandbox for unattended agent runs (SEC98-01)

## Supply Chain

All prebuilt binaries are content-addressed (SHA256 hash pinning). No GPG signature
verification is performed. Versions are pinned; hash mismatches cause build failures.

| Binary | Source | Hash Pinned | Opt-in |
|--------|--------|-------------|--------|
| nono | github.com/always-further/nono | Yes (sha256) | services.nonoSandbox.enable |
| pi | github.com/badlogic/pi-mono | Yes (sha256) | via agent-compute.nix import |
| zmx | zmx.sh | Yes (sha256) | via agent-compute.nix import |
| cass | github.com/Dicklesworthstone/coding_agent_session_search | Yes (sha256) | programs.cass.enable |
| claude-code | numtide/llm-agents.nix | Via flake.lock | via agent-compute.nix import |
| codex | numtide/llm-agents.nix | Via flake.lock | via agent-compute.nix import |

To remove all prebuilt agent binaries: do not import `agent-compute.nix` in your host config.
