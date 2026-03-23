# Private Overlay Example

Minimal forkable template for a private tsurf overlay.

**This is a TEMPLATE. It will not evaluate until you customize placeholder values, add host-specific modules, and configure real hardware.**

## Quick Start

1. Copy this directory into a new private repository.
2. Edit `flake.nix`: replace `github:your-org/tsurf` and `REPLACE` placeholders.
3. Replace placeholder recipients in `.sops.yaml` with real age public keys.
4. Replace hardware references in `hosts/example/default.nix` with your host's config.
5. After host-specific setup, import `networking.nix` and `secrets.nix` (requires Tailscale, persisted SSH host keys, and an encrypted sops file).
6. Run `nix flake lock` in this private repo to generate `flake.lock`.
7. Create `secrets/example.yaml`, encrypt it with sops, and set `sops.defaultSopsFile` when enabling `secrets.nix`.
8. Deploy with deploy-rs using your real hostnames and SSH access.

---

## Adding a Custom Agent

tsurf agents run inside a [nono](https://github.com/always-further/nono) sandbox with [Landlock](https://docs.kernel.org/userspace-api/landlock.html) kernel-level isolation. API keys stay in the parent process; the child gets only a per-session phantom token. For recurring agents, `services.agentSandbox.agentTimers` now generates the nono profile, launch script, env template, and systemd units from one declarative entry.

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

[`modules/greeter.nix`](modules/greeter.nix) is the simplest possible agent: a daily timer that asks Claude to write a greeting. Using `agentTimers`, the whole module is about ten lines:

```nix
{ ... }:
{
  services.agentSandbox.agentTimers.greeter = {
    description = "Example daily greeting agent";
    prompt = "Write a short, cheerful greeting with today's date to /var/lib/greeter/greeting.txt. One sentence only.";
    workingDirectory = "/var/lib/greeter";
    filesystem.allow = [ "/var/lib/greeter" ];
    filesystem.allowFile = [ "/var/lib/greeter/greeting.txt" ];
    credentials = [ "anthropic" ];
    timer.onCalendar = "daily";
  };
}
```

The abstraction auto-generates the nono profile, launch script, sops env template, systemd service with hardening defaults, tmpfiles rule for the working directory, and the timer. To use it: import `modules/greeter.nix` in your host config and ensure `anthropic-api-key` exists in your sops secrets.

### Step-by-step: adding your own agent

**1. Define the agent timer.**

```nix
# modules/my-agent.nix
{ ... }:
{
  services.agentSandbox.agentTimers.my-agent = {
    description = "My custom agent";
    prompt = "Your agent prompt here.";
    workingDirectory = "/var/lib/my-agent";
    filesystem.allow = [ "/var/lib/my-agent" ];
    credentials = [ "anthropic" ];
    timer.onCalendar = "daily";
    # Optional overrides:
    # filesystem.allowFile = [ "/var/lib/my-agent/output.json" ];
    # memoryMax = "4G";
    # tasksMax = 128;
    # package = pkgs.claude-code;
    # binary = "claude";
    # cliArgs = [ "-p" "--permission-mode=bypassPermissions" ];
  };
}
```

This generates the nono profile, launch script, env template, systemd service, and optional timer automatically. Credentials refer to `services.nonoSandbox` definitions, so the API endpoint details stay centralized.

**2. Wire it up.**

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

For interactive use (not timer-based), tsurf ships a sandboxed `claude` wrapper in core. Optional wrappers for `codex`, `pi`, and `opencode` are available via `extras/codex.nix`, `extras/pi.nix`, and `extras/opencode.nix`. Core `claude` is available on the agent user's PATH:

```bash
# SSH in as operator, then:
cd /data/projects/my-repo
claude   # wrapper broker-launches as agent user and runs in nono sandbox
```

All enabled wrappers handle credential injection from `/run/secrets/`, enforce the git-worktree requirement, and log launches to journald (`journalctl -t agent-launch`).

See `SECURITY.md` in the tsurf repo for the full access control model, credential flow architecture, and tailnet segmentation guidance.

### Adding Docker

Docker is not included in the public template. To add it in your private overlay:

1. Create a Docker module (or copy from the public repo's git history):

```nix
# modules/docker.nix
{ config, lib, ... }: {
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      iptables = false;        # NixOS owns the firewall
      log-driver = "journald";
    };
  };
  virtualisation.oci-containers.backend = "docker";
  networking.nat = {
    enable = true;
    internalIPs = [ "172.16.0.0/12" ];
  };
}
```

2. Import it in your host config and add `dev` to the `docker` group:

```nix
# hosts/my-host/default.nix
imports = [ ../../modules/docker.nix ];
users.users.dev.extraGroups = [ "wheel" "docker" ];
```

3. Add a `/docker` BTRFS subvolume in your disko config for overlay2 storage:

```nix
"/docker" = {
  mountpoint = "/var/lib/docker";
  mountOptions = [ "compress=zstd" "noatime" ];
};
```
