# Requirements: agent-neurosys

**Defined:** 2026-02-13
**Core Value:** One command to deploy a fully working development server with all services running, all tools installed, and all infrastructure repos cloned — no manual setup steps.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Boot & Deployment

- [ ] **BOOT-01**: NixOS boots on Contabo VPS from flake-based configuration with all inputs pinned via flake.lock
- [ ] **BOOT-02**: disko manages disk layout (EFI + root partition) compatible with Contabo hardware
- [ ] **BOOT-03**: Server can be fully deployed via single `nixos-anywhere` command over SSH
- [ ] **BOOT-04**: GRUB boot loader configured for hybrid BIOS/UEFI compatibility on Contabo
- [ ] **BOOT-05**: Nix garbage collection runs weekly, deleting generations older than 30 days
- [ ] **BOOT-06**: Nix store optimization (hard-link dedup) runs automatically

### Networking & Security

- [ ] **NET-01**: SSH accessible with key-only authentication (password and keyboard-interactive auth disabled, root login disabled)
- [ ] **NET-02**: Firewall enabled with default-deny policy using nftables backend
- [ ] **NET-03**: Tailscale VPN connected to tailnet with `tailscale0` as trusted firewall interface
- [ ] **NET-04**: Firewall allows only SSH (22), HTTP (80), HTTPS (443), and Syncthing (22000) on public interface
- [ ] **NET-05**: fail2ban protects SSH with automatic IP banning and exponential ban times
- [ ] **NET-06**: Tailscale reverse path filtering set to "loose" to prevent routing conflicts

### Secrets Management

- [ ] **SEC-01**: sops-nix decrypts secrets at activation time to `/run/secrets/` using age encryption
- [ ] **SEC-02**: Age key derived from SSH host key via `ssh-to-age`; host key pre-generated before deployment
- [ ] **SEC-03**: All service credentials (Tailscale authkey, B2 creds, Docker env files, SSH keys) stored as encrypted sops secrets in-repo

### System Identity

- [ ] **SYS-01**: Non-root user `dangirsh` with sudo access and docker group membership
- [ ] **SYS-02**: Hostname set to `acfs`, timezone `Europe/Berlin`, locale `C.UTF-8`

### Development Tools

- [ ] **DEV-01**: Git configured with identity (Dan Girshovich, dangirsh@users.noreply.github.com) and GitHub CLI (gh) available
- [ ] **DEV-02**: Bun, Node.js, and pnpm installed from nixpkgs
- [ ] **DEV-03**: Rust available via rustup (user manages nightly/stable toolchains)
- [ ] **DEV-04**: Go and Python 3 installed from nixpkgs
- [ ] **DEV-05**: Neovim, fd, ripgrep, jq, and git-lfs installed from nixpkgs

### Shell & Home Environment

- [ ] **HOME-01**: home-manager integrated as NixOS module, managing user `dangirsh` config
- [ ] **HOME-02**: Zsh configured with completions, syntax highlighting, and autosuggestions
- [ ] **HOME-03**: Tmux configured for persistent terminal sessions
- [ ] **HOME-04**: Atuin shell history configured and syncing
- [ ] **HOME-05**: Starship prompt configured

### Docker Services

- [ ] **DOCK-01**: Docker engine running with `--iptables=false` to prevent firewall bypass
- [ ] **DOCK-02**: claw-swap stack running: Caddy (ports 80/443), app (port 3000 internal), PostgreSQL 16 (port 15432) on `claw-swap-net` network
- [ ] **DOCK-03**: grok-mcp container running on port 9601
- [ ] **DOCK-04**: Docker networks (`claw-swap-net`) declared in Nix, created before dependent containers start

### System Services

- [ ] **SVC-01**: Ollama service running with `nomic-embed-text` model loadable (CPU-only)
- [ ] **SVC-02**: Syncthing running as user `dangirsh` with declarative devices and folders (`overrideDevices`, `overrideFolders`)
- [ ] **SVC-03**: CASS indexer running as user-level systemd service via home-manager (`cass index --watch`)

### Agent Tooling

