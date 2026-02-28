# Phase 40: agentd Integration — Research

**Completed:** 2026-02-28
**Objective:** What do I need to know to PLAN this phase well?

---

## 1. agentd Architecture Deep Dive

### What agentd is

agentd (`github:papercomputeco/agentd`) is the agent management daemon from the stereOS ecosystem. Written in Go, it manages a single agent's lifecycle within a tmux session using a Kubernetes-inspired reconciliation loop. Each instance reads one `jcard.toml` config file and one secrets directory, hashes both with SHA256, and restarts the agent whenever either changes.

**Source:** https://github.com/papercomputeco/agentd

### Core Design

```
                    agentd (Go daemon, runs as root)
                        |
        +---------------+---------------+
        |               |               |
   Reconcile Loop   HTTP API        tmux Server
   (5s interval)    (Unix socket)   (private socket)
        |               |               |
   jcard.toml +     /v1/health      Agent session
   secrets dir      /v1/agents      (send-keys, has-session)
   SHA256 watch     /v1/agents/{n}
```

### Reconciliation Loop

- Ticks every 5 seconds (configurable via `-reconcile-interval` CLI flag, NOT via jcard.toml)
- First reconciliation runs immediately on startup
- Reads jcard.toml as raw bytes, reads all secrets from secret dir
- Computes SHA256 of each, compares to cached hashes
- If EITHER hash changed AND manager is running: **full stop + restart** (no partial update)
- If nothing changed and manager is running: no-op
- If nothing running: create new manager and start

### Agent Execution Modes

agentd supports two execution modes (`type` field in jcard.toml):

| Type | Implementation | Session Tracking |
|------|---------------|------------------|
| `native` (default for neurosys) | tmux session, direct execution | tmux has-session, send-keys |
| `sandboxed` | gVisor/runsc OCI container | runsc container state |

**For neurosys, we use `native` mode** because we want bubblewrap (our existing sandbox), not gVisor. agentd's `native` mode runs the agent in a tmux session and we wrap the command with bwrap via the `custom` harness.

### Harness System

Harnesses define how agent binaries are invoked. Each implements:
```go
type Harness interface {
    Name() string
    BuildCommand(prompt string) (bin string, args []string)
}
```

Built-in harnesses:
| Harness | Binary | Prompt |
|---------|--------|--------|
| `claude-code` | `claude` | `-p <prompt>` |
| `opencode` | `opencode` | `--prompt <prompt>` |
| `gemini-cli` | `gemini` | positional arg |
| `custom` | configurable (default: `agent`) | positional arg |

**For neurosys:** The `custom` harness is the right choice. We set the binary to our bwrap wrapper script and pass the agent binary as part of the bwrap arguments. This preserves the existing bubblewrap sandbox without modifying agentd.

### Session Management (tmux internals)

agentd uses these tmux subcommands internally:
- `new-session -d` -- create detached session
- `has-session` -- check if session exists (exit code 1 = absent)
- `send-keys` + `Enter` -- type command into session
- `send-keys C-c` -- send SIGINT for graceful shutdown
- `kill-session` -- destroy session
- `kill-server` -- terminate all sessions
- `list-sessions` -- enumerate active sessions

The tmux server uses an isolated socket at `/run/agentd/tmux.sock` (mode 0770, group `admin`). All tmux commands run via `sudo -u agent` to satisfy tmux's UID-based socket ownership checks.

**Admin users can attach for debugging:**
```bash
sudo tmux -S /run/agentd/tmux.sock attach -t session-name
```

### Restart Policies

| Policy | Behavior | Use Case |
|--------|----------|----------|
| `no` | Never restart after exit | Ad-hoc coding agents |
| `on-failure` | Restart on non-zero exit, up to `max_restarts` | Semi-supervised agents |
| `always` | Restart unconditionally, up to `max_restarts` (0=unlimited) | Autonomous agents |

Monitor loop polls every 2 seconds. 3-second backoff between restart attempts.

Graceful shutdown: sends C-c (SIGINT), waits `grace_period` (default 30s), then forcibly destroys session.

### HTTP API

Read-only Unix socket at `/run/stereos/agentd.sock` (mode 0660, group `admin`):

