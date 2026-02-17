# Phase 11: Agent Sandboxing - Research

**Researched:** 2026-02-17
**Domain:** Linux process sandboxing (bubblewrap), NixOS module integration, rootless container runtimes
**Confidence:** HIGH

## Summary

Bubblewrap (bwrap) 0.11.0 is available in nixpkgs (nixos-25.11) and provides all the primitives needed for this phase: mount namespace isolation, optional user/PID/IPC/UTS namespace separation, `--disable-userns` to prevent sandbox escapes, `--die-with-parent` for lifecycle management, and `--tmpfs`/`--size` for ephemeral storage caps. The existing `agent-spawn` script in `modules/agent-compute.nix` already wraps agents in a `systemd-run --user --scope --slice=agent.slice` call with `zmx`; the sandbox adds a `bwrap` layer between `systemd-run` and `zmx`, constructing an isolated mount namespace before the agent process starts.

The critical design question is whether to use `--unshare-user`. On NixOS, bwrap is NOT setuid (confirmed in nixpkgs), so it implicitly creates a user namespace for mount operations. The user decision says "run as host user (dangirsh) -- correct file ownership on project dir writes." This is achievable: bwrap with user namespace still maps the invoking UID/GID (via `--uid`/`--gid`) so files written to bind-mounted directories retain the host user's ownership. Alternatively, without `--unshare-user`, bwrap on non-setuid installations may still implicitly create a user namespace -- this needs a validation test on the target NixOS system.

Rootless Podman (5.8.0 in nixpkgs) serves as the Docker replacement inside the sandbox. NixOS provides `virtualisation.podman` with `dockerCompat = true` as a clean module. The key requirement is `subUidRanges`/`subGidRanges` for the `dangirsh` user, which must be added. Podman is daemonless and works with user namespaces, making it compatible with the bubblewrap sandbox -- agents use `podman` (aliased as `docker`) without needing the Docker socket.

**Primary recommendation:** Wrap the existing `agent-spawn` with a bwrap invocation that constructs an explicit deny-by-default mount namespace (only `/nix/store`, project dir, curated dotfiles, and essential system files visible), runs inside the existing `systemd-run --user --scope` for cgroup limits, and uses `--die-with-parent` + `--new-session` for lifecycle isolation. Add rootless Podman as a NixOS module alongside existing Docker.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Filesystem Policy
- `/data/projects/` visible read-only; agent's specific project directory is read-write
- `/nix/store` fully visible read-only (no security concern -- content-addressed, no secrets)
- Nix daemon socket bind-mounted -- agents can `nix build`, `nix develop`, `nix-shell`
- Per-agent isolated tmpfs at `/tmp` (ephemeral, dies with agent)
- `/run/secrets/` completely invisible (sops-nix secrets hidden)
- `~/.ssh/` completely invisible (no SSH agent forwarding either)
- No Docker socket inside sandbox (Docker socket = root-equivalent = sandbox escape)
- No Tailscale CLI/interface (network access via regular routing, not tailscale tooling)
- Curated home directory bind-mounts: fixed list of common dotfiles (e.g., `~/.gitconfig`, `~/.npmrc`) -- read-only. Not configurable per-project.
- Minimal `/dev`: only `/dev/null`, `/dev/zero`, `/dev/urandom`, `/dev/tty`, `/dev/pts`
- `/etc` handling: Claude's discretion -- selective bind-mount of resolv.conf, passwd, group, ssl certs, nix configs
- Shared PID namespace (agent can see host processes, useful for debugging)
- Run as host user (dangirsh) -- correct file ownership on project dir writes
- Multiple agents on same project: shared workspace view (they coordinate via git/worktrees)
- Fully ephemeral: when agent exits, all non-project-dir state is gone
- All permissions fixed at spawn time -- no runtime escalation

#### Docker Access via Rootless Podman
- No raw Docker socket in sandbox (prevents sandbox escape via privileged containers / host mounts)
- Rootless Podman as the container runtime for agents
- Daemonless architecture -- no per-agent daemon overhead (unlike rootless Docker)
- Agents get full `podman build` / `podman run` / `podman-compose` workflow
- User namespace isolation: even container escape = unprivileged user
- Containers launched via Podman inherit host network (including Tailscale for testing)
- Containers cannot access `/run/secrets/` or `~/.ssh/` (rootless user namespace + filesystem permissions)
- NixOS module: `virtualisation.podman = { enable = true; dockerCompat = true; }`

#### Network Policy
- Unrestricted internet access (no domain allowlisting, no proxy filtering)
- Tailscale network accessible directly from agent process
- No network namespace isolation (`--unshare-net` NOT used)
- Block link-local/metadata addresses (169.254.169.254) via iptables as cheap defense

#### Resource Limits
- Best-effort resource sharing -- no hard reservation split between agents and production
- Core services (SSH, Tailscale, Podman) protected from starvation via systemd slice weights
- Per-agent PID limit (e.g., 4096) -- prevents fork bombs
- Per-agent tmpfs size cap (e.g., 4GB) -- prevents disk exhaustion
- No per-agent memory or CPU hard caps -- Linux OOM killer handles runaway processes
- Existing agent-spawn cgroup slice configuration from Phase 5 provides the foundation

#### Agent UX & Opt-out
- Sandbox ON by default: `agent-spawn <name> <dir>` is sandboxed
- `--no-sandbox` for explicit opt-out (no reason required)
- Sandbox-aware error messages: when sandbox blocks access, agent sees helpful error
- `agent-spawn --show-policy` for introspecting what the sandbox allows
- Audit log: records all sandbox policy denials. Stored per-agent session.

