# CLAUDE.md — tsurf

NixOS configuration template for declarative server management with flakes + home-manager. Hosts: `neurosys` (services) and `neurosys-dev` (agent/dev).

## Project Structure

```
flake.nix              # Entrypoint — inputs, outputs, nixosConfigurations.neurosys + neurosys-dev
flake.lock             # Pinned dependencies (nixpkgs 25.11, home-manager, sops-nix, disko, etc.)
hosts/
  hardware.nix         # Shared QEMU VPS hardware config (both hosts)
  disko-config.nix     # Shared disko partition layout (both hosts)
  services/            # Example service host (Contabo VPS)
  dev/                 # Example agent/dev host (OVH VPS)
modules/
  agent-compute.nix    # Agent CLI (claude, codex), Podman, zmx
  agent-sandbox.nix    # nono wrappers for claude/codex/pi agents
  base.nix             # Nix settings, system packages, kernel sysctl hardening
  boot.nix             # GRUB bootloader + BTRFS root rollback
  break-glass-ssh.nix  # Emergency SSH key (last-resort recovery)
  dashboard.nix        # Service dashboard from direct entry declarations
  dev-agent.nix        # Persistent autonomous Claude agent (zmx + systemd)
  docker.nix           # Docker engine (--iptables=false), NAT
  impermanence.nix     # /persist manifest — BTRFS subvolume rollback on boot
  networking.nix       # nftables, SSH (hardened), Tailscale, firewall assertions
  nono.nix             # nono profile + env credential injection
  cost-tracker.nix     # API cost tracking (Anthropic, OpenAI)
  restic.nix           # Restic backup to B2 + status server
  secrets.nix          # sops-nix secret declarations
  sshd-liveness-check.nix # sshd liveness check with auto-rollback
  syncthing.nix        # Syncthing file sync (127.0.0.1 GUI)
  users.nix            # Operator (dev) + agent user split, tsurf.agent.* options, sudo, SSH keys
home/
  default.nix          # home-manager: git/ssh/direnv inlined
  cass.nix             # CASS indexer timer (opt-in)
scripts/
  deploy.sh            # deploy-rs wrapper (locking, watchdog, health check)
examples/
  bootstrap/
    bootstrap-ovh.sh   # OVH VPS bootstrap via rescue mode + nixos-anywhere
scripts/
  bootstrap-contabo.sh # Contabo VPS bootstrap via rescue mode
secrets/               # sops-encrypted secrets (age keys, gitignored)
tests/
  eval/config-checks.nix  # 47 offline eval assertions
  vm/ssh-reachability.nix # NixOS VM integration test
  live/*.bats              # Live BATS tests over SSH
```

## Key Decisions

- **Flakes + home-manager**: Reproducible, lockfile-pinned (nixos-25.11)
- **Docker**: Engine with `--iptables=false`; NAT via nftables; docker0 NOT trusted by default
- **Restic to B2**: Automated daily backups to Backblaze B2 (S3 API)
- **sops-nix secrets**: All credentials encrypted, decrypted at activation via age keys
- **Agent tooling**: llm-agents overlay provides claude-code + codex; nono sandbox via `nono.nix` and `agent-sandbox.nix`
- **Agent sandbox**: Landlock deny-by-default filesystem, PWD restricted to project root, read access scoped to current git repo, nix daemon socket opt-in. Per-wrapper credential allowlists (least privilege). Env injection — real keys enter the child process (proxy mode requires org.freedesktop.secrets, unavailable on headless servers).
- **SSH hardened**: Port 22 on public firewall (key-only, srvos defaults); deploy prefers Tailscale MagicDNS
- **Network model**: Only ports 22 + 22000 on public firewall by default. Ports 80/443 conditional on nginx. All internal services bind 127.0.0.1 (dashboard, syncthing GUI). Tailscale for internal access.
- **Privilege model**: `dev` is the operator (wheel, docker, human admin). `agent` runs sandboxed tools (no wheel, no docker). Parameterized via `tsurf.agent.{user, home, projectRoot}`. Build-time assertions enforce agent user security invariants.
- **Per-host explicit imports**: Each host/default.nix lists all imports directly

## Module Conventions & Patterns