| Endpoint | Response |
|----------|----------|
| `GET /v1/health` | `{"state":"running","uptime_seconds":123}` |
| `GET /v1/agents` | `[{"name":"...","running":true,"session":"...","restarts":0}]` |
| `GET /v1/agents/{name}` | Single agent object (404 if not found, case-insensitive) |

### Secrets Loading

Directory-based: `/run/stereos/secrets/` (configurable via `-secret-dir`).
- Each file = one secret: filename = env var name, content = value
- Hidden files (`.` prefix) skipped
- Trailing newlines trimmed
- Missing directory = empty map
- `[agent.env]` values override secrets with same name

### Default Paths

```
DefaultConfigPath      = /etc/stereos/jcard.toml
DefaultAPISocketPath   = /run/stereos/agentd.sock
SecretDir              = /run/stereos/secrets
TmuxSocketPath         = /run/agentd/tmux.sock
DefaultSandboxStateDir = /run/agentd/runsc-state
DefaultSandboxBundleDir = /run/agentd/sandboxes
```

### NixOS Module (upstream)

The agentd flake (`github:papercomputeco/agentd`) exports:
- `overlays.default` -- adds `agentd` package (Go buildGoModule)
- `nixosModules.default` -- basic systemd service with 3 options:
  - `services.agentd.enable` (bool)
  - `services.agentd.package` (package)
  - `services.agentd.extraArgs` (list of strings)

