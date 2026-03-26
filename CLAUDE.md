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
  agent-launcher.nix   # Generic sandboxed agent launcher (wrapper, systemd-run, nono, credentials)
  agent-sandbox.nix    # Claude agent declaration on top of the generic launcher
  base.nix             # Nix settings, system packages, nix-mineral kernel hardening
  boot.nix             # GRUB bootloader + BTRFS root rollback
  impermanence.nix     # /persist manifest — BTRFS subvolume rollback on boot
  networking.nix       # nftables, SSH (hardened), firewall assertions
  nono.nix             # nono base profile for the filesystem/network sandbox
  secrets.nix          # sops-nix secret declarations
  users.nix            # Root + agent user model, tsurf.agent.* options, root SSH assertion
scripts/                 # Core scripts (sandbox, rollback, deploy, test runner)
  agent-wrapper.sh     # root-owned launch bridge — credential proxy, sandbox, privilege drop
  btrfs-rollback.sh    # BTRFS root subvolume rollback on boot
  credential-proxy.py  # Root-owned per-session credential proxy for agent launches
  complexity-metric.sh # Effective LOC counter for complexity tracking
  deploy.sh            # deploy-rs wrapper (locking, health check, safety guard)
  run-tests.sh         # Live BATS test runner (SSH-based)
  sandbox-probe.sh     # Sandbox boundary probe for live tests
  tsurf-init.sh        # Bootstrap wizard: generate SSH keys, validate setup
  tsurf-status.sh      # Check systemd service status on tsurf hosts
extras/                  # Optional batteries — import what you need
  cass.nix             # Low-priority CASS indexer timer for the dedicated agent user
  codex.nix            # Codex agent wrapper (OpenAI, opt-in, uses generic launcher)
  cost-tracker.nix     # API cost tracking (Anthropic, OpenAI)
  restic.nix           # Restic backup to B2
  home/
    default.nix        # home-manager: git/ssh/direnv defaults for the agent user
  scripts/             # Scripts for extras modules
    clone-repos.sh     # Idempotent repo cloning activation script
    cost-tracker.py    # Cost tracker HTTP server (Python)
examples/
  private-overlay/     # Forkable starting point for a private overlay
