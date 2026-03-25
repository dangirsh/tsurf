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

## Adding Agent Workloads

Public tsurf core provides two first-class agent paths running as the unprivileged `agent` user under [nono](https://github.com/always-further/nono):

- interactive `claude`
- unattended `services.devAgent`

Additional wrappers such as `codex` are opt-in public extras. Workflow-specific agents and orchestration still belong in your private overlay.

### Required modules for agent hosts

Hosts running agent workloads should import all three agent infrastructure modules:

- `modules/agent-compute.nix` -- provides `tsurf-agents.slice` cgroup limits and `/data/projects` persistence
- `modules/agent-launcher.nix` -- generic sandboxed agent launcher infrastructure
- `modules/agent-sandbox.nix` -- core `claude` wrapper declaration on top of the generic launcher
- `modules/nono.nix` -- nono binary and tsurf Landlock profile

For unattended Claude work, also import `extras/dev-agent.nix`.

The private overlay template `flake.nix` already imports `agent-launcher.nix`, `agent-sandbox.nix`, `nono.nix`, and `extras/dev-agent.nix`. Add `agent-compute.nix` and enable it with `services.agentCompute.enable = true` for any host that runs agent workloads.

### What agents can access

| Resource | Access | Controlled by |
|----------|--------|---------------|
| Current working directory | Read + write | `workdir.access` in nono profile |
| Current git repo root | Read only | `agent-wrapper.sh` `--read` flag |
| Agent config dirs (`~/.claude`, etc.) | Read + write | `filesystem.allow` in nono profile |
| Nix store, SSL certs, `/etc` basics | Read only | Inherited from `extends = "claude-code"` |
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

### First-class unattended workflow (`dev-agent`)

Use the shipped `dev-agent` module for the standard unattended Claude path:

```nix
{ config, inputs, ... }:
{
  imports = [ "${inputs.tsurf}/extras/dev-agent.nix" ];

  services.devAgent = {
    enable = true;
    workingDirectory = "/data/projects/my-workspace";
    prompt = ''
      Review the repository in the current working directory, continue the
      highest-value concrete task you can verify locally, and leave a short
      progress note in ./DEV-AGENT-STATUS.md.
    '';
    permissionMode = "bypassPermissions";
    model = "claude-opus-4-6";
  };
}
```

The service keeps a named `zmx` session alive, initializes the workspace as a Git repo if needed, and restarts cleanly under systemd supervision.

### Step-by-step: adding another wrapper command

For workflow-specific wrappers beyond the shipped public set, add your own module in the private overlay:

```nix
# modules/my-agent-wrapper.nix
{ pkgs, ... }:
{
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "my-agent";
      runtimeInputs = [ pkgs.claude-code ];
      text = ''
        # Start with the core Claude wrapper path; replace with your own
        # private-overlay command model as needed.
        exec claude "$@"
      '';
    })
  ];
}
```

Then add workflow-specific credentials and execution policy in that same overlay module.

### Secret ownership for agent execution

For the public brokered launcher model, keep provider keys root-owned. The launcher reads them before the privilege drop and exposes only per-session loopback tokens to the child:

```nix
sops.secrets."anthropic-api-key".owner = "root";
```

### Using the built-in interactive wrappers

For interactive use, tsurf ships the sandboxed `claude` wrapper in public core:

```bash
# SSH in as operator, then:
cd /data/projects/my-repo
claude   # wrapper broker-launches as agent user and runs in nono sandbox
```

The wrapper handles credential injection from `/run/secrets/`, enforces the git-worktree requirement, and logs launches to journald (`journalctl -t agent-launch`).

See `SECURITY.md` in the tsurf repo for the full access control model, credential flow architecture, and tailnet segmentation guidance.

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
