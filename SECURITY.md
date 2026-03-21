# Security Model

This document describes the actual security boundaries, secret flow, privilege model,
and network model of tsurf. It is the authoritative source for security claims.

## Trust Boundaries

### What the sandbox guarantees

- **Brokered execution**: Interactive agent sessions run as the `agent` user, not the
  calling operator. The wrapper uses `sudo` + `systemd-run --uid=agent` to drop
  privileges before executing the agent binary. The operator never directly execs
  agent binaries with agent credentials.
- **Per-session cgroup limits**: Each interactive session runs in a transient systemd
  unit under `tsurf-agents.slice` with MemoryMax=4G, CPUQuota=200%, TasksMax=256.
- **Filesystem isolation**: [nono](https://github.com/always-further/nono) uses
  [Landlock](https://docs.kernel.org/userspace-api/landlock.html) (kernel-level,
  irreversible per-process) to restrict agent filesystem access.
- **Read access scoped to current git repo root**, not all of `/data/projects`.
- **Denied paths**: `/run/secrets/`, `~/.ssh`, `~/.bash_history`, `~/.gnupg`,
  `~/.aws`, `~/.docker`, `~/.config/syncthing`.
- **`--no-sandbox` blocked** unless `AGENT_ALLOW_NOSANDBOX=1` is set in the environment.
- **Launch logging** to journald (`journalctl -t agent-launch`) — structured metadata only, no raw arguments.

### What the sandbox does NOT guarantee

- **No egress filtering**: agents have unrestricted outbound network access. nono does
  not yet support allowlist-based outbound filtering on headless servers.
- **Sandbox escape via `--no-sandbox`**: any user with `AGENT_ALLOW_NOSANDBOX=1` in
  their environment can bypass the sandbox entirely. Under the brokered model, the
  unsandboxed binary still runs as `agent` (not operator).
- **`dev` user has effective root access**: `dev` is in `wheel` with passwordless sudo
  in the public template. The brokered launch model prevents casual privilege leaks,
  but `dev` can always escalate via `sudo`. The operator/agent split is enforced by
  build-time assertions and the brokered launcher.

## Secret Flow

API keys are stored as sops-nix secrets, decrypted at activation to `/run/secrets/`.
The brokered launcher runs `agent-wrapper.sh` as the `agent` user (via `systemd-run
--uid=agent`). The wrapper loads secrets from `/run/secrets/` (agent-owned) into the
parent process environment. nono's reverse proxy reads them via `env://` URIs,
generates per-session 256-bit phantom tokens, and passes only the phantom tokens to
the sandboxed child. The child process never sees real API keys — it receives a
worthless session token that only works with nono's localhost proxy.

The operator (`dev`) never has agent credentials in their shell. Secrets are only
readable by the `agent` user, and the brokered launcher ensures the wrapper runs as
`agent` even when invoked by `dev`.

## Privilege Model

The public template ships an operator/agent user split with brokered execution:

| User | Groups | Purpose | Build-time assertions |
|------|--------|---------|----------------------|
| `dev` (operator) | wheel, docker | Human admin, deploy, maintenance | — |
| `agent` | users | Runs sandboxed agent tools, owns workspaces | NOT in wheel, NOT in docker |
| service-specific | (varies) | Long-lived services (optional) | — |

### Execution flow

```
dev runs "claude ..."
  → wrapper stub (as dev): sets AGENT_* env vars
    → sudo tsurf-agent-launch (as root): validates inputs, Nix store path check
      → systemd-run --uid=agent --pty --slice=tsurf-agents.slice
        → agent-wrapper.sh (as agent): reads /run/secrets/*, applies nono sandbox
          → nono → real agent binary (as agent, sandboxed, phantom tokens only)
```

When already running as `agent` (e.g. `dev-agent.nix` systemd unit), the wrapper
skips the brokered path and execs `agent-wrapper.sh` directly.

Parameterized via `tsurf.agent.{user, home, projectRoot}` (default: `agent`,
`/home/agent`, `/data/projects`). Build-time assertions reject agent user in
wheel or docker groups.

The `dev` user retains `wheel` + `docker` because the public template uses
`allowUnsafePlaceholders = true` (injected at flake level for eval fixtures).
Private overlay uses `mkHost` directly and never sets this flag.

## Control-Plane vs Workspace Separation

### Zones

- **Control plane** (`/data/projects/tsurf` or private overlay): NixOS config,
  deployment scripts, sops-encrypted secrets, `flake.lock`. Write access =
  ability to modify the system config that gets deployed.
- **Workspace** (`/data/projects/<other-repos>`): Application code repos where
  agents do their work. Write access is expected and normal.

### Current enforcement

- Both zones live under `/data/projects` (persisted as a single impermanence directory)
- The sandbox scopes read access to the current git repo root — agents cannot read sibling repos
- `agent-wrapper.sh` refuses to grant read access to the entire `/data/projects` root
- `scripts/deploy.sh` runs as operator, not agent — agent user cannot deploy

### Recommended production hardening

- Set control-plane repo ownership to `dev:dev` (operator-only write)
- Set workspace repos ownership to `agent:users`
- Consider separate directories: `/data/infra` (operator) and `/data/workspace` (agent)
- Add systemd tmpfiles rules for ownership enforcement
- The `dev-agent.nix` service uses `WorkingDirectory = /data/projects/tsurf` as a
  template example — production should point to a workspace repo, not the control-plane

## Credential Flow Architecture

```
sops-encrypted YAML (secrets/*.yaml)
  │
  ▼  sops-nix activation (age key from SSH host key)
/run/secrets/<secret-name>  (mode 0400, owner: agent user)
  │  Ownership set by agent-sandbox.nix (mkDefault agentCfg.user).
  │
  ▼  Brokered privilege drop (interactive: sudo → systemd-run --uid=agent)
  │  agent-wrapper.sh always runs as the agent user (see "Execution flow" above).
  │
  ▼  agent-wrapper.sh reads secrets from per-wrapper AGENT_CREDENTIALS allowlist
Parent process env var (e.g., ANTHROPIC_API_KEY=sk-...)
  │  PLACEHOLDER-prefixed values skip credential injection.
  │
  ▼  nono --credential <service> (proxy mode, Landlock sandbox applied)
  │
  ├─ nono proxy: reads env://ANTHROPIC_API_KEY, holds real key in Zeroizing<String>
  │  Starts localhost reverse proxy, generates 256-bit phantom token
  │
  ▼  Sandboxed child receives:
     ANTHROPIC_API_KEY=<64-char-hex-phantom-token>  (worthless outside session)
     ANTHROPIC_BASE_URL=http://127.0.0.1:<port>/anthropic
```

**Who runs the wrapper:**
- **Interactive use** (operator typing `claude`): brokered launch drops to `agent` user
  via `sudo` + `systemd-run --uid=agent` before the wrapper runs. Secret files are
  agent-owned (`mkDefault`), which matches this path.
- **dev-agent.nix** (systemd service): wrapper runs as `agentCfg.user` (default: `agent`)
  directly — the wrapper detects it's already `agent` and skips the brokered path.

**Stage details:**
1. **sops-nix** decrypts at system activation using age key derived from SSH host key.
   Secret files land at `/run/secrets/<name>` with mode 0400.
2. **Ownership** is declared in `agent-sandbox.nix` via `mkDefault` — both
   `anthropic-api-key` and `openai-api-key` default to `config.tsurf.agent.user`.
   No separate `secrets.nix` module exists in the public template for API keys.
   The brokered launch model ensures the wrapper always runs as `agent`, so the
   default ownership is correct for both interactive and daemon paths.
3. **agent-wrapper.sh** reads only the secrets named in `AGENT_CREDENTIALS` (a per-wrapper
   allowlist set by the Nix wrapper stub). Each triple is `SERVICE:ENV_VAR:secret-file-name`.
   Missing files produce a warning; `PLACEHOLDER`-prefixed values skip credential injection.
4. **nono's reverse proxy** loads real keys from parent env via `env://` URIs (no system
   keystore needed), generates per-session 256-bit phantom tokens.