### Claude's Discretion
- Exact `/etc` bind-mount set (resolv.conf, passwd, group, ssl certs, nix-related configs)
- Exact curated home dotfile list for bind-mounting
- Secrets access mechanism (completely hidden vs opt-in env var injection at spawn time)
- Audit log format and storage location
- Sandbox-aware error message implementation (custom wrapper vs LD_PRELOAD vs bubblewrap config)
- PID limit and tmpfs size exact values (4096 PIDs and 4GB tmpfs are starting points)
- OPA authz plugin as optional defense-in-depth layer on rootless Podman

### Deferred Ideas (OUT OF SCOPE)
- Network monitoring/filtering
- Copy-on-write overlay workspaces
- DNS exfiltration prevention
- Docker socket proxy with OPA
- gVisor/Sysbox integration
</user_constraints>

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| bubblewrap (bwrap) | 0.11.0 | Mount namespace isolation, filesystem policy | Used by Flatpak, Claude Code srt; in nixpkgs; zero overhead |
| podman | 5.8.0 | Rootless container runtime (Docker replacement) | NixOS native module; daemonless; user namespace isolated |
| systemd (slices/scopes) | (NixOS 25.11) | cgroup resource limits (TasksMax, CPUWeight) | Already in use from Phase 5 `agent.slice` |
| nftables | (NixOS 25.11) | Block metadata IP 169.254.169.254 | Already enabled in `modules/networking.nix` |

### Supporting
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `writeShellApplication` | Nix-native shell script packaging with runtimeInputs | Building the `agent-spawn` wrapper |
| `podman-compose` | Multi-container workflows via Podman | When agents need docker-compose equivalent |
| `socat` | (future) Proxy forwarding if network filtering added later | Not needed this phase |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| bubblewrap | Firejail | Firejail is higher-level but setuid, larger attack surface |
| bubblewrap | systemd-nspawn | Heavier, designed for full OS containers, requires root |
| rootless Podman | rootless Docker | Docker requires a per-user daemon; Podman is daemonless |
| nftables rules | iptables rules | NixOS already uses nftables backend; no reason to mix |

## Architecture Patterns

### Agent-Spawn Script Architecture

The sandbox wraps the existing `agent-spawn` flow. The execution order is:

```
agent-spawn <name> <dir> [agent] [--no-sandbox] [--show-policy]
  |
  +-> Parse args, validate project dir
  |
  +-> [--show-policy]: print sandbox policy and exit
  |
  +-> systemd-run --user --scope --slice=agent.slice \
        -p TasksMax=4096 \
        -p CPUWeight=100 \
        -- bwrap \
             [mount namespace flags] \
             [filesystem binds] \
             [lifecycle flags] \
             -- zmx run "$NAME" bash -c "cd '$PROJECT_DIR' && $CMD"
  |
  +-> Audit log: record session start, sandbox policy
```

### Recommended Module Structure

```
modules/
  agent-compute.nix       # EXISTING: extend with sandbox, podman
  (or split to:)
  agent-compute.nix       # Agent spawn, cgroup slices
  agent-sandbox.nix       # Bubblewrap policy, sandbox wrapper
  podman.nix              # Rootless podman config

home/
  agent-config.nix        # EXISTING: agent dotfile symlinks
```

**Recommendation:** Keep it in `agent-compute.nix` since the sandbox is tightly coupled to agent-spawn. Split only if the file exceeds ~150 lines.

### Pattern 1: Bubblewrap Mount Namespace on NixOS

**What:** Construct an explicit filesystem view using bwrap bind mounts. On NixOS, all binaries live in `/nix/store` with profile symlinks in `/run/current-system/sw/`, `/etc/profiles/per-user/`, and `~/.nix-profile/`.

**NixOS-specific bind-mount set:**
```bash
# Core Nix infrastructure (read-only)
--ro-bind /nix/store /nix/store
--ro-bind /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket  # nix build/develop
--ro-bind /nix/var/nix/db /nix/var/nix/db                        # nix store queries
--ro-bind /nix/var/nix/gcroots /nix/var/nix/gcroots              # GC root lookup

# NixOS system profile symlinks (read-only)
--ro-bind /run/current-system/sw /run/current-system/sw
--ro-bind /etc/profiles/per-user/dangirsh /etc/profiles/per-user/dangirsh

# User nix profile (read-only)
--ro-bind-try /home/dangirsh/.nix-profile /home/dangirsh/.nix-profile

# /etc files needed for system operation (read-only)
--ro-bind /etc/resolv.conf /etc/resolv.conf        # DNS resolution
--ro-bind /etc/passwd /etc/passwd                   # user identity lookup
--ro-bind /etc/group /etc/group                     # group membership lookup
--ro-bind /etc/ssl /etc/ssl                         # TLS certificate bundle
--ro-bind /etc/nix /etc/nix                         # nix.conf, registry
--ro-bind /etc/static /etc/static                   # NixOS managed /etc entries
--ro-bind-try /etc/hosts /etc/hosts                 # hostname resolution

# Virtual filesystems
--proc /proc                    # shared PID namespace (decision: no --unshare-pid)
--dev /dev                      # creates minimal devtmpfs
--tmpfs /tmp --size 4294967296  # 4GB ephemeral tmpfs

# Project directory (read-write)
--bind "$PROJECT_DIR" "$PROJECT_DIR"

# All of /data/projects read-only (sibling projects visible but not writable)
--ro-bind /data/projects /data/projects

# Curated home dotfiles (read-only)
--ro-bind /home/dangirsh/.gitconfig /home/dangirsh/.gitconfig
--ro-bind-try /home/dangirsh/.npmrc /home/dangirsh/.npmrc
--ro-bind-try /home/dangirsh/.claude /home/dangirsh/.claude
--ro-bind-try /home/dangirsh/.codex /home/dangirsh/.codex
--ro-bind-try /home/dangirsh/.config/git /home/dangirsh/.config/git

# Lifecycle and security
--die-with-parent
--new-session
--disable-userns           # prevent nested user namespace escape
--unshare-ipc              # IPC isolation
--unshare-uts              # hostname isolation
--hostname "sandbox-$NAME"
--chdir "$PROJECT_DIR"

# Environment
--clearenv
--setenv HOME /home/dangirsh
--setenv USER dangirsh
--setenv PATH "/run/current-system/sw/bin:/etc/profiles/per-user/dangirsh/bin:/home/dangirsh/.nix-profile/bin:/nix/var/nix/profiles/default/bin"
--setenv TERM "$TERM"
--setenv NIX_PATH "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
--setenv LANG "C.UTF-8"
```

