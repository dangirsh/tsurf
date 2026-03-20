# Private Overlay Example

Minimal forkable template for a private tsurf overlay.

**This is a TEMPLATE. It will not evaluate until you customize placeholder values, add host-specific modules, and configure real hardware.**

## Quick Start

1. Copy this directory into a new private repository.
2. Edit `flake.nix`: replace `github:your-org/tsurf` and `REPLACE` placeholders.
3. Replace placeholder recipients in `.sops.yaml` with real age public keys.
4. Replace hardware references in `hosts/example/default.nix` with your host's config.
5. After host-specific setup, import `networking.nix`, `secrets.nix`, and `sshd-liveness-check.nix` (requires Tailscale, persisted SSH host keys, and an encrypted sops file).
6. Run `nix flake lock` in this private repo to generate `flake.lock`.
7. Create `secrets/example.yaml`, encrypt it with sops, and set `sops.defaultSopsFile` when enabling `secrets.nix`.
8. Deploy with deploy-rs using your real hostnames and SSH access.

---

## Adding a Custom Agent

tsurf agents run inside a [nono](https://github.com/always-further/nono) sandbox with [Landlock](https://docs.kernel.org/userspace-api/landlock.html) kernel-level isolation. Each agent needs three things:

1. **A nono profile** — what the agent can and cannot access
2. **A launch script** — how the agent runs (credentials, CLI flags)
3. **A systemd unit** — when and how the system starts it

### What agents can access

| Resource | Access | Controlled by |
|----------|--------|---------------|
| Current working directory | Read + write | `workdir.access` in nono profile |
| Current git repo root | Read only | `agent-wrapper.sh` `--read` flag |
| Agent config dirs (`~/.claude`, etc.) | Read + write | `filesystem.allow` in nono profile |
| Nix store, SSL certs, `/etc` basics | Read only | Inherited from `extends = "claude-code"` |
| Paths in `filesystem.allow` | Read + write | Your nono profile |
| Outbound network (API calls, git) | Allowed | `network.block = false` + egress nftables rules |

| Resource | Denied | Controlled by |
|----------|--------|---------------|
| `/run/secrets/` (API keys on disk) | Blocked | Landlock deny (nono profile inherits this) |
| `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.docker` | Blocked | `filesystem.deny` in nono profile |
| Other git repos (sibling projects) | Blocked | `agent-wrapper.sh` scopes read to current repo only |
| `wheel` / `sudo` | No access | Agent user has no `wheel` group (build-time assertion) |
| Docker daemon | No access | Agent user has no `docker` group (build-time assertion) |
| Nix daemon | Off by default | `services.agentSandbox.allowNixDaemon` (opt-in) |
| CPU / memory beyond limits | Killed | `tsurf-agents.slice` cgroup limits |

### Minimal example: `greeter.nix`

[`modules/greeter.nix`](modules/greeter.nix) is the simplest possible agent — a daily timer that asks Claude to write a greeting. It demonstrates the full pattern in ~100 lines:

```nix
# 1. Define a nono profile (what the agent can access)
greeterProfile = {
  extends = "claude-code";       # inherit safe defaults
  filesystem.allow = [
    "/var/lib/greeter"           # output directory
  ];
  network.block = false;         # needs API access
  workdir.access = "readwrite";  # CWD is writable
  interactive = false;           # no TTY (systemd timer)
};

# 2. Install the profile
environment.etc."nono/profiles/greeter.json".source = greeterProfileFile;

# 3. Launch script (credential injection + nono sandbox)
exec nono run --profile /etc/nono/profiles/greeter.json --net-allow \
  -- claude -p --permission-mode=bypassPermissions \
  "Write a greeting to /var/lib/greeter/greeting.txt"

# 4. Systemd service + timer
systemd.services.greeter = {
  serviceConfig = {
    User = config.tsurf.agent.user;  # runs as agent, not operator
    Slice = "tsurf-agents.slice";    # resource limits
    MemoryMax = "2G";
    # ... hardening flags ...
  };
};
```

To use it: import `modules/greeter.nix` in your host config and ensure `anthropic-api-key` exists in your sops secrets.

### Complex example: `janitor.nix`

[`modules/janitor.nix`](modules/janitor.nix) is a more realistic agent that demonstrates:

- **Configurable options** (`services.janitor.schedule`, `.model`, `.systemPrompt`, `.reportPath`)
- **Custom nono profile with `extends`** — inherits from `claude-code`, adds `/tmp`, `/nix/var`, `/var/lib/janitor`
- **Natural-language system prompt** — cleanup behavior defined in English, not bash
- **JSON report output** with validation
- **Weekly systemd timer** with persistent scheduling

Cost: ~$0.01-0.03/run (~$0.50-1.50/year at Sonnet pricing). Override model with `services.janitor.model`.

### Step-by-step: adding your own agent

**1. Define the nono profile.**

Start with `extends = "claude-code"` and add only the paths your agent needs:

```nix
myAgentProfile = {
  extends = "claude-code";
  filesystem = {
    allow = [ "/var/lib/my-agent" ];  # directories the agent needs to write
    allow_file = [ "/var/lib/my-agent/output.json" ];  # specific files
    # deny list is inherited — blocks ~/.ssh, ~/.gnupg, etc.
  };
  network.block = false;
  workdir.access = "readwrite";
  interactive = false;  # true if the agent needs a TTY (interactive use)
};
```

Key profile fields:
- `extends`: inherit from a built-in profile (`claude-code`, `codex`, etc.)
- `filesystem.allow`: directories with read+write access
- `filesystem.allow_file`: specific files with read+write access
- `filesystem.deny`: paths to block even within allowed parent directories
- `network.block`: `false` to allow outbound network (API calls)
- `workdir.access`: `"readwrite"` for the current working directory
- `interactive`: `true` for interactive agents, `false` for timer/service agents

**2. Install the profile to `/etc/nono/profiles/`.**

```nix
profileFile = pkgs.writeText "my-agent-profile.json" (builtins.toJSON myAgentProfile);
environment.etc."nono/profiles/my-agent.json".source = profileFile;
```

**3. Write the launch script.**

```nix
script = pkgs.writeShellScript "my-agent" ''
  set -euo pipefail
  export ANTHROPIC_API_KEY="$(cat "$ANTHROPIC_API_KEY_FILE")"
  exec nono run \
    --profile /etc/nono/profiles/my-agent.json \
    --net-allow \
    -- claude -p \
    --permission-mode=bypassPermissions \
    "Your agent prompt here."
'';
```

For agents using other binaries (codex, pi, custom tools), replace `claude` with the appropriate command. The `--permission-mode=bypassPermissions` flag is safe here because nono is the actual permission boundary.

**4. Define the systemd service.**

```nix
systemd.services.my-agent = {
  serviceConfig = {
    Type = "oneshot";
    User = config.tsurf.agent.user;          # runs as agent, not operator
    WorkingDirectory = "/var/lib/my-agent";
    ExecStart = script;
    Environment = [ "ANTHROPIC_API_KEY_FILE=${config.sops.secrets."anthropic-api-key".path}" ];

    # Resource limits
    Slice = "tsurf-agents.slice";
    MemoryMax = "2G";
    TasksMax = 64;

    # Hardening baseline
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectClock = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    LockPersonality = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
  };
};
```

**5. (Optional) Add a timer.**

```nix
systemd.timers.my-agent = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "daily";   # or "weekly", "Mon *-*-* 03:00", etc.
    Persistent = true;       # run missed timers on boot
  };
};
```

**6. Wire it up.**

Import the module in your host config:

```nix
# hosts/my-host/default.nix
imports = [ ../../modules/my-agent.nix ];
```

Ensure the sops secret exists:

```nix
sops.secrets."anthropic-api-key".owner = config.tsurf.agent.user;
```

### Using the built-in interactive wrappers

For interactive use (not timer-based), tsurf ships sandboxed wrappers for `claude`, `codex`, and `pi`. These use the default `tsurf` nono profile and are available on the agent user's PATH:

```bash
# SSH in as operator, then:
sudo -u agent bash
cd /data/projects/my-repo
claude   # runs through nono sandbox automatically
codex    # same — sandboxed wrapper
pi       # same
```

The wrappers handle credential injection from `/run/secrets/`, enforce the git-worktree requirement, and log launches to journald (`journalctl -t agent-launch`).

See `SECURITY.md` in the tsurf repo for the full access control model, credential flow architecture, and tailnet segmentation guidance.