- One module per concern. Prefer adding to existing modules over new ones for <20 lines.
- Each host `default.nix` lists imports explicitly (no module hub).
- Secrets managed via sops-nix (age key derived from SSH host key).
- All service configs are declarative — no imperative setup steps.
- Infrastructure repos cloned via activation scripts (clone-only, never pull).
- Internal services use `openFirewall = false` + `trustedInterfaces` (Tailscale-only).
- `@decision` annotations on security-relevant choices in module headers.

### NixOS module authoring

- Module anatomy: start with header comments and `@decision` annotations, use
  `{ config, lib, pkgs, ... }:` as the function signature, define repeated values in `let`,
  and keep the declarative body in the final attrset.
- Register services on the dashboard with `services.dashboard.entries.<name>` (from
  `modules/dashboard.nix`). Required fields: `name`, `description`, `icon`, `order`.
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
| VM integration (requires KVM) | `nix build .#vm-test-ssh` | Not available on VPS |
| Live tests over SSH | `nix run .#test-live -- --host neurosys` | After deploy only |
| JSON output | `scripts/run-tests.sh --live --json` | After deploy only |

### Test conventions

- One assertion per test, host-prefixed names (`neurosys: tailscaled.service is active`).
- Tests are idempotent and read-only.
- Helpers in `tests/lib/common.bash`.

### Adding eval checks

In `tests/eval/config-checks.nix`:
- Copy the `mkCheck` pattern already used in the file.
- Use `neurosysCfg` for the services host and `devCfg` for the dev host.
- For source checks on modules not imported directly, use `builtins.readFile` + `lib.hasInfix`.

### Debugging eval failures

- The failing check name maps directly to a derivation in `config-checks.nix`.
- Read that check's failure message to identify which invariant failed.
- Common causes: missing `git add`, missing host import, assertion violation in
  `modules/networking.nix`, wrong option type.

## Security

### Hard-stop rules

- **Never** add ports to `networking.firewall.allowedTCPPorts`; add to `internalOnlyPorts` in `modules/networking.nix`.
- **Never** commit unencrypted secrets; use sops-nix with minimal ownership.
- **Never** embed credentials in URLs or CLI args.
- **Never** weaken nono sandbox defaults in `nono.nix`.
- **Never** run agents with `--no-sandbox` unless explicitly instructed for a trusted operation.
- **Never** mount Docker socket without a documented `@decision`.
- **Never** add packages imperatively (`nix-env`, `nix profile install`) or re-enable `nix.channel.enable` / `nix.nixPath`.
- **Never** remove `modules/break-glass-ssh.nix` from either host config.
- **Never** omit `@decision` annotations for security-relevant module choices.

### Pre-flight checklist

Run before every module or service commit:

1. **Port exposure** — New port? Add to `internalOnlyPorts` in `modules/networking.nix`. NEVER add to `networking.firewall.allowedTCPPorts`.
2. **Secrets** — New secret? Add to `secrets.nix` with minimal `owner`/permissions. Use `sops.templates` for env files. NEVER embed credentials in URLs, CLI args, or committed files.
3. **New service** — Set `openFirewall = false`. Add `@decision` annotation. Add port to `internalOnlyPorts` and dashboard entry to `services.dashboard.entries`.
4. **Sandbox impact** — Modifying `agent-compute.nix` or `nono.nix`? Verify `/run/secrets` and `~/.ssh` remain in the deny list. NEVER weaken nono sandbox defaults.
5. **Agent execution** — NEVER run agents with `--no-sandbox` unless explicitly instructed. Requires `AGENT_ALLOW_NOSANDBOX=1`.
6. **Docker** — NEVER mount Docker socket without `@decision` annotation.
7. **Package management** — NEVER use `nix-env`, `nix profile install`, or re-enable `nix.channel.enable` / `nix.nixPath`.
8. **Break-glass key** — NEVER remove `modules/break-glass-ssh.nix` from either host config.
9. **Validation** — `nix flake check` passes.

### Accepted Risks (documented, not actionable)