secrets/               # sops-encrypted secrets (age keys, gitignored)
tests/
  eval/config-checks.nix  # Offline eval assertions
  vm/sandbox-behavioral.nix # NixOS VM sandbox test (requires KVM)
  live/*.bats              # Live BATS tests over SSH
  unit/                    # Unit tests (deploy script, credential proxy)
  lib/common.bash          # Shared helpers for BATS live tests
.githooks/
  pre-commit             # Blocks .planning/ and README.md from autonomous commits
  post-commit            # Complexity metric warning on LOC growth
```

## Key Decisions

- **Flakes + home-manager**: Reproducible, lockfile-pinned (nixos-25.11)
- **Restic to B2**: Automated daily backups to Backblaze B2 (S3 API, opt-in extra)
- **sops-nix secrets**: All credentials encrypted, decrypted at activation via age keys
- **Agent tooling**: Public core ships the sandboxed interactive `claude` path plus the generic launcher. `codex` is an opt-in extra; workflow-specific wrappers belong in private overlays. Long-lived sessions should use `tmux`, and unattended jobs should schedule the generated wrappers directly.
- **Agent sandbox**: Landlock deny-by-default filesystem, PWD restricted to project root, read access scoped to current git repo. A root-owned loopback credential proxy keeps real keys out of the agent principal and gives the child only per-session tokens.
- **Agent egress**: Host nftables allowlists outbound agent traffic by UID. Defaults allow DNS plus TCP `22/80/443` and block private/link-local ranges.
- **SSH hardened**: Port 22 on public firewall (key-only, srvos defaults)
- **Network model**: Only port 22 is on the public firewall by default. Ports 80/443 are conditional on nginx. Internal services bind `127.0.0.1` and register their localhost ports in `modules/networking.nix`. Tailscale belongs in the private overlay.
- **Privilege model**: Two-user model: `root` (operator/deploy/admin) and `agent` (sandboxed tools, SSH access). Agent is not in `wheel`; immutable-launcher sudo access is granted explicitly. Parameterized via `tsurf.agent.{user, home, projectRoot}`.
- **Per-host explicit imports**: Each host/default.nix lists all imports directly

## Module Conventions & Patterns

- One module per concern. Prefer adding to existing modules over new ones for <20 lines.
- Each host `default.nix` lists imports explicitly (no module hub).
- Secrets managed via sops-nix (age key derived from SSH host key).
- All service configs are declarative — no imperative setup steps.
- Infrastructure repos cloned via activation scripts (clone-only, never pull).
- Internal services bind `127.0.0.1` (localhost-only).
- `@decision` annotations on security-relevant choices in module headers.

### NixOS module authoring

- Module anatomy: start with header comments and `@decision` annotations, use
  `{ config, lib, pkgs, ... }:` as the function signature, define repeated values in `let`,
  and keep the declarative body in the final attrset.
- `@decision` annotation format: `@decision ID: Description.` in module header comments.
  Use these for security choices, port exposure decisions, and design trade-offs.
- Secrets pattern: declare `sops.secrets."<name>"` with minimal `owner`, and render env files with
  `sops.templates."<name>".content` plus `config.sops.placeholder."<secret>"`.
- File-size rule: if a change is <20 lines and belongs to an existing concern, extend that module.
  Create a new module when adding a new service with its own systemd unit, user, and secrets.
- Import rule: each host `default.nix` lists imports explicitly. After creating a module, add its
  path to `hosts/services/default.nix` and/or `hosts/dev/default.nix`.

## Testing Workflow

**Git hooks**: Activate the project hooks once after cloning:

```bash
git config core.hooksPath .githooks
```

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

- One assertion per test, host-prefixed names (`tsurf: sshd.service is active`).
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
- **Never** omit `@decision` annotations for security-relevant module choices.
- **Never** commit `.planning/` — it is local-only agent state (gitignored, blocked by `.githooks/pre-commit`).
- **Never** remove or rewrite the opening section of `README.md` (the description, personal note, and blockquotes before `## Design Principles`) or the `## Design Principles` section itself. These are human-authored and must not be touched by agents.

### Pre-flight checklist

Run before every module or service commit:

1. **Port exposure** — New port? Add to `internalOnlyPorts` in `modules/networking.nix`. NEVER add to `networking.firewall.allowedTCPPorts`.
2. **Secrets** — New secret? Add to `secrets.nix` with minimal `owner`/permissions. Use `sops.templates` for env files. NEVER embed credentials in URLs, CLI args, or committed files.
3. **New service** — Set `openFirewall = false`. Add `@decision` annotation. Add port to `internalOnlyPorts`.
4. **Sandbox impact** — Modifying `agent-compute.nix` or `nono.nix`? Verify `/run/secrets` and `~/.ssh` remain in the deny list. NEVER weaken nono sandbox defaults.
5. **Agent execution** — Public core `claude` and any generated wrappers must stay sandboxed. Launch agents from workspace repos, not security-boundary repos (operational policy).
7. **Package management** — NEVER use `nix-env`, `nix profile install`, or re-enable `nix.channel.enable` / `nix.nixPath`.
8. **Root SSH access** — Keep a real root SSH key configured in the private overlay. The public repo no longer ships placeholder recovery keys.
9. **Validation** — `nix flake check` passes.

## Sandbox Awareness

- The public core wrapper brokers through `sudo` + `systemd-run` + `setpriv --reuid=agent`. See `SECURITY.md` for the full sandbox model, credential flow, and access control.
- Launch logs: `journalctl -t agent-launch`

## Deployment Rules

- **ALL deploys from the PRIVATE overlay**: `cd /path/to/private-overlay && ./scripts/deploy.sh --node <your-host>`.
- **This public repo refuses deploys** (`tsurf.url` guard in `scripts/deploy.sh`) and exports eval fixtures only (`.#eval-services`, `.#eval-dev`).
- **NEVER** use `nixos-rebuild switch` for normal deploys; it bypasses the deploy safety guard and lock/watcher flow.

## Recovery

If SSH is lost, use provider console/rescue mode to rollback (`nixos-rebuild switch --rollback`) or repair persisted `authorized_keys`, then redeploy from the private overlay.
Keep the private overlay's root SSH key material in sync with `SECURITY.md` recovery invariants.

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
- Let bindings for values used more than once
- `tmp/` in project root for temporary files (never `/tmp/`) — convention from global CLAUDE.md
- `disabledModules` for private overlay: only justified when the public module references non-existent users/resources in private config (e.g., `users.nix`, `agent-compute.nix`), or when the entire module content differs and you are replacing that concern wholesale in the overlay.
