# Feature Research

**Domain:** Declarative NixOS server configuration (dev server with Docker, AI tooling, backups)
**Researched:** 2026-02-13
**Confidence:** HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

Features required for the server to be functional and safe. Missing any of these means the server is unusable or dangerously exposed.

#### Boot and Base System

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Flake-based NixOS configuration | Reproducibility is the entire point of NixOS; channels are legacy | LOW | `flake.nix` as entrypoint with `flake.lock` pinning all inputs |
| disko disk partitioning | Required for `nixos-anywhere` deployment; manual partitioning defeats the purpose | MEDIUM | EFI + single root partition. Keep it simple -- no ZFS, no LUKS (Contabo VPS, not a laptop) |
| nixos-anywhere deployment | One-command install to Contabo VPS from any machine with Nix | MEDIUM | Requires SSH access to target (Contabo provides Ubuntu); kexec into NixOS installer |
| Boot loader (systemd-boot) | Server must boot. systemd-boot is the standard for UEFI NixOS | LOW | `boot.loader.systemd-boot.enable = true` |
| SSH access with key-only auth | Only way to access a headless server; password auth is a security liability | LOW | `services.openssh.enable = true`, `settings.PasswordAuthentication = false`, `settings.PermitRootLogin = "no"` |
| Firewall (default-deny) | Current server has NONE -- this is the single most critical security gap | LOW | `networking.firewall.enable = true` with explicit allowedTCPPorts for SSH (22), HTTP (80), HTTPS (443), Syncthing (22000) |
| Tailscale VPN | Secure overlay network for private access; already in use | LOW | `services.tailscale.enable = true`, trust `tailscale0` interface in firewall, allow Tailscale UDP port |
| User account with sudo | Need a non-root user for daily operations and home-manager | LOW | Single user `dangirsh` with `extraGroups = ["wheel" "docker"]` |
| Timezone and locale | Server must have correct time for logs, cron, TLS | LOW | `time.timeZone = "Europe/Berlin"`, `i18n.defaultLocale = "C.UTF-8"` |
| Hostname and networking | Basic identity and connectivity | LOW | `networking.hostName = "acfs"`, DHCP on primary interface |

#### Secrets Management

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| sops-nix with age encryption | Secrets (SSH keys, API keys, B2 creds) must be encrypted in-repo, decrypted at activation | MEDIUM | Use age (not GPG) -- simpler key management. Derive machine age key from SSH host key via `ssh-to-age`. Secrets decrypted to `/run/secrets/` at activation time |
| Secret files for services | Each service needs its credentials injected securely | MEDIUM | `sops.secrets."restic/b2-env".owner = "root"`, `sops.secrets."tailscale/authkey"`, etc. Wire into service configs via `environmentFile` or `passwordFile` options |

#### Development Tools

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Git + GitHub CLI (gh) | Version control is non-negotiable for a dev server | LOW | `programs.git` via home-manager, `pkgs.gh` in system packages |
| Bun, Node.js, pnpm | JavaScript/TypeScript runtime for existing projects | LOW | All available in nixpkgs |
| Rust via rustup | Nightly toolchain needed; Nix rust-overlay is less flexible for this use case | LOW | Install `rustup` via nixpkgs, let user manage toolchains. Do NOT use nixpkgs `rustc` directly |
| Go, Python 3 | Required for existing projects | LOW | Standard nixpkgs |
| Neovim | Editor for quick server-side edits | LOW | nixpkgs |
| fd, ripgrep, jq, git-lfs | Standard dev utilities already in use | LOW | All in nixpkgs |

#### Shell and Home Environment

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| home-manager (as NixOS module) | Manages user-level config declaratively; the NixOS way to handle dotfiles | MEDIUM | Import as NixOS module (not standalone) for tighter integration. Manages Zsh, Git, tmux, Atuin |
| Zsh with completions and syntax highlighting | Already the user's shell; home-manager manages it natively | LOW | `programs.zsh.enable`, `enableCompletion`, `syntaxHighlighting.enable`, `autosuggestion.enable` |
| Tmux configuration | Terminal multiplexer for persistent sessions on a headless server | LOW | `programs.tmux` via home-manager |
| Atuin shell history | Already in use; syncs shell history | LOW | `programs.atuin` via home-manager |
| Starship prompt | Clean, informative prompt | LOW | `programs.starship` via home-manager |