- **Docker containers:** External service containers lack hardening (read-only rootfs, cap-drop). NixOS-managed containers inherit module defaults.
- **Pre-built binaries:** zmx and cass lack signature verification — mitigated by SHA256 hash pinning.
- **No-sandbox agents:** `--no-sandbox` = effective root access (dev → wheel → sudo). Mitigated by default sandbox-on, audit logging, operator awareness.
- **Sandbox read access:** Sandboxed agents have read-only access to the current git repo root (not all of `/data/projects`). No `.env` files on server (sops-nix handles secrets). Unrestricted network egress (agents need API/git access; nono allowlist filtering not yet available on headless servers). Metadata endpoint blocked at nftables level.
- **Public template users:** `users.allowNoPasswordLogin = true` required for eval without real credential hashes. Private overlay replaces `users.nix` entirely.
- **srvos defaults:** Relied upon implicitly (fail2ban, SSH hardening, systemd-networkd). Specific overrides documented per-host with `mkForce`.
- **Break-glass key:** Public repo uses a placeholder. Private overlay MUST replace with a dedicated offline-stored key before deploying.
- **fail2ban disabled:** SSH brute-force protection relies on key-only auth, MaxAuthTries 3, and srvos defaults. Re-enable if brute-force attempts become problematic.
- **nono proxy_credentials:** Disabled — nono v0.16.0 requires a system keystore unavailable on headless servers. API keys pass through wrapper env directly.
- **dev-agent bypassPermissions:** `dev-agent.nix` runs claude with `--permission-mode=bypassPermissions` inside nono sandbox. Sandbox provides the actual permission boundary.
- **Manual internalOnlyPorts:** Must be kept in sync with actual service ports. Mitigated by existing firewall assertion.
- **SEC105-01:** Template ships insecure defaults (placeholder SSH keys, passwordless sudo, empty-password login). Required for public template to evaluate without real credentials. Private overlay replaces `users.nix` entirely.
- **SEC105-02:** Unrestricted network egress for sandboxed agents (`--net-allow`). nono upstream does not yet support allowlist-based outbound filtering on headless servers. UID-based nftables egress filtering is now available as opt-in via `services.agentSandbox.egressControl.enable` (restricts agent user to whitelisted TCP destination ports).
- **SEC105-03:** Public repo size (dashboard, cost-tracker, restic, syncthing, dev-agent, deploy.sh in core). Moving to `examples/` is large structural work; current modules serve both public template and private overlay.
- **SEC105-04:** Service modules coupled to dashboard via `services.dashboard.entries.*`. Catalog abstraction is YAGNI at current scale.
- **SEC105-05:** Hard-coded `dev` username, `/home/dev`, `/data/projects` paths for the operator user. Agent-specific paths (`/home/agent`, agent user) are parameterized via `tsurf.agent.*` options. `dev` remains hard-coded as the operator user.
- **SEC105-06:** (RESOLVED in Phase 106) `home-manager.users.dev` moved to per-host config.
- **SEC105-07:** `deploy.sh` is 558 lines with custom logic. Serves its purpose for private overlay deployment; public users can use bare `deploy-rs`.
- **SEC114-01:** File-based agent audit log (`/data/projects/.agent-audit/agent-launches.log`) is owned by the same user that runs agents. Mitigated by dual-logging to journald (root-owned, append-only). File log kept as grep-friendly convenience; journald is the trustworthy audit source.
- **SEC114-02:** `dev-agent.sh` parent env no longer exports raw API keys. Wrapper handles credential injection via `AGENT_CREDENTIALS` + nono `--env-credential-map`. Raw keys still reach the sandboxed child process as env vars — full broker/proxy model is future work (see security review #5).
- **SEC115-01:** Flat tailnet trust model — `tailscale0` in trustedInterfaces means all tailnet devices reach all internal services. Mitigated by binding services to 127.0.0.1 and relying on Tailscale device authentication. Production should use Tailscale ACL tags. See SECURITY.md "Tailnet Segmentation".
- **SEC116-01:** Agent resource limits via `tsurf-agents.slice` set aggregate ceilings (8G/300%/1024 tasks). Per-unit limits on dev-agent (4G/200%/256 tasks, OOMPolicy=kill). Limits are conservative defaults; production may need tuning based on workload.
- **SEC116-02:** Syncthing defaults to tailnet-only operation (global announce, local announce, relays, NAT all disabled). Public BEP port 22000 requires explicit `publicBep` opt-in. Private overlay should enable `publicBep` only if non-Tailscale peers are needed.

## Sandbox Awareness

When running inside the nono sandbox (as the `agent` user — no wheel, no docker):

- Launch from inside `/data/projects`; wrapper scripts reject sandboxed launches outside that root.
- Read access is scoped to the current git repo root, not all of `/data/projects`.
- API keys are loaded from `/run/secrets/` by the wrapper and injected as environment variables into the sandboxed child via nono `--env-credential-map`.
- Denied paths include `/run/secrets/`, `~/.ssh`, `~/.bash_history`, `~/.gnupg`, `~/.aws`, and `~/.docker`.
- `--no-sandbox` escape is blocked unless `AGENT_ALLOW_NOSANDBOX=1` is set.
- Launch audit entries are sent to journald (`journalctl -t agent-launch`) and also written to `/data/projects/.agent-audit/agent-launches.log` as a convenience log. The journald log is the trustworthy source (root-owned, append-only); the file log is user-owned and not tamper-proof.
- For guided workflows, use `/nix-module` for module authoring and `/nix-test` for test execution + `.test-status`.

## Deployment Rules

**CRITICAL — read before running any deploy:**

- **ALL deploys MUST come from the PRIVATE overlay** — both hosts run private config:
  ```
  cd /path/to/private-tsurf && ./scripts/deploy.sh [--node neurosys|neurosys-dev]
  ```
- **`scripts/deploy.sh` in this public repo refuses ALL deploys** (enforced: `tsurf.url` guard detects public repo)
- **NEVER run `nixos-rebuild switch --flake .#neurosys`** or `.#neurosys-dev` from this repo — the public flake has placeholder SSH keys and no private services; it will break the server
- **NEVER run `nixos-rebuild switch` from ANY repo** (parts, home-assistant-config, or any other) — even with the correct flake, this bypasses deploy.sh's safety guard, watchdog, and shared deploy lock. The ONLY safe deploy path is `./scripts/deploy.sh` from the private overlay
- For first-time OVH bootstrap: `examples/bootstrap/bootstrap-ovh.sh` installs base NixOS, then follow with private overlay deploy

## Recovery (Out-of-Band)

If SSH access is lost, regain access via provider console:

- **Contabo:** KVM VNC console (my.contabo.com -> VPS -> VNC tab). Log in as root, then `nixos-rebuild switch --rollback` or manually fix `/persist/root/.ssh/authorized_keys`.
- **OVH:** Rescue mode (ovh.com/manager -> VPS -> Boot -> Rescue). SSH into rescue, mount persist subvolume (`mount /dev/sda3 /mnt -o subvol=persist`), fix authorized_keys or chroot + rollback. Switch boot back to hard disk after.

After recovery: identify root cause (`journalctl -b -1 -p err`), deploy via private overlay only, verify break-glass key is present.

## Private Overlay

Personal services, real credentials, and host-specific config go in a separate private flake
that imports this repo's modules. The private flake:

- Uses `follows` to share dependencies (nixpkgs, home-manager, sops-nix, etc.)
- Imports public modules individually (no hub/default import)
- Can replace modules entirely (users.nix, syncthing.nix) or import and extend
- Extends eval checks by importing `tests/eval/config-checks.nix`

## Simplicity Conventions

- Every new module must justify its existence — prefer adding to existing modules over creating new ones for <20 lines
- No dead code — unused options, packages, or features must be removed immediately
- YAGNI — do not add features "for later" unless they are in an active phase plan
- One source of truth — packages declared in exactly one module (no duplicates across modules)
- Prefer inline over separate files for small configs (<10 lines); extract larger bash/python to separate files
- Let bindings for values used more than once (e.g., Tailscale IP in homepage.nix)
- `tmp/` in project root for temporary files (never `/tmp/`) — convention from global CLAUDE.md
- `disabledModules` for private overlay: only justified when the public module references non-existent users/resources in private config (users.nix, agent-compute.nix), or when the entire content differs (homepage.nix, syncthing.nix). For service modules (automaton, openclaw, matrix), import from public and override only what differs.

## Module Change Checklist

Before committing any module change:

1. Run the full [Security pre-flight checklist](#pre-flight-checklist).
2. Verify module placement follows [NixOS module authoring](#nixos-module-authoring) (<20 lines extends existing module, new service gets its own file).
3. Ensure explicit host imports are updated in `hosts/services/default.nix` and/or `hosts/dev/default.nix`.
4. Follow [Testing workflow](#testing-workflow), including `.test-status` output for the commit guard.
5. If creating or restructuring a module, invoke `/nix-module`. If validating tests or check failures, invoke `/nix-test`.