The upstream module uses `DynamicUser=true` and `StateDirectory=agentd`. The stereOS module overrides this to `DynamicUser=false` and runs as root (needed to manage agent user's tmux sessions via sudo).

### CLI Flags

```
-config          jcard.toml path
-api-socket      Unix socket for API
-secret-dir      Secrets directory
-tmux-socket     tmux socket path
-runsc-path      gVisor binary (unused in native mode)
-sandbox-state-dir   (unused in native mode)
-sandbox-bundle-dir  (unused in native mode)
-debug           Enable debug logging
```

---

## 2. jcard.toml Configuration Schema

### Complete Field Reference

```toml
[agent]
# Required
harness = "custom"              # Harness type: claude-code|opencode|gemini-cli|custom

# Execution mode
type = "native"                 # native (tmux) or sandboxed (gVisor). Default: sandboxed.

# Prompt (optional)
prompt = ""                     # Inline prompt text
prompt_file = "./prompts/x.md"  # File path (overrides prompt if set)

# Directories
workdir = "/home/agent/workspace"  # Default working directory

# Lifecycle
restart = "no"                  # no|on-failure|always. Default: no.
max_restarts = 0                # 0 = unlimited. Default: 0.
timeout = ""                    # Go duration: "2h", "30m". Empty = no timeout.
grace_period = "30s"            # SIGINT grace window. Default: 30s.

# Session
session = ""                    # tmux session name. Default: harness name.

# Sandbox-only (irrelevant for native mode)
memory = "2GiB"                 # Memory limit (sandboxed only)
pid_limit = 512                 # PID limit (sandboxed only)
extra_packages = []             # Additional Nix packages (sandboxed only)

# Environment
[agent.env]
CUSTOM_VAR = "value"            # Additional env vars (override secrets)
```

### Validation Rules
- `harness` is required, must be one of the registered harness names
- `timeout` and `grace_period` must parse as Go time.Duration
- `memory` and `pid_limit` validated only for sandboxed agents
- `extra_packages` entries cannot be empty strings

---

## 3. zmx vs. tmux Compatibility Assessment

### zmx Subcommands

zmx (`github:neurosnap/zmx`, version 0.3.0) supports:
- `run <name> [command...]` -- send command without attaching
- `attach <name> [command...]` -- attach to session
- `detach` -- detach from current session
- `list [--short]` -- list active sessions
- `kill <name>` -- kill a session
- `history <name>` -- session scrollback
- `wait <name>...` -- wait for session tasks
- `version`, `completions`, `help`

### tmux Subcommands Required by agentd

agentd's `pkg/tmux/tmux.go` uses:
- `new-session -d` -- **NO zmx equivalent** (zmx uses `run`)
- `has-session -t <name>` -- **NO zmx equivalent** (zmx has `list` but not a single-session existence check by exit code)
- `send-keys <text> Enter` -- **NO zmx equivalent** (zmx has no send-keys)
- `send-keys C-c` -- **NO zmx equivalent**
- `kill-session -t <name>` -- zmx has `kill <name>` (similar but different flags)
- `kill-server` -- **NO zmx equivalent**
- `list-sessions` -- zmx has `list --short` (different output format)

### Verdict: zmx is NOT a drop-in replacement for agentd's tmux usage

zmx deliberately avoids tmux's session management primitives. It is designed for session persistence (run-and-detach), not for programmatic session control (send-keys, has-session checks, graceful C-c shutdown).

**Recommendation:** Accept tmux as agentd's invisible internal detail. agentd owns its own tmux socket (`/run/agentd/tmux.sock`), never exposed to users. zmx stays available on PATH for human-initiated sessions if ever needed, but agentd does not use it.

This aligns with the user's philosophy: tmux is plumbing inside agentd, not a user interface. Humans interact with agents via the HTTP API and homepage dashboard.

---

## 4. Multi-Instance Architecture

### Decision: One agentd per agent

Each agent gets its own:
- systemd service: `agentd-<name>.service`
- jcard.toml: `/etc/agentd/<name>/jcard.toml`
- API socket: `/run/agentd/<name>/agentd.sock`
- tmux socket: `/run/agentd/<name>/tmux.sock`
- Secrets directory: `/run/agentd/<name>/secrets/`

### Why per-instance, not multi-agent

agentd is designed for a single agent per instance. Its reconciliation loop watches one jcard.toml and one secrets directory. The code manages one `AgentManager` instance. Multiple agents = multiple agentd processes. This is the correct approach given the decision that each agent has its own NixOS systemd service.

### Path Overrides per Instance

Each instance uses CLI flags to override default paths:
```bash
agentd \
  -config /etc/agentd/neurosys-dev/jcard.toml \
  -api-socket /run/agentd/neurosys-dev/agentd.sock \
  -tmux-socket /run/agentd/neurosys-dev/tmux.sock \
  -secret-dir /run/agentd/neurosys-dev/secrets/
```

---

## 5. NixOS Module Design (Claude's Discretion)

### Proposed Schema: `services.agentd.agents`

```nix
services.agentd.agents = {
  neurosys-dev = {
    enable = true;
    harness = "custom";
    command = "/path/to/bwrap-wrapper-script";
    workdir = "/data/projects/neurosys";
    restart = "no";
    env = {
      ANTHROPIC_API_KEY = "injected-via-EnvironmentFile";
    };
  };

  conway-automaton = {
    enable = true;
    harness = "custom";
    command = "/path/to/automaton-bwrap-wrapper";
    prompt = "You are awakening...";
    workdir = "/data/projects/conway";
    restart = "always";
    maxRestarts = 0;
    gracePeriod = "60s";
  };

  claw-swap-dev = {
    enable = true;
    harness = "custom";
    command = "/path/to/bwrap-wrapper-script";
    workdir = "/data/projects/claw-swap";
    restart = "no";
    env = {
      ANTHROPIC_BASE_URL = "http://127.0.0.1:9091";
    };
  };
};
```

### Option Types

```nix
services.agentd.agents = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule {
    options = {
      enable = lib.mkEnableOption "this agentd agent instance";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.agentd;
        description = "The agentd package to use";
      };

      harness = lib.mkOption {
        type = lib.types.enum [ "claude-code" "opencode" "gemini-cli" "custom" ];
        default = "custom";
        description = "Agent harness type";
      };

      command = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Binary path for custom harness (required when harness=custom)";
      };

      prompt = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Inline startup prompt (empty = interactive mode)";
      };

      promptFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Prompt file path (overrides prompt)";
      };

      workdir = lib.mkOption {
        type = lib.types.str;
        default = "/data/projects";
        description = "Agent working directory";
      };

      restart = lib.mkOption {
        type = lib.types.enum [ "no" "on-failure" "always" ];
        default = "no";
        description = "Restart policy";
      };

      maxRestarts = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Maximum restart attempts (0 = unlimited)";
      };

      timeout = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Agent timeout (Go duration format, empty = no timeout)";
      };

      gracePeriod = lib.mkOption {
        type = lib.types.str;
        default = "30s";
        description = "SIGINT grace period before force kill";
      };

      env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
        description = "Additional environment variables (override secrets)";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to EnvironmentFile for systemd (typically sops template)";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = "User to run agentd as (root required for tmux sudo)";
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Extra CLI arguments passed to agentd";
      };
    };
  });
  default = {};
};
```

### jcard.toml Rendering

Each agent's attrset renders to `/etc/agentd/<name>/jcard.toml`:

```nix
environment.etc."agentd/${name}/jcard.toml".text = ''
  [agent]
  type = "native"
  harness = "${cfg.harness}"
  prompt = "${cfg.prompt}"
  workdir = "${cfg.workdir}"
  restart = "${cfg.restart}"
  max_restarts = ${toString cfg.maxRestarts}
  grace_period = "${cfg.gracePeriod}"
  ${lib.optionalString (cfg.timeout != "") ''timeout = "${cfg.timeout}"''}
  session = "${name}"

  [agent.env]
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''${k} = "${v}"'') cfg.env)}
'';
```

### Systemd Service Generation

Each enabled agent generates `systemd.services."agentd-${name}"`:

```nix
systemd.services."agentd-${name}" = {
  description = "agentd agent: ${name}";
  after = [ "network-online.target" "sops-nix.service" ];
  wants = [ "network-online.target" ];
  wantedBy = [ "multi-user.target" ];

  path = [ pkgs.tmux pkgs.sudo pkgs.bubblewrap ];

  serviceConfig = {
    ExecStart = "${cfg.package}/bin/agentd -config /etc/agentd/${name}/jcard.toml -api-socket /run/agentd/${name}/agentd.sock -tmux-socket /run/agentd/${name}/tmux.sock -secret-dir /run/agentd/${name}/secrets/";
    RuntimeDirectory = "agentd/${name}";
    DynamicUser = false;
    User = "root";  # Required for tmux sudo to agent user
    Restart = "on-failure";
    RestartSec = 5;
  } // lib.optionalAttrs (cfg.environmentFile != null) {
    EnvironmentFile = cfg.environmentFile;
  };
};
```

---

## 6. bubblewrap Integration via Custom Harness

### Architecture

agentd's `custom` harness allows specifying any binary. We set it to a wrapper script that invokes bwrap with the existing sandbox arguments:

```
agentd
  -> tmux new-session
    -> custom harness binary (= bwrap-wrapper)
      -> bwrap <sandbox-args> -- claude
```

### Wrapper Script Design

Instead of the monolithic `agent-spawn` bash script, each agent gets a NixOS-generated wrapper:

```nix
agentd-bwrap-wrapper = pkgs.writeShellScript "agentd-bwrap-${name}" ''
  exec bwrap \
    --unshare-user --uid $UID --gid $GID \
    --unshare-ipc --unshare-uts --unshare-pid --unshare-cgroup \
    --disable-userns \
    --hostname "sandbox-${name}" \
    --die-with-parent --new-session \
    ... (existing bwrap args from agent-compute.nix) ...
    --clearenv \
    --setenv HOME /home/myuser \
    ... (env vars from EnvironmentFile are passed through) ...
    -- claude "$@"
'';
```

### Secrets Flow

```
sops-nix -> /run/secrets/anthropic-api-key (file)
          -> sops.templates."agentd-env" -> EnvironmentFile
            -> systemd passes to agentd process env
              -> agentd reads from secret-dir OR process env
                -> merges into agent env
                  -> tmux session inherits
                    -> bwrap --setenv picks up from parent
                      -> agent binary sees ANTHROPIC_API_KEY
```

**Two approaches for secret injection:**

**Option A: agentd secret-dir (stereOS native)**
Write sops secrets to `/run/agentd/<name>/secrets/` as individual files. agentd reads them natively.
- Pro: uses agentd's built-in secret watching; config hash changes trigger restart
- Con: requires creating individual secret files, more activation script complexity

**Option B: EnvironmentFile on systemd service (NixOS native)**
Use `sops.templates` to render an env file, pass via `EnvironmentFile` on the systemd unit.
- Pro: familiar NixOS pattern (same as automaton.nix), simpler
- Con: agentd won't detect env changes via its reconciliation loop (env is from systemd, not secret-dir)

**Recommendation: Option B (EnvironmentFile)**. Rationale:
1. Already proven pattern in the codebase (automaton.nix uses it)
2. Secrets rarely change; when they do, `systemctl restart agentd-<name>` handles it
3. agentd's secret-dir watching adds complexity for marginal benefit
4. Keeps sops-nix as the single source of truth for secrets

The bwrap wrapper script reads env vars from its parent process (agentd's tmux session) and passes them via `--setenv` to the sandboxed agent. The current `agent-spawn` already reads from `/run/secrets/*` files directly, but with agentd the flow changes: sops-nix renders to a template, systemd passes to agentd, agentd passes to tmux session, bwrap inherits and re-sets.

**Alternative: hybrid approach.** The bwrap wrapper could still read `/run/secrets/*` directly (as agent-spawn does today), independent of agentd's env passing. This is simpler but means agentd doesn't know about the secrets and can't hash-watch them. Given that secrets rarely change, this is acceptable.

---

## 7. Config-Change Restart Behavior

### Problem

The context document specifies: "Only autonomous agents trigger a restart when their jcard.toml changes. Ad-hoc agents are not auto-restarted on config change."

But agentd's reconciliation loop ALWAYS restarts on config change -- there is no selective restart mechanism.

### Solutions

**Option 1: Large reconcile interval for ad-hoc agents**
Set `-reconcile-interval 1h` for ad-hoc agents (effectively disabling the reconcile loop). Autonomous agents keep the default 5s.
- Pro: simple, no code changes to agentd
- Con: ad-hoc agents still restart if the interval happens to fire after a config edit; imprecise

**Option 2: Ad-hoc agents do not use agentd's reconcile loop**
Set the reconcile interval very large (24h) for ad-hoc agents. Config changes take effect only on next manual `systemctl restart`.
- Pro: deterministic; ad-hoc agents never surprise-restart
- Con: same as Option 1 but with a very long interval

**Option 3: Accept the behavior**
Since jcard.toml is NixOS-generated, it only changes on NixOS activation (deploy). Deploys already restart services. The reconcile loop detecting the change is redundant but harmless.
- Pro: no special handling needed
- Con: none, given NixOS manages config

**Recommendation: Option 3.** Since jcard.toml is rendered by NixOS into `/etc/agentd/<name>/jcard.toml`, it only changes during `nixos-rebuild switch`. At that point, systemd detects the unit file change and restarts the service anyway. The reconcile loop's config-change detection is defense-in-depth that never triggers in practice. No special treatment needed.

---

## 8. Homepage Widget Design

### Requirements
- Show all agents from both hosts (Contabo + OVH) in a single unified view
- Display: name, status (running/stopped), restart count, uptime
- Use standard agentd `/v1/agents` API fields

### Challenge: Cross-Host Aggregation

agentd's API is a Unix socket, not HTTP over TCP. homepage-dashboard needs HTTP URLs for its customapi widget.

### Approach: socat TCP-to-Unix proxy per host

For each host, a lightweight socat or nginx proxy exposes the per-agent Unix sockets as TCP endpoints on localhost:

```nix
# For each agent, proxy its Unix socket to a TCP port
systemd.services."agentd-proxy-${name}" = {
  description = "TCP proxy for agentd-${name} API";
  after = [ "agentd-${name}.service" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:${port},fork,reuseaddr UNIX-CONNECT:/run/agentd/${name}/agentd.sock";
    Restart = "on-failure";
  };
};
```

Then homepage uses `customapi` widgets pointing to `http://localhost:<port>/v1/agents` for local agents and `http://<other-host>:<port>/v1/agents` (via Tailscale) for remote agents.

### Alternative: Single aggregator service

Write a small script/service that polls all local agentd sockets, aggregates results into a single JSON endpoint on a single TCP port. Homepage queries this one endpoint.

**Recommendation:** Start with socat proxies (one per agent). Simple, no custom code, each agent has its own homepage widget entry. Cross-host: homepage on each host queries the other host's Tailscale IP for its agents. A single "Agents" section in homepage shows all entries from both hosts.

### Port Allocation

Each agent needs a unique proxy port. Use a fixed offset scheme:
- Base port: 9200
- Agent index: neurosys-dev=9201, conway-automaton=9202, claw-swap-dev=9203, etc.
- Add all to `internalOnlyPorts` in networking.nix

### Homepage Widget Config

```nix
{
  "Agent: neurosys-dev" = {
    widget = {
      type = "customapi";
      url = "http://localhost:9201/v1/agents";
      refreshInterval = 10000;
      mappings = [
        { field = "0.name"; label = "Agent"; }
        { field = "0.running"; label = "Status"; format = "text"; remap = [{ value = true; to = "Running"; } { value = false; to = "Stopped"; }]; }
        { field = "0.restarts"; label = "Restarts"; }
      ];
    };
    icon = "mdi-robot";
    description = "Claude Code agent on neurosys";
  };
}
```

---

## 9. Existing Infrastructure to Modify

### Files Changed

| File | Change | Repo |
|------|--------|------|
| `flake.nix` | Add `agentd` flake input | public (neurosys) |
| `modules/default.nix` | Add `./agentd.nix` import | public |
| `modules/agentd.nix` | **NEW** -- NixOS module with `services.agentd.agents` option schema | public |
| `modules/agent-compute.nix` | Remove `agent-spawn` from `environment.systemPackages`; keep agent CLI packages, podman, zmx, cgroup slice | public |
| `modules/networking.nix` | Add agentd proxy ports to `internalOnlyPorts` | public |
| Private: `modules/agent-compute.nix` | Same `agent-spawn` removal + override bwrap wrapper paths for dangirsh user | private |
| Private: `modules/homepage.nix` | Add "Agents" section with customapi widgets | private |
| Private: `flake.nix` | Add `agentd.follows = "neurosys/agentd"` or own agentd input | private |

### Files Removed (after cutover)

- `agent-spawn` script (embedded in agent-compute.nix) -- replaced by per-agent bwrap wrappers + agentd services

### Impermanence Considerations

agentd uses `/run/` paths exclusively (RuntimeDirectory managed by systemd). No persistent state needed beyond what NixOS generates at activation time. No impermanence changes required.

---

## 10. Integration Gaps and Adaptation Points

### Gap 1: agentd assumes stereOS user model (agent/admin)

agentd's code uses `sudo -u agent` for tmux commands and expects an `admin` group for socket permissions. neurosys uses `dangirsh`/`myuser` (public) and has no `agent` user.

**Resolution options:**
a. Create an `agent` system user on neurosys (like stereOS does) -- agents run as `agent`, agentd runs as root
b. Fork/patch agentd to use configurable user/group
c. Run agentd as the human user with tmux ownership matching

**Recommendation: Option (a)** -- create `agent` system user. This matches stereOS conventions and keeps agentd's user model intact. The bwrap wrapper handles the actual sandbox isolation. The `agent` user is just the tmux session owner.

However, there is a subtlety: current agent-spawn runs as `dangirsh` (via `systemd-run --user`). The bwrap sandbox uses dangirsh's UID/GID. Switching to an `agent` user means the sandbox UID changes, which affects file ownership in `/data/projects/` and `/home/dangirsh/.claude`.

**Alternative: Option (c)** -- run agentd as root but configure tmux to run sessions as `dangirsh`/`myuser`. agentd's `runAs` field in the tmux.Server struct controls which user tmux sessions run as. This is the lowest-friction option -- no new user needed, file ownership preserved.

**Updated recommendation: Option (c)** -- requires agentd to be configurable for the tmux `runAs` user. The current code hardcodes `AgentUser = "agent"`. This needs to be made configurable or overridden. Check if `runAs` is exposed as a config option. Based on the code analysis, `AgentUser` is a const in `agentd.go`, not configurable via jcard.toml or CLI flags. This will need a fork/patch or upstream contribution.

**Pragmatic approach:** Fork agentd, make `AgentUser` configurable via CLI flag or jcard.toml field. The change is small (one const -> one flag). Contribute upstream afterward.

### Gap 2: agentd has no `--no-sandbox` escape hatch

Current `agent-spawn` supports `--no-sandbox` for trusted operations. With agentd, the `custom` harness always invokes the bwrap wrapper. Trusted (unsandboxed) sessions need a separate wrapper script or a second agent config with `harness = "claude-code"` (no bwrap).

**Resolution:** Define two wrapper scripts per agent type: one with bwrap, one without. Use separate agentd instances for sandboxed vs. unsandboxed agents. For example, `neurosys-dev` (sandboxed, default) and `neurosys-dev-trusted` (unsandboxed, explicit).

### Gap 3: Custom harness binary name

agentd's `custom` harness defaults the binary to `agent`. For neurosys, we need it to be the bwrap wrapper script path. The custom harness's `BinaryName` field appears to be hardcoded to "agent" in the struct, but may be overridable via jcard.toml or environment.

**Research finding:** Based on the code analysis, the custom harness uses a `BinaryName` field that defaults to "agent" but the README mentions it "can be overridden via environment variables." This needs verification in the source. If it cannot be overridden via jcard.toml, a fork is needed to add a `binary` field to jcard.toml's `[agent]` section for the custom harness.

### Gap 4: Homepage cross-host API access

agentd uses Unix sockets. Homepage needs HTTP. Need a TCP proxy layer.

**Resolution:** socat or nginx proxy (see Section 8). Small per-agent systemd service.

---

## 11. Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| agentd user model mismatch (hardcoded `agent` user) | HIGH -- blocks basic functionality | HIGH | Fork agentd, make user configurable |
| Custom harness binary not configurable via jcard.toml | MEDIUM -- forces env var workaround or fork | MEDIUM | Verify source; fork if needed |
| tmux session leaks on crash (no cleanup) | LOW -- sessions persist in /run, cleaned on reboot | LOW | agentd handles graceful shutdown |
| Reconcile loop restarts ad-hoc sessions | LOW -- jcard.toml only changes on deploy | LOW | Accept behavior (Section 7) |
| Homepage cross-host latency | LOW -- Tailscale internal network | LOW | socat proxy is lightweight |
| agentd upstream breaking changes | MEDIUM -- unstable project | MEDIUM | Pin flake input, test before update |

---

## 12. Verification Strategy

### Tests that must pass before phase is complete

1. **Build validation:** `nix flake check` passes with agentd module
2. **Service lifecycle:** `systemctl start agentd-<name>` spawns a tmux session with the agent running inside bwrap
3. **API check:** `curl --unix-socket /run/agentd/<name>/agentd.sock http://localhost/v1/agents` returns agent status
4. **Restart policy:** Kill agent process inside sandbox; observe agentd auto-restart within policy (for `restart = "always"`)
5. **No-restart policy:** Agent exits; verify agentd does NOT restart (for `restart = "no"`)
6. **Sandbox preserved:** Agent inside bwrap cannot read `/run/secrets/`, `/home/myuser/.ssh`
7. **Homepage widget:** Dashboard shows agent status from both hosts
8. **agent-spawn removed:** `which agent-spawn` returns nothing; no references in systemPackages

---

## 13. Recommended Plan Structure

### Plan 40-01: Core agentd Module + First Agent

1. Add agentd flake input (pin specific commit for stability)
2. Fork agentd if needed (configurable user, custom harness binary)
3. Create `modules/agentd.nix` with `services.agentd.agents` option schema
4. Create bwrap wrapper derivation (factored from agent-compute.nix)
5. Define first agent: `neurosys-dev` (ad-hoc, restart=no, custom harness + bwrap)
6. Wire sops secrets via EnvironmentFile
7. Test on one host (OVH or Contabo)
8. Verify: service starts, API responds, sandbox works

### Plan 40-02: Full Agent Fleet + Homepage Widget

1. Define remaining agents: `conway-automaton` (restart=always), `claw-swap-dev` (restart=no)
2. Deploy to both hosts
3. Remove agent-spawn from both public and private agent-compute.nix
4. Add socat TCP proxy per agent for API access
5. Add "Agents" section to homepage with customapi widgets
6. Cross-host homepage: query remote host's Tailscale IP for its agents
7. Verify: all agents running, homepage shows unified view, agent-spawn gone

---

## 14. Open Questions for Planning Phase

1. **agentd fork scope:** Should we maintain a fork in `dangirsh/agentd` or contribute upstream? The changes needed (configurable user, custom harness binary path) are small and likely welcome upstream.

2. **Conway Automaton migration:** Should conway-automaton move from its current raw systemd service (automaton.nix) to an agentd-managed agent? Or keep it as-is since it's a different binary (Node.js, not claude/codex)?

3. **Per-host agent declarations:** Where should per-host agent definitions live? Options:
   - Shared module with per-host enable flags
   - Host-specific imports (contaboModules, ovhModules)
   - Private overlay agent definitions

4. **Testing without live VPS:** Can we test the agentd module locally using `nixos-rebuild build` + VM test? Or does it require deployment to verify tmux session management?

---

*Research completed: 2026-02-28*
*Sources: github.com/papercomputeco/agentd (main branch), github.com/papercomputeco/stereOS (main branch), github.com/neurosnap/zmx, neurosys codebase analysis*