#### Core Services

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Docker engine | Runs all container workloads; already manages 5 containers | LOW | `virtualisation.docker.enable = true`. Use Docker, not Podman -- existing compose files and workflows depend on it |
| Docker containers (declarative) | Claw-swap stack (Caddy + app + DB), grok-mcp must be declared in Nix | MEDIUM | Use `virtualisation.oci-containers.containers` for each container. Define networks, volumes, port mappings declaratively |
| Docker networks (declarative) | claw-swap-net bridge network needed for inter-container communication | MEDIUM | `systemd.services."docker-network-claw-swap-net"` -- create network before dependent containers start |
| Ollama service | LLM inference (nomic-embed-text) is a core capability of this server | LOW | `services.ollama.enable = true`. CPU-only on Contabo VPS (no GPU). Use `services.ollama.loadModels` for pre-loading models |
| Syncthing | File sync already in use; must survive migration | LOW | `services.syncthing.enable = true` with declarative devices and folders. Run as user `dangirsh` |
| Restic backups to B2 | Automated backups are the safety net; losing this means risking all data | MEDIUM | `services.restic.backups.daily` with B2 repository, credentials from sops-nix, retention policy (`--keep-daily 7 --keep-weekly 5 --keep-monthly 12`) |
| CASS indexer (user systemd service) | User-level service for code indexing; runs `cass index --watch` | MEDIUM | `systemd.user.services.cass-indexer` via home-manager. Needs CASS binary available (install from source or pre-built) |

#### Agent Tooling

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| global-agent-conf cloned and symlinked | Claude Code configuration depends on `~/.claude` being the symlinked repo | MEDIUM | Activation script: clone to `/data/projects/global-agent-conf` if absent, symlink `~/.claude` to it. Idempotent -- skip if already done |
| Claude Code CLI available | Primary AI assistant tool | LOW | Binary at `~/.local/bin/claude` -- either fetch in activation script or add to PATH via home-manager |

### Differentiators (Competitive Advantage)

