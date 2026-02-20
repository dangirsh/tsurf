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
  networking.nix       # Firewall (nftables), SSH (Tailscale-only), Tailscale, fail2ban
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
- **SSH via Tailscale only**: Port 22 not on public firewall; deploy uses Tailscale MagicDNS
- **Kernel hardening**: sysctl settings restrict dmesg, kptr, BPF, ICMP redirects

## Testing

NixOS configs are validated with:
- `nix flake check` — Flake evaluation
- `nixos-rebuild build --flake .#neurosys` — Build without switching
- `nixos-rebuild test --flake .#neurosys` — Build and switch (test, no boot entry)

## Conventions

- One module per concern (networking, services, dev-tools)
- Secrets managed via sops-nix (age key derived from SSH host key)
- All service configs are declarative -- no imperative setup steps
- Infrastructure repos cloned via activation scripts (clone-only, never pull)
- Internal services use `openFirewall = false` + `trustedInterfaces` (Tailscale-only)
- `@decision` annotations on security-relevant choices in module headers

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

- **SEC3:** Docker container hardening (read-only rootfs, cap-drop, no-new-privileges) is deferred -- containers are declared in external repos (parts, claw-swap), changes needed there
- **SEC5:** `--no-sandbox` agents can modify `~/.claude/settings.json` -- mitigated by default sandbox-on and requiring explicit `--no-sandbox` flag
- **SEC6:** Docker socket mounted in homepage-dashboard -- mitigated by Tailscale-only access (port 8082 in internalOnlyPorts)
- **SEC9:** Systemd service hardening (ProtectHome, PrivateTmp) is deferred -- NixOS service modules provide baseline defaults, custom overrides risk breaking services
- **SEC11:** Pre-built binaries (zmx, cass) lack signature verification -- mitigated by SHA256 hash pinning
- **Sandbox design choices:** Cross-project read access (deliberate for sibling repo reference), no network sandboxing (agents need API/git access), metadata endpoint blocked at nftables level

## Simplicity Conventions

Rules to prevent bloat and over-engineering:

- Every new module must justify its existence -- prefer adding to existing modules over creating new ones for <20 lines
- No dead code -- unused options, packages, or features must be removed immediately
- YAGNI -- do not add features "for later" unless they are in an active phase plan
- One source of truth -- packages declared in exactly one module (no duplicates across modules)
- Prefer inline over separate files for small configs (<20 lines)
- Let bindings for values used more than once (e.g., Tailscale IP in homepage.nix)
- `tmp/` in project root for temporary files (never `/tmp/`) -- convention from global CLAUDE.md

## Module Change Checklist

Before committing any module change, verify:

1. **Port exposure:** Does this change expose a new port? Add to `internalOnlyPorts` in `networking.nix`, or justify public exposure with a @decision annotation
2. **Secret handling:** Does this change add a new secret? Verify owner/permissions are minimal in `secrets.nix`
3. **New service:** Does this change add a service? Set `openFirewall = false` and add @decision annotation
4. **Sandbox impact:** Does this change modify `agent-compute.nix`? Verify `/run/secrets` and `~/.ssh` remain hidden from sandboxed agents
5. **Credentials:** Does this change handle tokens or API keys? Use env vars or sops-nix, never URLs or CLI args
6. **Validation:** `nix flake check` passes
