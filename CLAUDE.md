# CLAUDE.md — neurosys

NixOS configuration for the `neurosys` server (and future machines). Declarative system management with flakes + home-manager.

## Project Structure

```
flake.nix              # Entrypoint — inputs (7), outputs, nixosConfigurations.neurosys
flake.lock             # Pinned dependencies (nixpkgs 25.11, home-manager, sops-nix, disko, parts, claw-swap, llm-agents)
hosts/
  neurosys/
    default.nix        # Host-specific NixOS config (imports all modules)
    hardware.nix       # Hardware/disk config (disko, Contabo VPS)
modules/
  default.nix          # Import hub for all modules
  base.nix             # Nix settings, system packages, kernel sysctl hardening
  boot.nix             # GRUB bootloader config
  networking.nix       # Firewall (nftables), SSH (hardened), Tailscale, fail2ban
  users.nix            # User accounts, sudo, SSH authorized keys
  secrets.nix          # sops-nix secret declarations
  docker.nix           # Docker engine (--iptables=false), NAT
  monitoring.nix       # Prometheus + node_exporter + alert rules
  syncthing.nix        # Syncthing file sync service
  home-assistant.nix   # Home Assistant + ESPHome
  homepage.nix         # Homepage dashboard (Tailscale-only)
  agent-compute.nix    # Agent CLI (claude, codex), bubblewrap sandbox, Podman, agent-spawn
  repos.nix            # Idempotent repo cloning on activation
  restic.nix           # Restic backup to Backblaze B2
home/
  default.nix          # home-manager import hub
  bash.nix             # Bash shell + API key exports
  git.nix              # Git + gh CLI config
  ssh.nix              # SSH client config
  direnv.nix           # Direnv auto-loading
  cass.nix             # CASS indexer timer
  agent-config.nix     # ~/.claude and ~/.codex symlinks
packages/
  zmx.nix              # Pre-built zmx terminal multiplexer binary
  cass.nix             # Pre-built CASS indexer binary
scripts/
  deploy.sh            # Deploy script (local/remote build, locking, container health check)
secrets/
  neurosys.yaml            # sops-encrypted secrets (7 secrets + 1 template)
```

## Key Decisions

- **Flakes + home-manager**: Modern, reproducible, lockfile-pinned (nixos-25.11)
- **Docker stays**: Containers declared in Nix (parts, claw-swap), `--iptables=false`
- **Restic to B2**: Automated daily backups to Backblaze B2 (S3 API)
- **sops-nix secrets**: All credentials encrypted, decrypted at activation via age keys
- **Agent tooling**: llm-agents overlay provides claude-code + codex; bubblewrap sandbox via agent-spawn
- **SSH hardened**: Port 22 on public firewall (key-only, fail2ban-protected); deploy prefers Tailscale MagicDNS but public SSH enables bootstrap/recovery when Tailscale is unavailable
- **Kernel hardening**: sysctl settings restrict dmesg, kptr, BPF, ICMP redirects

## Conventions

- One module per concern (networking, services, dev-tools)
- Secrets managed via sops-nix (age key derived from SSH host key)
- All service configs are declarative -- no imperative setup steps
- Infrastructure repos cloned via activation scripts (clone-only, never pull)
- Internal services use `openFirewall = false` + `trustedInterfaces` (Tailscale-only)
- `@decision` annotations on security-relevant choices in module headers

## Testing

Two-layer test architecture: Nix eval checks (offline) + BATS live tests (SSH).

### Eval Checks (offline, fast)
```bash
nix flake check
```
Validates config evaluation and expected security/service invariants for `neurosys` and `ovh`.

### Live Tests (SSH to running hosts)
```bash
nix run .#test-live -- --host neurosys
nix run .#test-live -- --host neurosys-prod
scripts/run-tests.sh --live
scripts/run-tests.sh --live --json
```
`--json` emits one JSON object per test (`name`, `status`, `error`) for agent parsing.

### When a Test Fails
- Read BATS failure output and follow `DEBUG:` commands.
- SSH to the target host and validate service/runtime state directly.
- Re-run only affected test files first, then full suite.

### Test Conventions
- One assertion per test with host-prefixed names (e.g. `neurosys: prometheus.service is active`).
- Keep tests idempotent and read-only.
- Prefer helpers from `tests/lib/common.bash`.
- `scripts/run-tests.sh` writes `.claude/.test-status` for agent-runnable status checks.

### Private Overlay Tests
The private overlay extends the public suite. See `tests/eval/config-checks.nix`
for the extension pattern. Private tests cover private agent fleets, nginx
vhosts, ACME cert domains, and private service stacks.

## Deployment Rules

**CRITICAL — read before running any deploy:**

- **ALL deploys MUST come from the PRIVATE overlay** — both hosts run private config:
  ```
  cd /data/projects/private-neurosys && ./scripts/deploy.sh [--node neurosys|ovh]
  ```
- **`scripts/deploy.sh` in this public repo refuses ALL deploys** (enforced: `neurosys.url` guard detects public repo)
- **NEVER run `nixos-rebuild switch --flake .#neurosys`** or `.#ovh` from this repo — the public flake has placeholder SSH keys and no private services; it will break the server
- For first-time OVH bootstrap: `scripts/bootstrap-ovh.sh` installs base NixOS, then follow with private overlay deploy

## Security Conventions

