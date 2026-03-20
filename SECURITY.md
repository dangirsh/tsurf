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
  in the public template. Agent tools run as the separate `agent` user (no wheel,
  no docker). The operator/agent split is enforced by build-time assertions.

## Secret Flow

API keys are stored as sops-nix secrets, decrypted at activation to `/run/secrets/`.
The agent wrapper scripts (in `agent-sandbox.nix`) load secrets from `/run/secrets/`
and inject them as environment variables into the sandboxed child via nono
`--env-credential-map`. The sandboxed process receives real API keys as environment
variables. There is no credential proxy or token exchange.

## Privilege Model

The public template ships an operator/agent user split:

| User | Groups | Purpose | Build-time assertions |
|------|--------|---------|----------------------|
| `dev` (operator) | wheel, docker | Human admin, deploy, maintenance | — |
| `agent` | users | Runs sandboxed agent tools, owns workspaces | NOT in wheel, NOT in docker |
| service-specific | (varies) | Long-lived services (optional) | — |

Parameterized via `tsurf.agent.{user, home, projectRoot}` (default: `agent`,
`/home/agent`, `/data/projects`). Build-time assertions reject agent user in
wheel or docker groups.

The `dev` user retains `wheel` + `docker` because the public template needs
`allowUnsafePlaceholders = true` for eval. Private overlay can replace
`users.nix` entirely (`disabledModules`) or override `tsurf.agent.*` options.

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
/run/secrets/<secret-name>  (mode 0400, owner: agent user via sops.secrets.*.owner)
  │
  ▼  agent-wrapper.sh reads at launch (runs as agent user)
Shell env var (e.g., ANTHROPIC_API_KEY=sk-...)
  │
  ▼  nono --env-credential-map (Landlock sandbox applied)
Sandboxed child process env var
```

**Stage details:**
1. **sops-nix** decrypts at system activation using age key derived from SSH host key
2. **agent-wrapper.sh** reads `/run/secrets/*` files (secret files must be owned by the
   agent user — set `sops.secrets."<name>".owner = config.tsurf.agent.user`)
3. Wrapper exports env vars, then nono `--env-credential-map` re-injects them into the
   sandboxed child
4. The child receives real API keys as env vars — no proxy, no token exchange

**Security implications:**
- API keys exist in process env for the lifetime of the agent process
- `/run/secrets/` files are NOT accessible from inside the sandbox (denied by Landlock)
- The wrapper process briefly holds all configured keys before exec'ing nono
- `dev-agent.sh` parent env does NOT hold API keys (fixed in Phase 114)

**Recommended upgrade path:**
- Local API proxy (e.g., litellm, envoy) that issues short-lived tokens
- Agents talk to `http://127.0.0.1:<port>/v1/...`, proxy injects real token server-side
- Not implemented — requires org.freedesktop.secrets or equivalent for headless credential storage
- See accepted risk SEC114-02

## Tailnet Segmentation

### Current state

`tailscale0` is in `trustedInterfaces` — any device on the tailnet can reach all
internal services. All internal services bind `127.0.0.1` and are reachable via
Tailscale because the trusted interface bypasses the firewall. This is a **flat
trust model**: every tailnet device is equally trusted.

### Recommendations for production

- **Tailscale ACL tags**: Assign `tag:server` to hosts, `tag:admin` to operator
  devices, `tag:agent` to agent identities. Restrict service access to `tag:admin` only.
- **Tailscale Grants/ACLs**: Use ACL policies to restrict which tagged devices can
  reach which ports. Example: only `tag:admin` can reach port 8082 (dashboard).
- **Consider removing `tailscale0` from trustedInterfaces**: Bind services to specific
  IPs and use Tailscale Serve for access control. Trade-off: more configuration, better
  segmentation.
- **Per-host segmentation**: Agent-running host should have tighter tailnet ACLs than
  the services host.
- **Tailnet Lock**: Enable for higher-assurance node enrollment.

### Implementation notes

- Tailscale ACLs are configured in the Tailscale admin console, not NixOS config
- NixOS can set `tailscale.extraUpFlags` with tags (requires pre-authorized tag in admin)
- Removing `tailscale0` from `trustedInterfaces` requires binding each service to the
  Tailscale IP explicitly — significant refactoring, recommended as a future phase
- See accepted risk SEC115-01

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

- The configured user (default: `agent`, via `tsurf.agent.user`) is restricted to a whitelist of TCP
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