5. The child receives only phantom tokens + localhost base URLs — real keys never enter
   the child's environment or memory.

**Security properties:**
- The operator (`dev`) never has agent API keys in their shell environment
- Real API keys exist only in the nono proxy process (parent), stored in `Zeroizing<String>`
  (memory wiped on drop)
- Child process env (`/proc/PID/environ`) contains only worthless phantom tokens
- Phantom tokens are validated via constant-time comparison
- The proxy enforces TLS for upstream connections
- `/run/secrets/` files are NOT accessible from inside the sandbox (denied by Landlock)
- Each wrapper loads only its own credential allowlist — `claude` loads only Anthropic,
  `codex` loads only OpenAI (least-privilege per wrapper)
- See accepted risk SEC114-02

## Tailnet Segmentation

### Localhost-first model

`tailscale0` is **not** in `trustedInterfaces`. Internal services bind `127.0.0.1`
and are not reachable from the tailnet by default. Access to internal services is via
SSH tunnel (`ssh -L`) or Tailscale Serve. `--accept-routes` is not set by default.

If a private overlay needs direct tailnet access to a service, it should:
1. Change the service's bind address to `0.0.0.0`
2. Add the port to `networking.firewall.interfaces.tailscale0.allowedTCPPorts`

No blanket interface trust is required.