Features that make this config notably better than a manual Ubuntu setup. Not strictly required for day-one functionality, but provide significant operational value.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| fail2ban SSH protection | Bans IPs after repeated failed SSH attempts; critical for a public-facing server | LOW | `services.fail2ban.enable = true`. NixOS pre-configures the SSH jail automatically. Add `bantime-increment` for exponential ban times. Ignore Tailscale subnet |
| Nix garbage collection (automatic) | Prevents /nix/store from consuming all disk on a 484GB SSD | LOW | `nix.gc.automatic = true`, `nix.gc.dates = "weekly"`, `nix.gc.options = "--delete-older-than 30d"`. Also enable `nix.optimise.automatic = true` for hard-link dedup |
| Nix store optimization | Reduces disk usage by up to 40% through hard-link dedup of identical files | LOW | `nix.optimise.automatic = true` -- runs nightly by default |
| Boot generation management | Limit number of boot generations to prevent /boot from filling up | LOW | `boot.loader.systemd-boot.configurationLimit = 20` |
| Modular flake structure | Each concern in its own module file -- testable, composable, readable | LOW | Already designed: `modules/common.nix`, `modules/dev-tools.nix`, `modules/docker-services.nix`, etc. This is structure, not a feature to build |
| Firewall Tailscale integration | Trust Tailscale interface so all private services are accessible over VPN without opening public ports | LOW | `networking.firewall.trustedInterfaces = ["tailscale0"]`. Services like Syncthing web UI, Ollama API only exposed over Tailscale |
| nftables firewall backend | Modern replacement for iptables; better Tailscale compatibility, cleaner rule management | LOW | `networking.nftables.enable = true`, set Tailscale to use nftables mode. Avoids iptables/nftables conflicts |
| Declarative Syncthing devices/folders | Full Syncthing topology declared in Nix -- no manual web UI setup on rebuild | MEDIUM | `services.syncthing.settings.devices`, `services.syncthing.settings.folders` with `overrideDevices = true`, `overrideFolders = true` |
| Restic backup monitoring | Know when backups fail before you need them | MEDIUM | `systemd.services.restic-backups-daily.unitConfig.OnFailure = "notify-backup-failure.service"` -- send notification (email/webhook) on backup failure |
| Systemd service hardening | Restrict service capabilities to minimum needed (private network, no new privileges, etc.) | MEDIUM | Apply per-service: `PrivateTmp`, `NoNewPrivileges`, `ProtectSystem`, `ProtectHome`. Priority for network-facing services |
| SSH hardening beyond defaults | Disable root login, restrict ciphers, set idle timeout | LOW | `services.openssh.settings.KbdInteractiveAuthentication = false`, `settings.X11Forwarding = false`, `ClientAliveInterval = 300`, `ClientAliveCountMax = 2` |
| Automatic flake.lock updates | Keep nixpkgs current with security patches without manual intervention | MEDIUM | NOT `system.autoUpgrade` (problematic with flakes). Instead: scheduled systemd timer that runs `nix flake update` + `nixos-rebuild switch`, or a CI pipeline that updates flake.lock in the repo |
| Infrastructure repo cloning | `/data/projects/` repos (global-agent-conf, parts, claw-swap) cloned on first boot | MEDIUM | Activation script with idempotent `git clone` calls. Must handle SSH key availability (sops-nix decrypts keys first) |
| Persistent journal | Keep systemd journal across reboots for debugging; default is volatile on some setups | LOW | `services.journald.extraConfig = "Storage=persistent\nSystemMaxUse=500M"` |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems. Explicitly choosing NOT to build these.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Convert Docker containers to native NixOS services | "Pure NixOS" aesthetic; Nix managing everything | Massive migration effort for marginal gain. Existing Docker Compose files work. Caddy-in-Docker handles TLS automatically. Postgres-in-Docker has its own data volume. Converting means rewriting networking, volume mounts, and debugging Nix service wrappers | Keep Docker. Declare containers in Nix via `oci-containers`. Get reproducibility without rewriting working infrastructure |
| Impermanence (tmpfs root) | Security benefit -- attackers can't persist. Clean state on boot | Adds significant complexity to track every piece of state. For a single dev server, the cost/benefit is poor. You'd need to enumerate every file that needs persistence. Breaking changes are painful to debug remotely | Standard persistent root. Use Restic backups as the recovery mechanism. Consider impermanence only if adding more hosts later |
| Full monitoring stack (Prometheus + Grafana) | Observability is "best practice" for production | Overkill for a single dev server with one operator. Consumes RAM and disk on a 47GB VPS already running Ollama. Journal + basic systemd monitoring is sufficient | `journalctl` for logs, systemd service status for health. Add a lightweight health-check script that alerts on service failures. Revisit if hosting production workloads for others |
| system.autoUpgrade with flakes | Keep system updated automatically | Breaks reproducibility guarantees. Overwrites `flake.lock` outside of git. Can introduce breaking changes unattended on a remote server you SSH into. If an upgrade breaks SSH, you're locked out of a Contabo VPS | Manual `nix flake update` + `nixos-rebuild switch` in a tmux session. Or a scheduled CI job that opens a PR with the lock update for review |
| LUKS disk encryption | Encrypt data at rest | Contabo VPS cannot enter a LUKS passphrase on boot (no console access for remote unlock). Adds complexity with no threat model benefit -- if Contabo has physical access, encryption won't help against a nation-state adversary with hypervisor access | No encryption. Trust the VPS provider at the physical layer. Encrypt sensitive data at the application layer (sops-nix for secrets, encrypted Restic backups) |
| Multiple NixOS channels/overlays for bleeding-edge packages | Want latest Bun/Node/Go versions | Overlay maintenance burden. Nixpkgs-unstable is already fairly current. Custom overlays break binary cache hits, increasing build times | Use nixpkgs-unstable channel. For Rust nightly, use rustup (already decided). Accept nixpkgs versions for other tools -- they're close enough |
| Nix-based Docker image building (dockerTools) | Build Docker images with Nix for reproducibility | Adds Nix complexity to container workflows that work fine with standard Dockerfiles. The grok-mcp image is already built this way (good), but don't convert existing images | Use `dockerTools.buildLayeredImage` only for images that benefit from it (like grok-mcp). Use standard Dockerfiles for everything else |
| Cockpit web admin panel | Web-based server management UI | Another attack surface. Another service to maintain. NixOS configuration IS the management interface -- editing `.nix` files and rebuilding is the correct workflow | SSH + NixOS rebuild. That's the whole point |
| SELinux | Mandatory access control for defense in depth | Experimental on NixOS as of 2025. Not production-ready. Would require extensive policy authoring for every service | Rely on systemd service hardening (sandboxing, capability dropping) which NixOS supports well today |