Rules that agents MUST follow when modifying any module:

- **Never** add ports to `networking.firewall.allowedTCPPorts` -- the port 22 assertion and `internalOnlyPorts` assertion in `networking.nix` enforce this at build time, but do not attempt to weaken or remove these assertions
- **Never** commit unencrypted secrets to any file -- use sops-nix for all credentials
- **Never** embed credentials in URLs or command-line arguments -- use environment variables, credential helpers, or file-based injection
- **Never** weaken the bubblewrap sandbox defaults in `agent-compute.nix` -- `--no-sandbox` is for trusted operations only
- **Never** run Claude Code or Codex with `--no-sandbox` unless explicitly instructed by the user for a specific trusted operation -- sandbox is the default for a reason (CVE: GHSA-ff64-7w26-62rf)
- **Never** mount the Docker socket into a service unless strictly required and documented with a @decision annotation
- All network-facing services MUST have `openFirewall = false` (Tailscale-only via `trustedInterfaces`)
- New services MUST add their port to `internalOnlyPorts` in `networking.nix` if they should not be public
- All new modules MUST include `@decision` annotations for security-relevant choices
- Pre-built binaries (packages/*.nix) use SHA256 hash verification -- accepted risk, no signature verification available (SEC11)

### Accepted Risks (documented, not actionable)

- **SEC3:** Docker container hardening (read-only rootfs, cap-drop, no-new-privileges) — PARTIALLY ADDRESSED in Phase 47-02 (secret-proxy, monitoring hardened). Parts/claw-swap containers remain external.
- **SEC5:** `--no-sandbox` agents can modify `~/.claude/settings.json` -- mitigated by default sandbox-on and requiring explicit `--no-sandbox` flag
- **SEC6:** Docker socket mounted in homepage-dashboard -- mitigated by Tailscale-only access (port 8082 in internalOnlyPorts)
- **SEC9:** Systemd service hardening — PARTIALLY ADDRESSED in Phase 47-02 (secret-proxy, Prometheus, node-exporter, tailscale-serve-ha hardened). Remaining services use NixOS module defaults.
- **SEC11:** Pre-built binaries (zmx, cass) lack signature verification -- mitigated by SHA256 hash pinning
- **SEC47-13:** `--no-sandbox` agent = effective root access — inherent to design. Mitigated by default sandbox-on, audit logging, operator awareness.
- **SEC47-15:** Sandboxed agents have read-only access to all `/data/projects` — deliberate for cross-project reference. No `.env` files on server (sops-nix handles secrets).
- **SEC47-16:** `anthropic-api-key` is broadly shared (bash, agentd, openclaw, spacebot) — secret-proxy mitigates for claw-swap agents. Per-consumer key rotation out of scope.
- **SEC49-01:** Bootstrap script passwords (`CONTABO_PASS` default, `OVH_NEW_PASS`) remain in public git history (commits prior to Phase 49). Both passwords are ephemeral — used only during initial Ubuntu install which is immediately wiped by nixos-anywhere. Rewriting public repo history is impractical. Risk: minimal (passwords are useless after bootstrap completes).
- **Sandbox design choices:** Cross-project read access (deliberate for sibling repo reference), no network sandboxing (agents need API/git access), metadata endpoint blocked at nftables level
- **SEC50-01:** Public template `users.allowNoPasswordLogin = true` — required for the public template to evaluate without real credential hashes. Private overlay replaces `users.nix` entirely and does NOT set this. The setting only affects the public template, never the deployed config.
- **SEC50-02:** `srvos.nixosModules.server` imports numerous server defaults (fail2ban, SSH hardening, systemd-networkd) that are relied upon implicitly. Specific overrides are documented per-host with `mkForce`. A full audit of srvos defaults is deferred to a future phase.

## Simplicity Conventions

Rules to prevent bloat and over-engineering:

- Every new module must justify its existence -- prefer adding to existing modules over creating new ones for <20 lines
- No dead code -- unused options, packages, or features must be removed immediately
- YAGNI -- do not add features "for later" unless they are in an active phase plan
- One source of truth -- packages declared in exactly one module (no duplicates across modules)
- Prefer inline over separate files for small configs (<20 lines)
- Let bindings for values used more than once (e.g., Tailscale IP in homepage.nix)
- `tmp/` in project root for temporary files (never `/tmp/`) -- convention from global CLAUDE.md
- `disabledModules` for private overlay: only justified when the public module references non-existent users/resources in private config (users.nix, agent-compute.nix), or when the entire content differs (homepage.nix, syncthing.nix). For service modules (automaton, openclaw, spacebot, matrix), import from public and override only what differs.

## Module Change Checklist

Before committing any module change, verify:

1. **Port exposure:** Does this change expose a new port? Add to `internalOnlyPorts` in `networking.nix`, or justify public exposure with a @decision annotation
2. **Secret handling:** Does this change add a new secret? Verify owner/permissions are minimal in `secrets.nix`
3. **New service:** Does this change add a service? Set `openFirewall = false` and add @decision annotation
4. **Sandbox impact:** Does this change modify `agent-compute.nix`? Verify `/run/secrets` and `~/.ssh` remain hidden from sandboxed agents
5. **Credentials:** Does this change handle tokens or API keys? Use env vars or sops-nix, never URLs or CLI args
6. **Validation:** `nix flake check` passes
