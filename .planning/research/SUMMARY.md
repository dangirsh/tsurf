# Project Research Summary

**Project:** agent-neurosys
**Domain:** NixOS declarative server configuration (Ubuntu-to-NixOS VPS migration)
**Researched:** 2026-02-13
**Confidence:** HIGH

## Executive Summary

This project replaces a manually configured Ubuntu 25.10 VPS with a fully declarative NixOS flake configuration. The server runs AI agent infrastructure (Ollama, CASS indexer, Claude Code), Docker services (claw-swap stack, grok-mcp), development tools, and automated backups. Experts build this type of configuration using NixOS 25.11 stable with flakes, home-manager as a NixOS module, sops-nix for secrets, disko for declarative disk partitioning, and nixos-anywhere for one-command remote deployment. The ecosystem is mature -- every component has established community patterns with high-confidence documentation.

The recommended approach is a phased migration that starts with a bootable, SSH-accessible base system and incrementally adds services. The critical architectural decision is to keep Docker containers rather than converting them to native NixOS services -- this dramatically reduces migration risk while still gaining NixOS's declarative management through the `oci-containers` module. Secrets management via sops-nix with age encryption (derived from SSH host keys) eliminates the need for separate key infrastructure. The entire configuration lives in a single git repository with encrypted secrets committed alongside code.

The primary risks are: (1) Docker bypassing the NixOS firewall via its own iptables chain -- on a server migrating from zero firewall, this creates a false sense of security; (2) the sops-nix bootstrap chicken-and-egg problem where the host's age key does not exist until first boot but secrets must be encrypted before deployment; (3) Contabo's potentially BIOS-only boot environment despite advertising UEFI, which can render a freshly deployed system unbootable. All three risks have documented mitigations, but they must be addressed in Phase 0/1 before any services are deployed.

## Key Findings

### Recommended Stack

The stack centers on NixOS 25.11 "Xantusia" (stable, supported until June 2026) with Nix 2.33.x and flakes. Four flake inputs compose the system: nixpkgs (pinned to `nixos-25.11`), home-manager (`release-25.11` branch, as NixOS module), sops-nix (secrets via age encryption from SSH host keys), and disko (declarative disk partitioning for nixos-anywhere). All inputs use `inputs.nixpkgs.follows = "nixpkgs"` to deduplicate.

**Core technologies:**
- **NixOS 25.11 + Flakes:** Reproducible, version-pinned system configuration with atomic rollback
- **home-manager (NixOS module):** User environment (Zsh, Git, tmux, Atuin, Starship) deployed atomically with system config
- **sops-nix + age:** Secrets encrypted in-repo, decrypted at activation to `/run/secrets/`; age keys derived from SSH host keys
- **disko + nixos-anywhere:** Declarative disk layout + one-command remote NixOS installation
- **Docker via oci-containers:** Existing containers managed as systemd services through NixOS
- **GRUB (not systemd-boot):** Hybrid BIOS/UEFI support for Contabo VPS compatibility
- **Restic to B2 via S3 API:** Automated backups using NixOS systemd timers; S3 API preferred over native B2

**Critical version requirements:**
- nixpkgs and home-manager branches MUST match (`nixos-25.11` / `release-25.11`)
- Rust via rustup (not fenix/rust-overlay) per project requirement
- Docker (not Podman) for existing compose workflow compatibility

### Expected Features

**Must have (table stakes):**
- disko + nixos-anywhere deployment to Contabo VPS
- SSH key-only auth + default-deny firewall with nftables
- Tailscale VPN with trusted interface
- sops-nix secrets for all service credentials
- User account + home-manager (Zsh, tmux, Atuin, Starship, Git)
- Development tools (Bun, Node.js, Rust/rustup, Go, Python 3, ripgrep, fd, jq, Neovim, gh)
- Docker engine with declarative container management
- Nix garbage collection + store optimization

**Should have (add after base system validated):**
- Docker containers declared (claw-swap stack, grok-mcp) with networks
- Ollama service with nomic-embed-text model
- Syncthing with declarative devices/folders
- Restic automated backups to Backblaze B2
- fail2ban SSH protection
- CASS indexer as user systemd service
- Infrastructure repos cloned + global-agent-conf symlinked