## Feature Dependencies

```
[disko disk partitioning]
    |
    v
[nixos-anywhere deployment]
    |
    v
[Boot + base system (systemd-boot, networking, hostname)]
    |
    +---> [SSH access with key-only auth]
    |         |
    |         +---> [fail2ban SSH protection]
    |
    +---> [Firewall (default-deny)]
    |         |
    |         +---> [nftables backend]
    |         |
    |         +---> [Tailscale firewall integration]
    |
    +---> [User account (dangirsh)]
    |         |
    |         +---> [home-manager]
    |         |         |
    |         |         +---> [Zsh + completions + syntax highlighting]
    |         |         +---> [Tmux configuration]
    |         |         +---> [Atuin shell history]
    |         |         +---> [Starship prompt]
    |         |         +---> [Git + gh config]
    |         |         +---> [CASS indexer user service]
    |         |
    |         +---> [Dev tools (Bun, Rust, Go, Python, etc.)]
    |
    +---> [sops-nix secrets]
              |
              +---> [Tailscale VPN] (needs authkey secret)
              |
              +---> [Restic backups to B2] (needs B2 credentials)
              |         |
              |         +---> [Restic backup monitoring]
              |
              +---> [Docker engine]
              |         |
              |         +---> [Docker networks]
              |         |         |
              |         |         +---> [Docker containers (claw-swap, grok-mcp)]
              |         |
              |         +---> [Ollama service] (independent of Docker but same phase)
              |
              +---> [Syncthing] (needs device keys)
              |
              +---> [Infrastructure repo cloning] (needs SSH keys)
                        |
                        +---> [global-agent-conf symlink]
                                  |
                                  +---> [Claude Code CLI]
```

### Dependency Notes

- **nixos-anywhere requires disko:** The deployment tool uses disko's declarative disk config to partition and format the target
- **sops-nix gates most services:** Tailscale needs an authkey, Restic needs B2 credentials, Docker env files contain secrets, Syncthing needs device identity. Secrets must be set up before services can start
- **Firewall must be configured WITH Tailscale:** If firewall goes up before Tailscale is configured, you may lock yourself out of VPN access. Configure both in the same module/phase
- **home-manager requires user account:** The user must exist before home-manager can manage their environment
- **Docker containers require Docker networks:** The claw-swap stack needs `claw-swap-net` created before containers referencing it can start
- **Repo cloning requires SSH keys:** Activation scripts that clone from GitHub need decrypted SSH keys (from sops-nix) to authenticate
- **CASS indexer requires CASS binary:** Must be installable -- check if it's in nixpkgs or needs a custom derivation

## MVP Definition

### Launch With (v1) -- "It boots and I can work"

Minimum to replace the current Ubuntu server. The server must be functional for daily development work.

- [ ] disko + nixos-anywhere deployment to Contabo -- server boots NixOS
- [ ] SSH access with key-only auth -- can log in remotely
- [ ] Firewall (default-deny) with nftables -- server is not exposed
- [ ] Tailscale VPN connected -- private access works
- [ ] User account + home-manager (Zsh, tmux, Atuin, Starship, Git) -- comfortable shell environment
- [ ] Dev tools installed (Bun, Node, Rust/rustup, Go, Python, fd, rg, jq, Neovim, gh) -- can write code
- [ ] sops-nix secrets configured -- credentials available to services
- [ ] Docker engine running -- container orchestration works
- [ ] Nix garbage collection configured -- disk won't fill up