- [ ] **AGENT-01**: `global-agent-conf` repo cloned to `/data/projects/global-agent-conf` and symlinked to `~/.claude`
- [ ] **AGENT-02**: Infrastructure repos (`parts`, `claw-swap`) cloned to `/data/projects/` via idempotent activation scripts

### Backups

- [ ] **BACK-01**: Restic automated daily backups to Backblaze B2 via S3 API with retention policy (7 daily, 5 weekly, 12 monthly)

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Backup Monitoring

- **BACK-02**: Restic backup failure triggers notification (email or webhook)

### Hardening

- **HARD-01**: Per-service systemd hardening (PrivateTmp, NoNewPrivileges, ProtectSystem, ProtectHome)
- **HARD-02**: Advanced SSH hardening (cipher restriction, idle timeout, X11 forwarding disabled)
- **HARD-03**: Persistent journal with `Storage=persistent` and `SystemMaxUse=500M`
- **HARD-04**: Boot generation limit set to 20 via `configurationLimit`
- **HARD-05**: Automated flake.lock update pipeline (scheduled CI job or systemd timer)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Convert Docker containers to native NixOS services | Massive migration effort for marginal gain. Existing Docker workflows work. Nix manages containers via `oci-containers` |
| Impermanence (tmpfs root) | Significant complexity to track every piece of state. Poor cost/benefit for a single dev server |
| Full monitoring stack (Prometheus + Grafana) | Overkill for single dev server with one operator. Consumes RAM alongside Ollama |
| system.autoUpgrade with flakes | Breaks reproducibility, overwrites `flake.lock` outside git, can break SSH access on remote server |
| LUKS disk encryption | Contabo VPS cannot enter passphrase on boot. No meaningful threat model benefit at hypervisor layer |
| Multiple nixpkgs channels/overlays | Maintenance burden, breaks binary cache hits. Use nixpkgs-unstable + rustup for nightly |
| dockerTools for all images | Only use for images that benefit (grok-mcp). Standard Dockerfiles for everything else |
| Cockpit web admin panel | Additional attack surface. NixOS config files ARE the management interface |
| SELinux | Experimental on NixOS as of 2025. Use systemd hardening instead |
| ACFS shell framework | Barely used. home-manager replaces from scratch |
| claude-memory-daemon | Experiment, not production. Can add later if needed |
| MCP Agent Mail | Not included as managed service. Can add later |
| Multi-host fleet management | Single-host for now. Flake structure supports adding hosts later |
| GUI/desktop environment | Headless server only |
| Ollama model management | Models downloaded manually after deploy |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| BOOT-01 | — | Pending |
| BOOT-02 | — | Pending |
| BOOT-03 | — | Pending |
| BOOT-04 | — | Pending |
| BOOT-05 | — | Pending |
| BOOT-06 | — | Pending |
| NET-01 | — | Pending |
| NET-02 | — | Pending |
| NET-03 | — | Pending |
| NET-04 | — | Pending |
| NET-05 | — | Pending |
| NET-06 | — | Pending |
| SEC-01 | — | Pending |
| SEC-02 | — | Pending |
| SEC-03 | — | Pending |
| SYS-01 | — | Pending |
| SYS-02 | — | Pending |
| DEV-01 | — | Pending |
| DEV-02 | — | Pending |
| DEV-03 | — | Pending |
| DEV-04 | — | Pending |
| DEV-05 | — | Pending |
| HOME-01 | — | Pending |
| HOME-02 | — | Pending |
| HOME-03 | — | Pending |
| HOME-04 | — | Pending |
| HOME-05 | — | Pending |
| DOCK-01 | — | Pending |
| DOCK-02 | — | Pending |
| DOCK-03 | — | Pending |
| DOCK-04 | — | Pending |
| SVC-01 | — | Pending |
| SVC-02 | — | Pending |
| SVC-03 | — | Pending |
| AGENT-01 | — | Pending |
| AGENT-02 | — | Pending |
| BACK-01 | — | Pending |

**Coverage:**
- v1 requirements: 37 total
- Mapped to phases: 0
- Unmapped: 37 (pending roadmap creation)

---
*Requirements defined: 2026-02-13*
*Last updated: 2026-02-13 after initial definition*