**Critical notes:**
- The `--bind "$PROJECT_DIR" "$PROJECT_DIR"` MUST come AFTER `--ro-bind /data/projects /data/projects` because bwrap processes options sequentially and later mounts override earlier ones at the same path. This makes the specific project dir read-write while all sibling projects remain read-only.
- `--ro-bind-try` is used for paths that may not exist (e.g., `.npmrc`), preventing sandbox startup failures.
- `--disable-userns` requires `--unshare-user` (or implicit user namespace). This prevents an agent from creating a nested user namespace to escape mount restrictions.
- `--clearenv` + explicit `--setenv` prevents API key leakage from the parent shell environment.

### Pattern 2: Systemd Scope Resource Limits

**What:** Extend the existing `systemd-run --user --scope --slice=agent.slice` with `TasksMax` for PID limiting.

```bash
systemd-run --user --scope --slice=agent.slice \
  -p TasksMax=4096 \
  -p CPUWeight=100 \
  -- bwrap [flags] -- zmx run "$NAME" ...
```

The `TasksMax=4096` controls the `pids.max` cgroup attribute, preventing fork bombs. The agent.slice already exists from Phase 5 and provides the cgroup hierarchy.

**Note on `--size` for tmpfs:** bwrap's `--size` flag sets the tmpfs size limit directly (in bytes). `--tmpfs /tmp --size 4294967296` creates a 4GB tmpfs. This is a bwrap-level control, not a cgroup control.

### Pattern 3: Rootless Podman NixOS Module

**What:** Enable rootless Podman alongside existing Docker. Docker stays for host-level services; Podman is for agent sandboxes.

```nix
# In modules/agent-compute.nix (or a new modules/podman.nix)
virtualisation.podman = {
  enable = true;
  dockerCompat = true;   # creates `docker` -> `podman` alias
  defaultNetwork.settings.dns_enabled = true;
};

# Required: subordinate UID/GID ranges for rootless operation
users.users.dangirsh = {
  subUidRanges = [{ startUid = 100000; count = 65536; }];
  subGidRanges = [{ startGid = 100000; count = 65536; }];
};
```

**Gotcha:** `dockerCompat = true` creates a `docker` alias pointing to `podman`. This will conflict with the existing Docker installation. Resolution: Do NOT use `dockerCompat` at the system level. Instead, inside the sandbox, set `PATH` to include a directory with a `docker -> podman` symlink, or set `alias docker=podman` in the sandbox shell environment. The host keeps real Docker for non-sandboxed services.

### Pattern 4: Metadata IP Blocking

**What:** Block agent access to cloud metadata endpoints via nftables OUTPUT rule.

```nix
# In modules/networking.nix
networking.nftables.tables.agent-sandbox = {
  family = "ip";
  content = ''
    chain output {
      type filter hook output priority 0; policy accept;
      # Block cloud metadata endpoint (defense-in-depth)
      ip daddr 169.254.169.254 drop
    }
  '';
};
```

**Note:** This blocks ALL processes on the host from reaching the metadata IP, not just sandboxed agents. On a Contabo VPS, 169.254.169.254 is not used for any legitimate purpose, so this is safe. If granular per-process blocking is needed later, it requires network namespaces (deferred).

### Anti-Patterns to Avoid

- **Binding entire `/etc`:** Exposes shadow, sudoers, SSH host keys. Always use selective bind-mounts.
- **Binding `~/.ssh/`:** Decision explicitly prohibits this. SSH keys must never be visible to agents.
- **Using `--unshare-all` without `--share-net`:** The decision says NO network namespace isolation. Use selective namespace unsharing instead.
- **Binding Docker socket:** Docker socket = root-equivalent access. Decision explicitly prohibits.
- **Running bwrap as root:** Defeats the purpose. Always run as dangirsh via `systemd-run --user`.
- **Relying on `--unshare-pid` for process isolation:** Decision says shared PID namespace. Do NOT use `--unshare-pid`.
- **Using `--dev-bind /dev /dev`:** Exposes ALL host devices. Use `--dev /dev` for a minimal synthetic devtmpfs.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Filesystem isolation | Custom chroot/pivot_root | bubblewrap `--ro-bind`/`--bind` | bwrap handles mount namespace setup atomically, is well-audited |
| Container runtime for agents | Docker-in-sandbox wrappers | Rootless Podman | Daemonless, user-namespace isolated, NixOS module exists |
| PID limits | Custom process monitoring | systemd `TasksMax` | Kernel-enforced via cgroup pids controller |
| tmpfs size limits | Disk quota monitoring | bwrap `--tmpfs --size` | Built-in to bwrap, enforced by kernel tmpfs |
| Metadata IP blocking | Per-process firewall rules | System-wide nftables OUTPUT rule | Simple, no per-process complexity needed on VPS |
| Shell script packaging | Raw bash scripts | Nix `writeShellApplication` | runtimeInputs, shellcheck, reproducible PATH |