### Add After Validation (v1.x) -- "All services running"

Services that depend on the base system working. Add once SSH, firewall, and Docker are confirmed working.

- [ ] Docker containers declared (claw-swap stack, grok-mcp) -- when Docker engine is confirmed working
- [ ] Docker networks declared (claw-swap-net) -- when containers are being configured
- [ ] Ollama service with nomic-embed-text -- when system is stable and has spare RAM
- [ ] Syncthing with declarative devices/folders -- when Tailscale networking is confirmed
- [ ] Restic automated backups to B2 -- when sops-nix credentials are verified working
- [ ] fail2ban -- when SSH is confirmed working
- [ ] CASS indexer user service -- when home-manager is stable
- [ ] Infrastructure repos cloned + global-agent-conf symlinked -- when SSH keys are working

### Future Consideration (v2+) -- "Polish and hardening"

Features that improve operations but aren't needed for the migration.

- [ ] Restic backup failure notifications -- after backups run successfully for a week
- [ ] Systemd service hardening (per-service sandboxing) -- after all services are stable
- [ ] Declarative flake.lock update pipeline -- after manual updates work smoothly
- [ ] SSH hardening (cipher restriction, idle timeout) -- after basic SSH is battle-tested
- [ ] Persistent journal with size limits -- after initial debugging period
- [ ] Boot generation limit -- after several rebuilds accumulate
- [ ] Additional host configurations -- if/when adding more machines to the fleet

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| disko + nixos-anywhere | HIGH | MEDIUM | P1 |
| SSH (key-only) | HIGH | LOW | P1 |
| Firewall (default-deny, nftables) | HIGH | LOW | P1 |
| Tailscale VPN | HIGH | LOW | P1 |
| sops-nix secrets | HIGH | MEDIUM | P1 |
| User account + home-manager shell | HIGH | MEDIUM | P1 |
| Dev tools | HIGH | LOW | P1 |
| Docker engine | HIGH | LOW | P1 |
| Nix GC + store optimization | MEDIUM | LOW | P1 |
| Docker containers (claw-swap, grok-mcp) | HIGH | MEDIUM | P2 |
| Docker networks | MEDIUM | LOW | P2 |
| Ollama service | MEDIUM | LOW | P2 |
| Syncthing | MEDIUM | LOW | P2 |
| Restic backups to B2 | HIGH | MEDIUM | P2 |
| fail2ban | MEDIUM | LOW | P2 |
| CASS indexer | MEDIUM | MEDIUM | P2 |
| Repo cloning + agent tooling | MEDIUM | MEDIUM | P2 |
| Backup failure notifications | MEDIUM | MEDIUM | P3 |
| Systemd hardening | MEDIUM | HIGH | P3 |
| Flake.lock update pipeline | LOW | MEDIUM | P3 |
| SSH hardening (advanced) | LOW | LOW | P3 |
| Persistent journal config | LOW | LOW | P3 |
| Boot generation limits | LOW | LOW | P3 |

**Priority key:**
- P1: Must have for launch -- server boots, is accessible, has tools, is secure
- P2: Should have -- all services running and server matches current Ubuntu capabilities
- P3: Nice to have -- operational polish, deeper hardening, automation

## Competitor Feature Analysis

"Competitors" here means alternative approaches to achieving the same server setup.