### Recommendations for production

- **Tailscale ACL tags**: Assign `tag:server` to hosts, `tag:admin` to operator
  devices, `tag:agent` to agent identities. Restrict service access to `tag:admin` only.
- **Tailscale Grants/ACLs**: Use ACL policies to restrict which tagged devices can
  reach which ports. Example: only `tag:admin` can reach port 8082 (dashboard).
- **Per-host segmentation**: Agent-running host should have tighter tailnet ACLs than
  the services host.
- **Tailnet Lock**: Enable for higher-assurance node enrollment.
- **`--accept-routes`**: Only add to `extraUpFlags` if you need to accept subnet
  routes from other tailnet nodes. Disabled by default to prevent route hijacking.

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

Host source files (`hosts/*/default.nix`) are secure by default and do NOT set
`allowUnsafePlaceholders`. The public flake injects it at the flake level via
`mkEvalFixture` for CI eval only. Private overlay uses `mkHost` directly.

## Network Model

- **Default**: SSH (22) on public interface (key-only auth, hardened).
- **Conditional**: Syncthing BEP (22000) when `publicBep` opt-in is enabled.
- **Conditional**: HTTP/HTTPS (80/443) when `services.nginx.enable` is true.
- **Everything else**: Localhost-only. Internal services bind `127.0.0.1`.
  Access via SSH tunnel or Tailscale Serve. No blanket `trustedInterfaces`.
  Private overlay can expose specific ports on `tailscale0` via
  `networking.firewall.interfaces.tailscale0.allowedTCPPorts`.
- **Metadata endpoint**: `169.254.169.254` blocked at nftables level.
- **fail2ban**: disabled. SSH brute-force mitigation relies on key-only auth,
  MaxAuthTries 3, and srvos defaults.

## Agent Egress Controls

UID-based nftables egress filtering is available as opt-in via
`services.agentSandbox.egressControl.enable`. When enabled:

- The configured user (default: `agent`, via `tsurf.agent.user`) is restricted to a whitelist of TCP
  destination ports (default: 53, 80, 443, 22, 9418 -- DNS, HTTP/S, SSH, git).
- UDP port 53 (DNS) is always allowed regardless of the TCP port list.
- Loopback and established/related connections are always allowed.
- Traffic on the `tailscale0` interface is unrestricted for agent egress (outbound
  to tailnet peers, e.g., syncthing, other hosts). This is separate from the host's
  ingress firewall rules (which no longer trust `tailscale0` as an interface).
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
