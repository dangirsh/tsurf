# CLAUDE.md — tsurf

NixOS configuration template for declarative server management with flakes + home-manager. Example hosts: `services` and `dev` (replaced by real hosts in a private overlay).

## Project Structure

```
flake.nix              # Entrypoint — inputs, outputs, eval fixtures `.#eval-services` + `.#eval-dev`
flake.lock             # Pinned dependencies (nixpkgs 25.11, home-manager, sops-nix, disko, etc.)
hosts/
  hardware.nix         # Shared QEMU VPS hardware config (both hosts)
  disko-config.nix     # Shared disko partition layout (both hosts)
  services/            # Example service host
  dev/                 # Example agent/dev host
modules/                 # Core — security/infrastructure essentials only
  agent-compute.nix    # Agent runtime support (resource controls + shared tooling)
  agent-sandbox.nix    # First-class sandboxed `claude` wrapper path + protected repo guards
  base.nix             # Nix settings, system packages, kernel sysctl hardening
  boot.nix             # GRUB bootloader + BTRFS root rollback
  break-glass-ssh.nix  # Emergency SSH key (last-resort recovery)
  impermanence.nix     # /persist manifest — BTRFS subvolume rollback on boot
  networking.nix       # nftables, SSH (hardened), Tailscale, firewall assertions
  nono.nix             # nono profile + proxy credential injection (phantom tokens)
  secrets.nix          # sops-nix secret declarations
  users.nix            # Operator (dev) + agent user split, tsurf.agent.* options, sudo, SSH keys
scripts/                 # Core scripts (sandbox, rollback, test runner)
  agent-wrapper.sh     # nono sandbox entry — env setup, credential injection, exec
  btrfs-rollback.sh    # BTRFS root subvolume rollback on boot
  run-tests.sh         # Live BATS test runner (SSH-based)
  sandbox-probe.sh     # Sandbox boundary probe for live tests
extras/                  # Optional batteries — import what you need
  codex.nix            # Codex agent wrapper (OpenAI, opt-in)
  cost-tracker.nix     # API cost tracking (Anthropic, OpenAI)
  dashboard.nix        # Service dashboard from direct entry declarations
  dev-agent.nix        # First-class unattended Claude agent (supervised zmx + systemd)
  opencode.nix         # opencode agent wrapper (Anthropic + OpenAI, opt-in)
  pi.nix               # pi agent wrapper (Anthropic, opt-in)
  restic.nix           # Restic backup to B2 + status server
  syncthing.nix        # Syncthing file sync (127.0.0.1 GUI)
  home/
    default.nix        # home-manager: git/ssh/direnv inlined
    cass.nix           # CASS indexer timer (opt-in)
  scripts/             # Scripts for extras modules
    clone-repos.sh     # Idempotent repo cloning activation script
    cost-tracker.py    # Cost tracker HTTP server (Python)
    dashboard-frontend.html  # Dashboard single-page frontend
    dashboard-server.py      # Dashboard HTTP server (Python)
    deploy.sh          # deploy-rs wrapper (locking, watchdog, health check)
    dev-agent.sh       # Dev-agent session launcher script
examples/
  scripts/
    deploy.sh          # Private-overlay deploy wrapper reference (tsurf.url guard)
  private-overlay/     # Forkable starting point for a private overlay
