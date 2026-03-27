# Private Overlay Example

Minimal forkable template for a private tsurf overlay.

**This is a TEMPLATE. It will not evaluate until you customize placeholder values, add host-specific modules, and configure real hardware.**

## User Model

tsurf uses a two-user model:

- **root** -- Operator, deploys, SSH access, all admin tasks.
- **agent** -- Runs sandboxed agent tools. No general root access. SSH access for interactive agent sessions.

There is no separate `dev` operator user. Root handles all administrative tasks directly.

## Quick Start

If you just want to try tsurf on an existing NixOS server first, use the
repo-root quickstart path instead:

```bash
./tsurf init root@your-server
./tsurf deploy
./tsurf status
```

Use the private overlay flow below when you want the full long-lived setup with
your own repo, secrets, and host-specific modules.

1. Copy this directory into a new private repository.
2. Edit `flake.nix`: replace `github:your-org/tsurf` and `REPLACE` placeholders.
3. Run `nix run .#tsurf-init -- --overlay-dir .` to generate the root SSH key and
   create `modules/root-ssh.nix`.
4. Replace placeholder recipients in `.sops.yaml` with real age public keys.
5. Replace hardware references in `hosts/example/default.nix` with your host's config.
6. After host-specific setup, import `networking.nix` and `secrets.nix` (requires
   persisted SSH host keys and an encrypted sops file).
7. Run `nix flake lock` in this private repo to generate `flake.lock`.
8. Create `secrets/example.yaml`, encrypt it with sops, and set `sops.defaultSopsFile` when enabling `secrets.nix`.
9. Deploy: `./scripts/deploy.sh --node example --first-deploy`

---

## Adding Agent Workloads

Public tsurf core provides two first-class agent paths running as the `agent` user under [nono](https://github.com/always-further/nono) sandboxing:

- **Interactive `claude`** -- sandboxed wrapper for interactive use
- **Generic launcher** -- `services.agentLauncher.agents.<name>` for custom agents

Additional wrappers such as `codex` are opt-in public extras. Workflow-specific agents and orchestration belong in your private overlay.

### Required modules for agent hosts

Hosts running agent workloads should import these agent infrastructure modules:

- `modules/agent-compute.nix` -- provides `tsurf-agents.slice` cgroup limits and `/data/projects` persistence
- `modules/agent-launcher.nix` -- generic sandboxed agent launcher infrastructure
- `modules/agent-sandbox.nix` -- core `claude` wrapper declaration on top of the generic launcher
- `modules/nono.nix` -- nono binary and tsurf Landlock profile
- `extras/cass.nix` -- low-priority CASS indexer timer for the dedicated agent user

The private overlay template `flake.nix` already imports all of these. Enable `services.agentCompute.enable = true` for any host that runs agent workloads.

### Defining custom agents with the generic launcher

The generic launcher (`services.agentLauncher.agents.<name>`) lets you define agents in a few lines. Each produces a wrapper script, nono sandbox profile, systemd-run launcher, and sudo rule automatically. See `modules/code-review.nix` for a complete example.

### What agents can access

| Resource | Access | Controlled by |
|----------|--------|---------------|
| Current working directory | Read + write | `workdir.access` in nono profile |
| Current git repo root | Read only | `agent-wrapper.sh` `--read` flag |
| Agent-specific config dirs (for example `~/.claude`) | Read + write | Per-agent `nonoProfile.extraAllow` / `extraAllowFile` |
| Nix store, SSL certs, `/etc` basics | Read only | Base `tsurf` nono profile |
| Paths in `filesystem.allow` | Read + write | Your nono profile |
| Outbound network (API calls, git) | Allowlisted | Host nftables policy for the dedicated agent UID |

| Resource | Denied | Controlled by |
|----------|--------|---------------|
| `/run/secrets/` (API keys on disk) | Blocked | Landlock deny (nono profile inherits this) |
| `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.docker` | Blocked | `filesystem.deny` in nono profile |
| Other git repos (sibling projects) | Blocked | `agent-wrapper.sh` scopes read to current repo only |
| `sudo` | Limited | Agent user has sudo only for immutable launchers (no general root access) |
| Docker daemon | No access | Agent user has no `docker` group (build-time assertion) |
| CPU / memory beyond limits | Killed | `tsurf-agents.slice` cgroup limits |

### Reattachable Interactive Sessions

If you want an interactive agent session to survive SSH or mosh disconnects, run
the wrapper inside `tmux`:

```bash
tmux new -As claude-main
cd /data/projects/my-repo
claude
```

This keeps the public core simple while still giving you an easy reattach path.

### Adding a custom agent via the generic launcher

The preferred way to add agents is through the generic launcher. Each agent gets a sandboxed wrapper, nono profile, and sudo rule automatically:

```nix
# modules/my-agent.nix
{ pkgs, ... }:
{
  services.agentLauncher.agents.my-agent = {
    command = "claude";
    package = pkgs.claude-code;
    wrapperName = "my-agent";
    credentials = [ "anthropic:ANTHROPIC_API_KEY:anthropic-api-key" ];
    defaultArgs = [ "-p" "Your default prompt here" ];
    nonoProfile.extraAllow = [ "/data/projects/my-workspace" ];
  };
}
```

Then import it in your host config and optionally add a systemd timer.

### Secret ownership for agent execution

For the public brokered launcher model, keep provider keys root-owned. The launcher reads them before the privilege drop and exposes only per-session loopback tokens to the child:

```nix
sops.secrets."anthropic-api-key".owner = "root";
```

### Using the built-in interactive wrappers

For interactive use, tsurf ships the sandboxed `claude` wrapper in public core:

```bash
# SSH in as root, then:
cd /data/projects/my-repo
claude   # wrapper broker-launches as agent user and runs in nono sandbox
```

The wrapper handles credential injection from `/run/secrets/`, enforces the git-worktree requirement, and logs launches to journald (`journalctl -t agent-launch`).

See `SECURITY.md` in the tsurf repo for the full access control model and credential flow architecture.

### Adding File Sync

Public tsurf intentionally does not ship Syncthing or any other file-sync module. Peer topology, folder layout, and any public port exposure are deployment-specific, so keep sync in your private overlay.

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

2. Import it in your host config:

```nix
# hosts/my-host/default.nix
imports = [ ../../modules/docker.nix ];
```

3. Add a `/docker` BTRFS subvolume in your disko config for overlay2 storage:

```nix
"/docker" = {
  mountpoint = "/var/lib/docker";
  mountOptions = [ "compress=zstd" "noatime" ];
};
```