**Defer (v2+):**
- Backup failure notifications
- Per-service systemd hardening (sandboxing)
- Automated flake.lock update pipeline
- Advanced SSH hardening (cipher restriction, idle timeout)
- Impermanence, monitoring stacks, SELinux, auto-upgrades (explicitly rejected as anti-features)

### Architecture Approach

The architecture follows a module-per-concern pattern with a single flake entrypoint. The host config (`hosts/acfs/default.nix`) serves as a thin composition root that imports shared modules. System-level concerns (networking, Docker, services, secrets) live in `modules/`, user-level config in `home/`, and encrypted secrets in `secrets/`. All NixOS modules are lazily evaluated and merged -- the real sequencing occurs at activation time: users/groups first, then sops-nix decryption, then activation scripts, then systemd services.

**Major components:**
1. **flake.nix** -- Entry point: inputs (nixpkgs, home-manager, sops-nix, disko), nixosConfigurations, specialArgs wiring
2. **hosts/acfs/** -- Machine-specific: hardware-configuration.nix, disko-config.nix, host overrides (hostname, timezone)
3. **modules/** -- Reusable system modules: base.nix, boot.nix, networking.nix, users.nix, secrets.nix, docker.nix, services.nix
4. **home/** -- User environment: shell.nix, dev-tools.nix, git.nix, user services (syncthing, cass-indexer)
5. **secrets/** -- sops-encrypted YAML with `.sops.yaml` routing to age keys

### Critical Pitfalls

1. **Docker bypasses NixOS firewall** -- Docker injects its own iptables rules that override NixOS firewall. Mitigation: set `--iptables=false` on Docker daemon, bind container ports to `127.0.0.1`, expose via reverse proxy only. Verify with external `nmap`.

2. **sops-nix age key bootstrap** -- Host SSH key does not exist at deployment time, but secrets must be encrypted for it. Mitigation: pre-generate SSH host key locally, derive age key via `ssh-to-age`, deploy key with nixos-anywhere `--extra-files`.

3. **Contabo BIOS-only boot** -- UEFI may not work despite Contabo advertising it. Mitigation: use GRUB with hybrid BIOS+UEFI disko config (1MB BIOS boot partition + ESP). Test boot mode via VNC before committing.

4. **Missing VirtIO kernel modules** -- initrd may lack virtio_scsi/virtio_blk, causing boot hang. Mitigation: explicitly declare `boot.initrd.availableKernelModules` with all virtio modules. Run `lsmod | grep virtio` on target before deployment.

5. **Firewall + Docker + Tailscale checkReversePath conflict** -- Strict RPF breaks Tailscale routing and Docker networking. Mitigation: set `checkReversePath = "loose"`, trust `tailscale0` and `docker0` interfaces, enable nftables backend.

## Implications for Roadmap

Based on research, the project has clear dependency chains that dictate phase ordering. The critical path is: pre-deployment preparation -> bootable base system -> secrets foundation -> networking layer -> Docker services -> user environment -> hardening.

### Phase 0: Pre-Deployment Preparation
**Rationale:** Several critical steps must happen BEFORE nixos-anywhere runs. The sops-nix bootstrap problem (Pitfall 2) requires pre-generating the host SSH key and deriving the age key. The disko config needs the correct disk device path (sda vs vda) and boot mode (BIOS vs UEFI). Getting these wrong means an unbootable system.
**Delivers:** Pre-generated SSH host key, age public key in `.sops.yaml`, initial encrypted secrets file, verified disk device path and boot mode, flake.nix skeleton with all inputs.
**Addresses:** sops-nix secrets infrastructure, disko disk partitioning, flake structure
**Avoids:** Pitfall 2 (sops bootstrap), Pitfall 3 (BIOS/UEFI), Pitfall 14 (secrets leaking to nix store)

### Phase 1: Bootable Base System
**Rationale:** Nothing else works until the server boots NixOS and is accessible via SSH. This phase must be verified completely (SSH access from both root and user account) before adding complexity. The firewall should be enabled in this phase but AFTER confirming SSH works -- not simultaneously.
**Delivers:** NixOS boots on Contabo, SSH access works, firewall is active, user account exists, Nix GC configured.
**Addresses:** Boot/base system, SSH access, firewall, user account, Nix housekeeping
**Avoids:** Pitfall 4 (missing virtio modules), Pitfall 6 (lockout), Pitfall 12 (hostname), Pitfall 15 (boot loader choice)

### Phase 2: Networking + Secrets + Docker Foundation
**Rationale:** Tailscale, Docker, and the firewall interact in complex ways (Pitfall 1, 5). They must be configured and tested together in a single phase. Secrets must be working before Docker containers can start (they need environment files with credentials). This is the highest-risk phase due to the three-way firewall/Docker/Tailscale interaction.
**Delivers:** Tailscale connected, Docker engine running with `--iptables=false`, sops-nix secrets decrypting successfully, firewall verified from external host.
**Addresses:** Tailscale VPN, Docker engine, sops-nix activation, firewall hardening
**Avoids:** Pitfall 1 (Docker firewall bypass), Pitfall 5 (checkReversePath conflict), Pitfall 11 (Docker subnet conflicts)

### Phase 3: Docker Services + System Services
**Rationale:** With Docker, networking, and secrets all verified, containers can be declared. The claw-swap stack needs a Docker network created before containers start. Ollama and fail2ban are independent services that fit naturally here.
**Delivers:** claw-swap stack running (Caddy + app + PostgreSQL), grok-mcp container, Ollama with nomic-embed-text, fail2ban active.
**Addresses:** Docker containers, Docker networks, Ollama service, fail2ban
**Avoids:** Pitfall 10 (PostgreSQL UID mismatch -- use pg_dump/pg_restore, not file copy)

### Phase 4: User Environment + User Services
**Rationale:** Home-manager configuration is independent of system services. It depends on the user account (Phase 1) and secrets (Phase 2) but not on Docker services. However, placing it after Phase 3 means the system is fully functional before adding user-level polish. Syncthing needs Tailscale (Phase 2) and CASS needs its binary available.
**Delivers:** Full shell environment (Zsh, Starship, Atuin, tmux), Git config, dev tools, Syncthing with declarative folders, CASS indexer, infrastructure repos cloned.
**Addresses:** home-manager, shell config, dev tools, Syncthing, CASS indexer, repo cloning, agent tooling
**Avoids:** Pitfall 7 (activation scripts need network -- use oneshot systemd services instead), Pitfall 8 (HM as NixOS module trade-offs understood)

### Phase 5: Backups + Hardening
**Rationale:** Restic backups are critical but depend on B2 credentials (sops-nix, Phase 2) and a stable system worth backing up. Hardening should come last because it restricts capabilities, which makes debugging harder. Let services stabilize first, then lock them down.
**Delivers:** Automated Restic backups with retention policy, Restic backup monitoring, systemd service hardening, SSH hardening, persistent journal, boot generation limits.
**Addresses:** Restic backups to B2, backup failure notifications, systemd hardening, SSH hardening
**Avoids:** Pitfall 9 (flake.lock drift -- establish update discipline)

### Phase Ordering Rationale

- **Phase 0 before Phase 1** because the sops-nix bootstrap and disko config must be correct before nixos-anywhere runs. Deploying with wrong boot mode or missing age keys means an unbootable or secret-less system.
- **Phase 1 is minimal** (boot + SSH + firewall only) to create a fast feedback loop. Verify access before adding any complexity.
- **Phase 2 groups firewall + Tailscale + Docker** because their interaction is the most complex and dangerous part of the configuration. Testing them in isolation would miss the three-way conflict.
- **Phase 3 before Phase 4** because Docker services are higher value (production web app) than user shell polish. Getting claw-swap.com running again is more urgent than Starship prompts.
- **Phase 5 last** because backups and hardening are safety nets that benefit from a stable system. You cannot meaningfully harden services that are still being debugged.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 0:** sops-nix bootstrap with nixos-anywhere `--extra-files` -- the exact workflow for pre-seeding host keys is documented but nuanced. Research the nixos-anywhere secrets howto guide.
- **Phase 2:** Docker `--iptables=false` combined with nftables and Tailscale -- the three-way interaction is poorly documented as a combined solution. Multiple NixOS issues open. May need iterative testing.
- **Phase 3:** PostgreSQL data migration from old server -- need to verify pg_dump/pg_restore workflow and whether the claw-swap app needs specific PostgreSQL extensions.

Phases with standard patterns (skip research-phase):
- **Phase 1:** Boot, SSH, firewall, user account -- all well-documented NixOS wiki pages with high-confidence patterns.
- **Phase 4:** Home-manager shell/dev tools -- extremely well-documented, hundreds of reference configs available.
- **Phase 5:** Restic backups on NixOS -- standard module with clear documentation and community examples.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All technologies are established NixOS ecosystem tools. Official docs, version compatibility verified, reference flake.nix structure confirmed across multiple sources. |
| Features | HIGH | Feature inventory derived from actual running server audit. Dependency graph well-understood. Priority matrix clear. |
| Architecture | HIGH | Module-per-concern pattern is the community standard. Multiple reference configs confirm structure. flake.nix wiring pattern is boilerplate. |
| Pitfalls | MEDIUM-HIGH | Critical pitfalls (Docker firewall, sops bootstrap, Contabo boot) confirmed by multiple sources. Contabo BIOS-only claim is single-source -- needs verification on target hardware before committing to GRUB-only. |

**Overall confidence:** HIGH

### Gaps to Address

- **Contabo boot mode:** The claim that Contabo is BIOS-only comes from a single community source. Must verify by checking `/sys/firmware/efi` on the target VPS before writing the final disko config. Use hybrid BIOS+UEFI as a hedge.
- **CASS binary availability:** CASS indexer needs to be available as a binary. Unclear if it is in nixpkgs or requires a custom derivation/fetchurl. Investigate during Phase 4 planning.
- **PostgreSQL state:** The current server has both a native PostgreSQL 18 and Docker PostgreSQL 16 containers. Need to determine which databases have active data and what the migration path is for each.
- **dreamy_lehmann container:** Unidentified Docker container running PostgreSQL 16 on port 32941. Must determine its purpose before migration to avoid losing data.
- **Docker `--iptables=false` full implications:** Disabling Docker iptables management means Docker DNS and inter-container networking may break. The exact nftables rules needed to restore connectivity are not fully documented for NixOS. May require trial-and-error during Phase 2.
- **Tailscale auth key type:** Must use a tagged (not regular) auth key to prevent node key expiration. Confirm this is configured in the Tailscale admin console before deployment.

## Sources

### Primary (HIGH confidence)
- [NixOS 25.11 Release Announcement](https://nixos.org/blog/announcements/2025/nixos-2511/) -- Release details, package counts
- [sops-nix GitHub](https://github.com/Mic92/sops-nix) -- Secrets management module
- [disko GitHub](https://github.com/nix-community/disko) -- Declarative disk partitioning
- [nixos-anywhere GitHub](https://github.com/nix-community/nixos-anywhere) -- Remote deployment, `--extra-files` for secrets bootstrap
- [home-manager GitHub](https://github.com/nix-community/home-manager) -- User environment management
- [Michael Stapelberg: Secret Management with sops-nix (2025)](https://michael.stapelberg.ch/posts/2025-08-24-secret-management-with-sops-nix/) -- sops-nix best practices
- [Michael Stapelberg: NixOS Installation Declarative (2025)](https://michael.stapelberg.ch/posts/2025-06-01-nixos-installation-declarative/) -- disko + nixos-anywhere workflow
- [NixOS/nixpkgs#111852](https://github.com/NixOS/nixpkgs/issues/111852) -- Docker iptables firewall bypass
- [NixOS Wiki: Tailscale, Docker, Firewall, Storage optimization](https://wiki.nixos.org/) -- Official NixOS module documentation

### Secondary (MEDIUM confidence)
- [NixOS & Flakes Book](https://nixos-and-flakes.thiscute.world/) -- Modularization patterns, home-manager integration
- [Misterio77/nix-starter-configs](https://github.com/Misterio77/nix-starter-configs) -- Directory structure patterns
- [Arthur Koziel: Restic Backups on B2 with NixOS](https://www.arthurkoziel.com/restic-backups-b2-nixos/) -- Backup walkthrough, S3 API recommendation
- [drawbu/Notes: Install NixOS on Contabo](https://github.com/drawbu/Notes/) -- Contabo-specific hostname and boot quirks
- [Hardening NixOS -- nix-book](https://saylesss88.github.io/nix/hardening_NixOS.html) -- Comprehensive hardening guide

### Tertiary (LOW confidence -- patterns only)
- [NixOS Discourse: How do you structure configs?](https://discourse.nixos.org/t/how-do-you-structure-your-nixos-configs/65851) -- Community patterns survey
- [NixOS is a good server OS, except when it isn't](https://sidhion.com/blog/nixos_server_issues/) -- Server-specific design issues

---
*Research completed: 2026-02-13*
*Ready for roadmap: yes*