| Feature | Manual Ubuntu Setup | Ansible Playbook | NixOS Flake (Our Approach) |
|---------|--------------------|--------------------|---------------------------|
| Reproducibility | None -- drift inevitable | Idempotent but not atomic; playbook may partially apply | Full -- `nixos-rebuild` is atomic, rollback trivial |
| Secrets management | .env files, chmod 600 | Ansible Vault (decent) | sops-nix with age -- encrypted in repo, decrypted at activation |
| Firewall | ufw manual setup, easy to forget | Templated iptables rules | Declarative, always applied on rebuild, impossible to forget |
| Service management | systemctl enable/start, manual | Service templates, handlers | Declarative -- services defined in config, started automatically |
| Disaster recovery | Backup scripts, hope for the best | Re-run playbook (if you kept it updated) | `nixos-anywhere` -- one command rebuilds from scratch |
| Docker management | docker-compose files | Ansible docker_container module | `oci-containers` -- containers declared in Nix, managed by systemd |
| Shell/dotfiles | Manual dotfiles, stow, chezmoi | Ansible template/copy | home-manager -- declarative, versioned, reproducible |
| Rollback | Manual package pinning | Git revert + re-run | Boot into previous generation. Literally select from boot menu |
| Time to rebuild | Hours of manual work | 15-30 min playbook run | ~10 min nixos-rebuild (after initial deployment) |

## Sources

- [NixOS Official Wiki -- Security](https://wiki.nixos.org/wiki/Security) -- firewall, hardening overview (HIGH confidence)
- [NixOS Wiki -- Firewall](https://wiki.nixos.org/wiki/Firewall) -- iptables/nftables configuration (HIGH confidence)
- [NixOS Wiki -- Fail2ban](https://wiki.nixos.org/wiki/Fail2ban) -- SSH brute force protection (HIGH confidence)
- [NixOS Wiki -- Tailscale](https://wiki.nixos.org/wiki/Tailscale) -- VPN module configuration (HIGH confidence)
- [NixOS Wiki -- Ollama](https://wiki.nixos.org/wiki/Ollama) -- LLM inference service module (HIGH confidence)
- [NixOS Wiki -- Syncthing](https://wiki.nixos.org/wiki/Syncthing) -- declarative file sync (HIGH confidence)
- [NixOS Wiki -- Restic](https://wiki.nixos.org/wiki/Restic) -- backup module (HIGH confidence)
- [NixOS Wiki -- Storage optimization](https://wiki.nixos.org/wiki/Storage_optimization) -- GC and store optimization (HIGH confidence)
- [NixOS Wiki -- Impermanence](https://wiki.nixos.org/wiki/Impermanence) -- tmpfs root (HIGH confidence, used for anti-feature rationale)
- [NixOS Wiki -- Automatic system upgrades](https://wiki.nixos.org/wiki/Automatic_system_upgrades) -- auto-update caveats (HIGH confidence)
- [NixOS Wiki -- Zsh](https://wiki.nixos.org/wiki/Zsh) -- shell configuration (HIGH confidence)
- [nix-community/nixos-anywhere](https://github.com/nix-community/nixos-anywhere) -- remote deployment tool (HIGH confidence)
- [Mic92/sops-nix](https://github.com/Mic92/sops-nix) -- secrets management (HIGH confidence)
- [Michael Stapelberg -- Secret Management with sops-nix (2025)](https://michael.stapelberg.ch/posts/2025-08-24-secret-management-with-sops-nix/) -- practical sops-nix guide (MEDIUM confidence)
- [Arthur Koziel -- Restic Backups on B2 with NixOS](https://www.arthurkoziel.com/restic-backups-b2-nixos/) -- B2 backup walkthrough (MEDIUM confidence)
- [NixOS Discourse -- Firewall setup](https://discourse.nixos.org/t/firewall-setup-in-nixos/51826) -- community firewall guidance (MEDIUM confidence)
- [NixOS & Flakes Book -- Modularize Configuration](https://nixos-and-flakes.thiscute.world/nixos-with-flakes/modularize-the-configuration) -- flake structure patterns (MEDIUM confidence)
- [Hardening NixOS -- nix-book](https://saylesss88.github.io/nix/hardening_NixOS.html) -- comprehensive hardening guide (MEDIUM confidence)
- [Securing SSH on NixOS](https://ryanseipp.com/posts/nixos-secure-ssh/) -- SSH hardening specifics (MEDIUM confidence)

---
*Feature research for: NixOS declarative server configuration*
*Researched: 2026-02-13*