secrets/               # sops-encrypted secrets (age keys, gitignored)
tests/
  eval/config-checks.nix  # Offline eval assertions
  vm/sandbox-behavioral.nix # NixOS VM sandbox test (requires KVM)
  live/*.bats              # Live BATS tests over SSH
```

## Key Decisions

- **Flakes + home-manager**: Reproducible, lockfile-pinned (nixos-25.11)
- **Restic to B2**: Automated daily backups to Backblaze B2 (S3 API)
- **sops-nix secrets**: All credentials encrypted, decrypted at activation via age keys
- **Agent tooling**: Public core ships two first-class agent paths: sandboxed interactive `claude` and the unattended `dev-agent` service. `codex`, `pi`, and `opencode` are opt-in extras; workflow-specific wrappers still belong in private overlays.
- **Agent sandbox**: Landlock deny-by-default filesystem, PWD restricted to project root, read access scoped to current git repo, and protected control-plane repo markers/roots rejected up front. Proxy credential injection — nono generates per-session phantom tokens; real keys never reach the child process.
- **Agent egress**: Host nftables allowlists outbound agent traffic by UID. Defaults allow DNS plus TCP `22/80/443` and block private/link-local ranges.
- **SSH hardened**: Port 22 on public firewall (key-only, srvos defaults); deploy prefers Tailscale MagicDNS
- **Network model**: Only ports 22 + 22000 on public firewall by default. Ports 80/443 conditional on nginx. All internal services bind 127.0.0.1 (dashboard, syncthing GUI). Tailscale for internal access.
- **Privilege model**: `dev` is the operator (wheel, human admin). `agent` runs sandboxed tools (no wheel). Parameterized via `tsurf.agent.{user, home, projectRoot}`. Build-time assertions enforce agent user security invariants.
- **Operator UID**: Configurable via `tsurf.template.devUid` (default 1000), defined in `modules/users.nix`.
- **Per-host explicit imports**: Each host/default.nix lists all imports directly

## Module Conventions & Patterns

- One module per concern. Prefer adding to existing modules over new ones for <20 lines.
- Each host `default.nix` lists imports explicitly (no module hub).
- Secrets managed via sops-nix (age key derived from SSH host key).
- All service configs are declarative — no imperative setup steps.
- Infrastructure repos cloned via activation scripts (clone-only, never pull).
- Internal services bind `127.0.0.1` (localhost-only). Overlay can expose on tailnet via `networking.firewall.interfaces.tailscale0.allowedTCPPorts`.
- `@decision` annotations on security-relevant choices in module headers.

### NixOS module authoring

- Module anatomy: start with header comments and `@decision` annotations, use
  `{ config, lib, pkgs, ... }:` as the function signature, define repeated values in `let`,
  and keep the declarative body in the final attrset.
- Register services on the dashboard with `services.dashboard.entries.<name>` (from
  `extras/dashboard.nix`). Required fields: `name`, `description`, `icon`, `order`.
  Add the service port to `internalOnlyPorts` in `modules/networking.nix` manually.
- `@decision` annotation format: `@decision ID: Description.` in module header comments.
  Use these for security choices, port exposure decisions, and design trade-offs.
- Secrets pattern: declare `sops.secrets."<name>"` with minimal `owner`, and render env files with
  `sops.templates."<name>".content` plus `config.sops.placeholder."<secret>"`.
- File-size rule: if a change is <20 lines and belongs to an existing concern, extend that module.
  Create a new module when adding a new service with its own systemd unit, user, and secrets.
- Import rule: each host `default.nix` lists imports explicitly. After creating a module, add its
  path to `hosts/services/default.nix` and/or `hosts/dev/default.nix`.

## Testing Workflow

Before committing, stage new files before evaluation (flakes only see tracked files):

```bash
git add <new-files> && nix flake check
```

To satisfy the commit guard, produce `.test-status` at the project root:

```bash
nix flake check 2>&1 && echo "pass|0|$(date +%s)" > .test-status
```

- Guard hook: `~/.claude/hooks/guard.sh`
- Required format: `pass|0|<unix_timestamp>`
- Required location: `/data/projects/tsurf/.test-status` (project root)

### Test layers

| Layer | Command | When |
|-------|---------|------|
| Eval checks (50+ assertions, fast) | `nix flake check` | Before every commit |
| VM sandbox (requires KVM) | `nix build .#vm-test-sandbox` | Requires KVM |
| Live tests over SSH | `nix run .#test-live -- --host <hostname>` | After deploy only |
| Live sandbox behavioral | `nix run .#test-live -- --host <sandbox-host> tests/live/sandbox-behavioral.bats` | After deploy (sandbox host only) |

Sandbox testing has three tiers:
- **Eval checks**: Source-text regression guards (fast, every commit) — catch structural regressions
- **Live behavioral**: Runtime probes as agent user inside nono sandbox (after deploy, sandbox host only)
- **VM test**: Reproducible user privilege separation smoke test (requires KVM, not in CI)

### Test conventions

- One assertion per test, host-prefixed names (`tsurf: tailscaled.service is active`).
- Tests are idempotent and read-only.
- Helpers in `tests/lib/common.bash`.

## Security

See `SECURITY.md` for the complete security model, accepted risks, and verification approach.

### Hard-stop rules

- **Never** add ports to `networking.firewall.allowedTCPPorts`; add to `internalOnlyPorts` in `modules/networking.nix`.
- **Never** commit unencrypted secrets; use sops-nix with minimal ownership.
- **Never** embed credentials in URLs or CLI args.
- **Never** weaken nono sandbox defaults in `nono.nix`.
- **Never** add a public `--no-sandbox` path; unsandboxed execution belongs in a private overlay only.
- **Never** add packages imperatively (`nix-env`, `nix profile install`) or re-enable `nix.channel.enable` / `nix.nixPath`.
- **Never** remove `modules/break-glass-ssh.nix` from either host config.
- **Never** omit `@decision` annotations for security-relevant module choices.

### Pre-flight checklist

Run before every module or service commit:

1. **Port exposure** — New port? Add to `internalOnlyPorts` in `modules/networking.nix`. NEVER add to `networking.firewall.allowedTCPPorts`.
2. **Secrets** — New secret? Add to `secrets.nix` with minimal `owner`/permissions. Use `sops.templates` for env files. NEVER embed credentials in URLs, CLI args, or committed files.
3. **New service** — Set `openFirewall = false`. Add `@decision` annotation. Add port to `internalOnlyPorts` and dashboard entry to `services.dashboard.entries`.
4. **Sandbox impact** — Modifying `agent-compute.nix` or `nono.nix`? Verify `/run/secrets` and `~/.ssh` remain in the deny list. NEVER weaken nono sandbox defaults.
5. **Agent execution** — Public core `claude` and `dev-agent` must stay sandboxed. Protect control-plane repos with `.tsurf-control-plane` (or `services.agentSandbox.protectedRepoRoots`) and launch agents from workspace repos.
7. **Package management** — NEVER use `nix-env`, `nix profile install`, or re-enable `nix.channel.enable` / `nix.nixPath`.
8. **Break-glass key** — NEVER remove `modules/break-glass-ssh.nix` from either host config.
9. **Validation** — `nix flake check` passes.

## Sandbox Awareness

- The public core wrapper brokers through `sudo` + `systemd-run --uid=agent`. See `SECURITY.md` for the full sandbox model, credential flow, and access control.
- Launch logs: `journalctl -t agent-launch`

## Deployment Rules

- **ALL deploys from the PRIVATE overlay**: `cd /path/to/private-overlay && ./scripts/deploy.sh --node <your-host>`.
- **This public repo refuses deploys** (`tsurf.url` guard in `examples/scripts/deploy.sh`) and exports eval fixtures only (`.#eval-services`, `.#eval-dev`).
- **NEVER** use `nixos-rebuild switch` for normal deploys; it bypasses the deploy safety guard and lock/watcher flow.

## Recovery

If SSH is lost, use provider console/rescue mode to rollback (`nixos-rebuild switch --rollback`) or repair persisted `authorized_keys`, then redeploy from the private overlay.
Keep `modules/break-glass-ssh.nix` in both host configs and follow `SECURITY.md` recovery invariants.

## Private Overlay

Personal services, real credentials, and host-specific config go in a separate private flake
that uses `follows` to share pinned dependencies, imports public modules individually (no hub),
and can replace modules entirely or import and extend them.

## Simplicity Conventions

- Every new module must justify its existence — prefer adding to existing modules over creating new ones for <20 lines
- No dead code — unused options, packages, or features must be removed immediately
- YAGNI — do not add features "for later" unless they are in an active phase plan
- One source of truth — packages declared in exactly one module (no duplicates across modules)
- Prefer inline over separate files for small configs (<10 lines); extract larger bash/python to separate files
- Let bindings for values used more than once (e.g., Tailscale IP in homepage.nix)
- `tmp/` in project root for temporary files (never `/tmp/`) — convention from global CLAUDE.md
- `disabledModules` for private overlay: only justified when the public module references non-existent users/resources in private config (e.g., `users.nix`, `agent-compute.nix`), or when the entire module content differs (e.g., `syncthing.nix` for completely different sync setup).