**Key insight:** bubblewrap provides all filesystem isolation primitives. The complexity is in assembling the right bind-mount policy -- not in building isolation mechanisms.

## Common Pitfalls

### Pitfall 1: Mount Order Matters in bwrap
**What goes wrong:** Agent's project directory is read-only despite `--bind` being specified.
**Why it happens:** bwrap processes mount options sequentially. If `--ro-bind /data/projects /data/projects` comes AFTER `--bind /data/projects/foo /data/projects/foo`, the read-only mount shadows the read-write one.
**How to avoid:** Always specify broader read-only mounts FIRST, then specific read-write mounts AFTER. The more-specific mount overrides the broader one only if it comes later.
**Warning signs:** Agent sees "Read-only filesystem" errors when trying to write to its project directory.

### Pitfall 2: bwrap User Namespace on Non-Setuid NixOS
**What goes wrong:** bwrap fails with "No permissions to create new namespace" or similar.
**Why it happens:** On NixOS, bwrap is NOT setuid. It relies on `kernel.unprivileged_userns_clone = 1` (the default on NixOS). If this sysctl is changed (e.g., by a security hardening module), bwrap breaks.
**How to avoid:** Ensure `boot.kernel.sysctl."kernel.unprivileged_userns_clone" = 1;` is set (it's the NixOS default but should be explicit if any hardening is applied).
**Warning signs:** bwrap exits with "Permission denied" before any mount operations.

### Pitfall 3: Podman dockerCompat Conflicts with Docker
**What goes wrong:** System-wide `dockerCompat = true` replaces the `docker` binary, breaking host Docker services.
**Why it happens:** `dockerCompat` creates a symlink/wrapper at `/run/current-system/sw/bin/docker` pointing to `podman`. Existing Docker containers managed by `virtualisation.docker` stop working.
**How to avoid:** Do NOT enable `dockerCompat` at the NixOS module level. Instead, create a sandbox-local PATH entry or alias. The sandboxed agent's `PATH` should include a directory with a `docker -> podman` symlink (built as a Nix derivation).
**Warning signs:** Docker containers fail to start, `docker ps` shows Podman output on the host.

### Pitfall 4: Missing /etc Files Break Toolchains
**What goes wrong:** `git`, `curl`, `npm` fail with mysterious errors inside the sandbox.
**Why it happens:** Missing `/etc/resolv.conf` (no DNS), missing `/etc/ssl/certs` (TLS failures), missing `/etc/passwd` (git can't determine author identity).
**How to avoid:** Test each major toolchain (git, curl, npm, cargo, nix) inside the sandbox during verification. Add missing `/etc` entries as discovered.
**Warning signs:** "Could not resolve host", "certificate verify failed", "unable to look up current user".

### Pitfall 5: --clearenv Breaks Agent Runtimes
**What goes wrong:** Claude Code or Codex CLI fail to start because expected environment variables are missing.
**Why it happens:** `--clearenv` removes ALL environment variables. Agent CLIs may need `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GITHUB_TOKEN`, `XDG_*` paths, `SHELL`, etc.
**How to avoid:** After `--clearenv`, explicitly `--setenv` every required variable. For API keys, read from sops secret files at spawn time and inject via `--setenv` (rather than relying on shell environment inheritance). This is actually MORE secure -- secrets come from sops, not from potentially-leaked shell env.
**Warning signs:** Agent CLI exits immediately with "API key not found" or "configuration error".

### Pitfall 6: Nix Daemon Socket Permissions
**What goes wrong:** `nix build` fails inside sandbox with "cannot connect to daemon at '/nix/var/nix/daemon-socket/socket'".
**Why it happens:** The nix daemon socket needs to be bind-mounted AND the user inside the sandbox needs permission to access it. The socket is owned by root:nixbld with mode 0666 by default.
**How to avoid:** Bind-mount the entire `/nix/var/nix/daemon-socket/` directory (not just the socket file, because systemd socket activation may recreate it). Also bind-mount `/nix/var/nix/db` for store queries and `/nix/var/nix/gcroots` for GC root lookups.
**Warning signs:** "cannot connect to daemon" or "permission denied" during `nix` commands.

### Pitfall 7: --disable-userns Requires --unshare-user
**What goes wrong:** bwrap exits with error when `--disable-userns` is specified without `--unshare-user`.
**Why it happens:** `--disable-userns` works by setting `user.max_user_namespaces = 1` inside a user namespace, then entering a nested user namespace. It requires the initial user namespace creation.
**How to avoid:** Always pair `--disable-userns` with `--unshare-user`. Use `--uid $(id -u)` and `--gid $(id -g)` to map the host user's UID/GID into the sandbox user namespace, preserving file ownership.
**Warning signs:** bwrap exits with "--disable-userns requires --unshare-user".

## Code Examples

### Complete agent-spawn Wrapper (Pseudocode)

```bash
#!/usr/bin/env bash
# agent-spawn: spawn a sandboxed coding agent
set -euo pipefail

NAME="${1:?Usage: agent-spawn <name> <project-dir> [claude|codex] [--no-sandbox] [--show-policy]}"
PROJECT_DIR="${2:?Usage: agent-spawn <name> <project-dir> [claude|codex] [--no-sandbox] [--show-policy]}"
AGENT="${3:-claude}"
NO_SANDBOX=false
SHOW_POLICY=false

# Parse optional flags
for arg in "$@"; do
  case "$arg" in
    --no-sandbox) NO_SANDBOX=true ;;
    --show-policy) SHOW_POLICY=true ;;
  esac
done

case "$AGENT" in
  claude) CMD="claude" ;;
  codex)  CMD="codex" ;;
  *)      echo "Unknown agent: $AGENT"; exit 1 ;;
esac

[ -d "$PROJECT_DIR" ] || { echo "Error: $PROJECT_DIR does not exist"; exit 1; }
PROJECT_DIR="$(realpath "$PROJECT_DIR")"

# Resolve API keys from sops secrets (owner=dangirsh, readable)
ANTHROPIC_KEY="$(cat /run/secrets/anthropic-api-key 2>/dev/null || true)"
OPENAI_KEY="$(cat /run/secrets/openai-api-key 2>/dev/null || true)"
GITHUB_TOKEN="$(cat /run/secrets/github-pat 2>/dev/null || true)"

# Define sandbox policy
BWRAP_ARGS=(
  # --- Namespace isolation ---
  --unshare-user --uid "$(id -u)" --gid "$(id -g)"
  --unshare-ipc
  --unshare-uts
  --disable-userns
  --hostname "sandbox-${NAME}"
  --die-with-parent
  --new-session

  # --- Nix store + daemon (read-only) ---
  --ro-bind /nix/store /nix/store
  --ro-bind /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket
  --ro-bind /nix/var/nix/db /nix/var/nix/db
  --ro-bind /nix/var/nix/gcroots /nix/var/nix/gcroots

  # --- NixOS profiles (read-only) ---
  --ro-bind /run/current-system/sw /run/current-system/sw
  --ro-bind /run/current-system/etc /run/current-system/etc
  --ro-bind-try /etc/profiles/per-user/dangirsh /etc/profiles/per-user/dangirsh
  --ro-bind-try /home/dangirsh/.nix-profile /home/dangirsh/.nix-profile

  # --- /etc selective (read-only) ---
  --ro-bind /etc/resolv.conf /etc/resolv.conf
  --ro-bind /etc/passwd /etc/passwd
  --ro-bind /etc/group /etc/group
  --ro-bind /etc/ssl /etc/ssl
  --ro-bind /etc/nix /etc/nix
  --ro-bind /etc/static /etc/static
  --ro-bind-try /etc/hosts /etc/hosts
  --ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf
  --ro-bind-try /etc/login.defs /etc/login.defs
  --ro-bind-try /etc/subuid /etc/subuid
  --ro-bind-try /etc/subgid /etc/subgid
  --ro-bind-try /etc/containers /etc/containers

  # --- Virtual filesystems ---
  --proc /proc
  --dev /dev
  --tmpfs /tmp --size 4294967296

  # --- Project + sibling read-only ---
  --ro-bind /data/projects /data/projects
  --bind "$PROJECT_DIR" "$PROJECT_DIR"

  # --- Curated home dotfiles (read-only) ---
  --dir /home/dangirsh
  --ro-bind-try /home/dangirsh/.gitconfig /home/dangirsh/.gitconfig
  --ro-bind-try /home/dangirsh/.npmrc /home/dangirsh/.npmrc
  --ro-bind-try /home/dangirsh/.claude /home/dangirsh/.claude
  --ro-bind-try /home/dangirsh/.codex /home/dangirsh/.codex
  --ro-bind-try /home/dangirsh/.config/git /home/dangirsh/.config/git
  --ro-bind-try /home/dangirsh/.local/share/containers /home/dangirsh/.local/share/containers

  # --- Podman support (rootless) ---
  --bind-try /run/user/"$(id -u)"/containers /run/user/"$(id -u)"/containers
  --ro-bind-try /run/user/"$(id -u)"/podman /run/user/"$(id -u)"/podman

  # --- Environment ---
  --clearenv
  --setenv HOME /home/dangirsh
  --setenv USER dangirsh
  --setenv SHELL /bin/bash
  --setenv TERM "${TERM:-xterm-256color}"
  --setenv LANG C.UTF-8
  --setenv PATH "/run/current-system/sw/bin:/etc/profiles/per-user/dangirsh/bin:/home/dangirsh/.nix-profile/bin:/nix/var/nix/profiles/default/bin"
  --setenv SANDBOX "1"
  --setenv SANDBOX_NAME "$NAME"
  --setenv SANDBOX_PROJECT "$PROJECT_DIR"

  --chdir "$PROJECT_DIR"
)

# Inject API keys if available
[ -n "$ANTHROPIC_KEY" ] && BWRAP_ARGS+=(--setenv ANTHROPIC_API_KEY "$ANTHROPIC_KEY")
[ -n "$OPENAI_KEY" ] && BWRAP_ARGS+=(--setenv OPENAI_API_KEY "$OPENAI_KEY")
[ -n "$GITHUB_TOKEN" ] && BWRAP_ARGS+=(--setenv GITHUB_TOKEN "$GITHUB_TOKEN")

if [ "$SHOW_POLICY" = true ]; then
  echo "=== Sandbox Policy for '$NAME' ==="
  echo "Project dir (rw): $PROJECT_DIR"
  echo "Sibling projects: /data/projects (ro)"
  echo "Nix store: /nix/store (ro)"
  echo "Nix daemon: /nix/var/nix/daemon-socket (ro)"
  echo "Network: unrestricted (shared namespace)"
  echo "PID namespace: shared (host-visible)"
  echo "tmpfs /tmp: 4GB"
  echo "TasksMax: 4096"
  echo "Hidden: /run/secrets, ~/.ssh, /var/run/docker.sock"
  echo "Podman: rootless (available)"
  echo "User namespace: isolated (--disable-userns)"
  exit 0
fi

# Audit log
AUDIT_DIR="/data/projects/.agent-audit"
mkdir -p "$AUDIT_DIR"
AUDIT_FILE="$AUDIT_DIR/${NAME}-$(date +%Y%m%d-%H%M%S).log"
echo "$(date -Iseconds) SPAWN agent=$AGENT name=$NAME project=$PROJECT_DIR sandbox=$( [ "$NO_SANDBOX" = true ] && echo "off" || echo "on")" >> "$AUDIT_FILE"

if [ "$NO_SANDBOX" = true ]; then
  systemd-run --user --scope --slice=agent.slice \
    -p TasksMax=4096 -p CPUWeight=100 \
    -- zmx run "$NAME" bash -c "cd '$PROJECT_DIR' && $CMD"
else
  systemd-run --user --scope --slice=agent.slice \
    -p TasksMax=4096 -p CPUWeight=100 \
    -- bwrap "${BWRAP_ARGS[@]}" \
    -- zmx run "$NAME" bash -c "$CMD"
fi

echo "Agent '$NAME' spawned in zmx session (agent.slice, sandbox=$( [ "$NO_SANDBOX" = true ] && echo "off" || echo "on"))"
echo "Attach: zmx attach $NAME"
```

### NixOS Module: Rootless Podman

```nix
# Addition to modules/agent-compute.nix or new modules/podman.nix
{ config, pkgs, ... }: {
  virtualisation.podman = {
    enable = true;
    # NOTE: Do NOT set dockerCompat = true here -- it conflicts with host Docker
    defaultNetwork.settings.dns_enabled = true;
  };

  # Rootless podman requires subordinate UID/GID ranges
  users.users.dangirsh = {
    subUidRanges = [{ startUid = 100000; count = 65536; }];
    subGidRanges = [{ startGid = 100000; count = 65536; }];
  };

  # Podman tools available system-wide
  environment.systemPackages = with pkgs; [
    podman-compose
  ];
}
```

### Sandbox-Local Docker Compat Derivation

```nix
# Create a directory with docker -> podman symlink for sandbox PATH
sandbox-docker-compat = pkgs.runCommandNoCC "sandbox-docker-compat" {} ''
  mkdir -p $out/bin
  ln -s ${pkgs.podman}/bin/podman $out/bin/docker
'';
```

Then add `${sandbox-docker-compat}/bin` to the sandbox's PATH so agents can run `docker` commands that actually invoke `podman`.

### Metadata IP Block

```nix
# In modules/networking.nix
networking.nftables.tables.agent-metadata-block = {
  family = "ip";
  content = ''
    chain output {
      type filter hook output priority 0; policy accept;
      ip daddr 169.254.169.254 drop
    }
  '';
};
```

## Discretion Recommendations

### /etc Bind-Mount Set (HIGH confidence)

Based on analysis of what NixOS tools need and what nixwrap/nixpak bind:

| Path | Required By | Notes |
|------|-------------|-------|
| `/etc/resolv.conf` | DNS resolution (curl, npm, git, nix) | Critical |
| `/etc/passwd` | User identity (git, ssh, nix) | Critical |
| `/etc/group` | Group membership | Critical |
| `/etc/ssl` | TLS certificates (curl, npm, pip) | Critical |
| `/etc/nix` | nix.conf, registry.json | Required for nix commands |
| `/etc/static` | NixOS-managed /etc entries | Contains resolv.conf, hosts, etc. on NixOS |
| `/etc/hosts` | Local hostname resolution | Important |
| `/etc/nsswitch.conf` | Name service switch config | Used by glibc for passwd/group/host lookups |
| `/etc/subuid`, `/etc/subgid` | Rootless Podman UID mapping | Required for podman |
| `/etc/containers` | Podman configuration | registries.conf, policy.json |
| `/etc/login.defs` | UID range definitions | Used by newuidmap |

**Do NOT bind:** `/etc/shadow`, `/etc/sudoers`, `/etc/ssh/` (host keys), `/etc/machine-id` (fingerprinting).

### Curated Home Dotfile List (HIGH confidence)

| Path | Purpose | Notes |
|------|---------|-------|
| `~/.gitconfig` | Git identity and settings | Agents need to commit |
| `~/.npmrc` | npm registry config | Private registry access |
| `~/.claude` | Claude Code config | Agent configuration |
| `~/.codex` | Codex CLI config | Agent configuration |
| `~/.config/git/` | Git config directory (XDG) | Some setups use this |
| `~/.local/share/containers/` | Podman container storage | Bind rw for rootless podman |

**Do NOT bind:** `~/.ssh/` (decision: invisible), `~/.gnupg/`, `~/.aws/`, `~/.docker/` (contains Docker auth tokens).

### Secrets Access Mechanism (HIGH confidence)

**Recommendation: Opt-in env var injection at spawn time.**

Agents do NOT see `/run/secrets/` (decision: completely invisible). Instead, `agent-spawn` reads specific sops secrets at launch and injects them via `--setenv`:

```bash
ANTHROPIC_KEY="$(cat /run/secrets/anthropic-api-key 2>/dev/null || true)"
[ -n "$ANTHROPIC_KEY" ] && BWRAP_ARGS+=(--setenv ANTHROPIC_API_KEY "$ANTHROPIC_KEY")
```

**Rationale:**
- Secrets are only in the process environment, not on any filesystem path
- `--clearenv` ensures no accidental leakage from parent shell
- Only the specific secrets needed for agent operation are injected
- If an agent is compromised, it can read its own env vars (unavoidable), but cannot access OTHER secrets in `/run/secrets/`
- This is the same pattern Claude Code's own srt uses

### Audit Log Format and Location (MEDIUM confidence)

**Recommendation:** Simple append-only text log per agent session.

**Location:** `/data/projects/.agent-audit/` (inside the projects directory, not in /tmp or /var)

**Format:**
```
2026-02-17T14:30:00+01:00 SPAWN agent=claude name=feature-x project=/data/projects/foo sandbox=on
2026-02-17T14:30:01+01:00 POLICY paths_ro=[/nix/store,/data/projects,...] paths_rw=[/data/projects/foo] tasks_max=4096 tmpfs_size=4GB
2026-02-17T15:45:00+01:00 EXIT agent=claude name=feature-x code=0 duration=4500s
```

**Rationale:** Simple text is greppable, requires no tooling, and survives sandbox teardown since the audit dir is bind-mounted read-write (or written before sandbox entry). Complex structured logging (JSON, systemd journal) adds dependencies without proportional value at this scale.

**Note:** Filesystem-level denial logging (blocked path access attempts) is NOT trivially achievable with bubblewrap alone. Blocked paths simply don't exist in the mount namespace -- there's no EACCES to log. The audit log records policy at spawn time. For runtime denial detection, the sandbox-aware error messages (see below) provide user-facing feedback.

### Sandbox-Aware Error Messages (MEDIUM confidence)

**Recommendation: Custom wrapper script approach.**

Rather than LD_PRELOAD (fragile, complex) or seccomp audit (floods logs), use a simple wrapper approach:

1. Set `SANDBOX=1` environment variable inside the sandbox
2. Agent tooling (CLAUDE.md instructions, shell aliases) can check this variable
3. For common blocked operations, provide a shell function:

```bash
# Sourced in sandbox shell profile
sandbox-check() {
  if [ "${SANDBOX:-0}" = "1" ]; then
    case "$1" in
      ssh) echo "Blocked by sandbox: ~/.ssh/ is not accessible. Use --no-sandbox if needed." ;;
      docker) echo "Blocked by sandbox: Docker socket not available. Use 'podman' instead." ;;
      secrets) echo "Blocked by sandbox: /run/secrets/ is not accessible. API keys are in env vars." ;;
    esac
    return 1
  fi
}
```

This is pragmatic and zero-overhead. Agents will naturally see "No such file or directory" for missing paths, which is informative enough. The custom wrapper adds polish for the most common confusion points.

### PID Limit and tmpfs Size Values (HIGH confidence)

| Parameter | Recommended Value | Rationale |
|-----------|-------------------|-----------|
| TasksMax | 4096 | Claude Code spawns subprocesses (node, ripgrep, git, nix). 4096 is generous for development workloads. Fork bombs hit this quickly. Linux default is 32768 per user. |
| tmpfs /tmp size | 4 GB (4294967296 bytes) | Nix builds can produce large intermediate artifacts in /tmp. 4GB is enough for most builds. With 96GB RAM on the VPS, 4GB per agent is sustainable for ~20 concurrent agents. |

### OPA Authz Plugin for Podman (LOW confidence -- skip for now)

**Recommendation: Do not implement OPA in this phase.**

OPA authz for Docker/Podman is designed for the Docker daemon's authorization plugin API. Rootless Podman is daemonless -- there is no authorization plugin hook. The OPA approach only works with rootful Docker daemon or Podman run as a service. Since rootless Podman's security comes from user namespaces (container escape = unprivileged user), OPA adds no value here.

**If needed later:** The deferred "Docker socket proxy with OPA" approach would only apply if host Docker socket access is ever re-enabled (currently blocked by decision).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Docker-in-Docker (DinD) | Rootless Podman | Podman 4.x+ (2023) | No daemon, user namespace isolation, OCI-compatible |
| Firejail (setuid) | bubblewrap (unprivileged) | bwrap 0.3+ with user namespaces | Smaller attack surface, no setuid binary needed |
| Manual chroot | bwrap mount namespace | bwrap 0.1.0 (2016) | Atomic namespace setup, auto-cleanup |
| iptables firewall | nftables | NixOS 21.11+ | Native NixOS support, cleaner syntax |
| Docker --iptables=true | Docker --iptables=false + NixOS nat | Phase 3 decision | NixOS owns the firewall, not Docker |
| bwrap basic mounts | bwrap overlayfs (0.11.0) | December 2024 | Copy-on-write overlays for future workspace isolation |

**Deprecated/outdated:**
- `--unshare-all` as the default approach: Decisions override this -- use selective namespace unsharing
- setuid bwrap: NixOS uses unprivileged user namespaces instead
- `dockerCompat = true` with co-existing Docker: conflicts -- use sandbox-local PATH instead

## Open Questions

1. **bwrap implicit user namespace on NixOS**
   - What we know: On non-setuid installs, bwrap may implicitly create a user namespace for mount operations even without `--unshare-user`. The `--disable-userns` flag requires `--unshare-user`.
   - What's unclear: Whether bwrap without explicit `--unshare-user` can still do `--bind`/`--ro-bind` on NixOS. Need to test on the target system.
   - Recommendation: Use explicit `--unshare-user --uid $(id -u) --gid $(id -g)` to be deterministic. This creates a user namespace but maps the invoking user's UID/GID, so file ownership on bind-mounted directories is preserved.

2. **Rootless Podman inside bubblewrap user namespace**
   - What we know: Rootless Podman itself uses user namespaces (via newuidmap/newgidmap). Running it inside a bubblewrap sandbox that also uses a user namespace means nested user namespaces.
   - What's unclear: Whether `--disable-userns` prevents Podman from creating its own user namespace. If it does, Podman breaks.
   - Recommendation: Test on target system. If `--disable-userns` blocks Podman, remove it and rely on rootless Podman's own security model. The mount namespace isolation (hidden secrets/ssh) still provides the primary defense.

3. **NixOS /etc/static symlink resolution**
   - What we know: On NixOS, `/etc` entries are managed via `/etc/static` (a symlink farm pointing to /nix/store). Binding individual `/etc/foo` files works if they're real files or if the bind follows the symlink.
   - What's unclear: Whether bwrap `--ro-bind /etc/resolv.conf /etc/resolv.conf` follows the NixOS `/etc/static/resolv.conf` -> `/nix/store/...` symlink chain correctly.
   - Recommendation: Test on target. If symlinks break, bind `/etc/static` and create `/etc` -> `/etc/static` symlinks, or bind the resolved paths directly.

4. **zmx inside bwrap**
   - What we know: zmx is a terminal multiplexer (like tmux). It needs to create Unix sockets for session management.
   - What's unclear: Where zmx stores its socket (likely `/tmp/` or `/run/user/UID/`). If it's in `/tmp`, the per-agent tmpfs handles it. If it's in `/run/user/`, we need to bind-mount that.
   - Recommendation: Test zmx inside bwrap. May need `--bind /run/user/$(id -u) /run/user/$(id -u)` or specific zmx socket directory.

## Sources

### Primary (HIGH confidence)
- bwrap 0.11.0 `--help` output -- confirmed all flags available locally
- `nix eval nixpkgs#bubblewrap.version` = "0.11.0" -- confirmed in nixpkgs
- `nix eval nixpkgs#podman.version` = "5.8.0" -- confirmed in nixpkgs
- NixOS system: `kernel.unprivileged_userns_clone = 1` -- confirmed
- Existing `modules/agent-compute.nix` -- Phase 5 agent-spawn implementation
- Existing `modules/docker.nix` -- Docker configuration to coexist with Podman
- Existing `modules/secrets.nix` -- sops secrets that sandbox hides
- Existing `modules/networking.nix` -- nftables configuration to extend

### Secondary (MEDIUM confidence)
- [Bubblewrap ArchWiki](https://wiki.archlinux.org/title/Bubblewrap) -- comprehensive flag documentation
- [Bubblewrap Examples ArchWiki](https://wiki.archlinux.org/title/Bubblewrap/Examples) -- mount order patterns
- [Claude Code srt analysis](https://www.sambaiz.net/en/article/547/) -- bwrap usage in production agent sandbox
- [NixOS Podman Wiki](https://wiki.nixos.org/wiki/Podman) -- rootless Podman NixOS module
- [bwrap man page (Debian)](https://manpages.debian.org/unstable/bubblewrap/bwrap.1.en.html) -- complete flag reference
- [Linux sandboxing with bubblewrap](https://www.staldal.nu/tech/2025/10/19/linux-sandboxing-with-bubblewrap/) -- practical NixOS-adjacent sandbox patterns
- [Sandboxing with bubblewrap blog](https://sloonz.github.io/posts/sandboxing-1/) -- /etc handling, --clearenv rationale
- [nixwrap source](https://github.com/rti/nixwrap) -- NixOS-specific bwrap wrapper patterns
- [systemd.resource-control](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html) -- TasksMax, CPUWeight documentation
- [NixOS Firewall Wiki](https://wiki.nixos.org/wiki/Firewall) -- nftables custom tables
- [bubblewrap releases](https://github.com/containers/bubblewrap/releases) -- 0.11.0 overlay features, 0.8.0 --disable-userns

### Tertiary (LOW confidence -- needs validation on target)
- Podman inside bubblewrap user namespace -- no authoritative source; needs testing
- NixOS /etc/static symlink resolution via bwrap --ro-bind -- needs testing
- zmx socket location -- needs testing

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- bubblewrap and Podman versions confirmed in nixpkgs, flags verified
- Architecture: HIGH -- bwrap flag semantics well-documented, NixOS path structure understood
- Pitfalls: HIGH -- mount ordering, namespace conflicts, /etc requirements documented by multiple sources
- Discretion areas: MEDIUM-HIGH -- recommendations based on documented patterns, but 4 items need target-system validation

**Research date:** 2026-02-17
**Valid until:** 2026-03-17 (30 days -- stable tools, unlikely to change)
