# Roadmap: agent-neurosys

## Overview

This roadmap delivers a fully declarative NixOS server configuration that replaces a manually configured Ubuntu VPS. The critical path starts with pre-deployment scaffolding (flake structure, sops-nix bootstrap, disko config), then a minimal bootable system, then networking and Docker foundations, then services, then the user development environment, and finally backups. Each phase delivers a verifiable capability -- the server becomes progressively more functional and can be tested at each boundary.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Flake Scaffolding + Pre-Deploy** - Flake skeleton, disko config, sops-nix bootstrap, age key derivation
- [ ] **Phase 2: Bootable Base System** - NixOS boots on Contabo, SSH works, firewall active, user exists
- [ ] **Phase 2.1: Base System Fixups from Neurosys Review** - Settings module, system packages, SSH hardening (INSERTED)
- [ ] **Phase 3: Networking + Secrets + Docker Foundation** - Tailscale connected, full secrets decryption, Docker engine running
- [ ] **Phase 3.1: Parts Integration — Flake Module + Declarative Containers** - Parts exports NixOS module via flake, agent-neurosys imports it, containers via dockerTools, secrets migrated to sops-nix (INSERTED)
- [ ] **Phase 4: Docker Services + Ollama** - claw-swap stack, grok-mcp container, Ollama service running
- [ ] **Phase 5: User Environment + Dev Tools** - home-manager shell, dev toolchain, full development experience
- [ ] **Phase 6: User Services + Agent Tooling** - Syncthing, CASS indexer, infrastructure repos cloned and symlinked
- [ ] **Phase 7: Backups** - Automated Restic backups to Backblaze B2
- [ ] **Phase 8: Review Old Neurosys + Doom.d for Reusable Server Config** - Audit dangirsh/neurosys and dangirsh/.doom.d on GitHub, identify server-relevant config/services worth porting

## Phase Details

### Phase 1: Flake Scaffolding + Pre-Deploy
**Goal**: All configuration scaffolding exists so nixos-anywhere can deploy a working system on first try
**Depends on**: Nothing (first phase)
**Requirements**: BOOT-02, BOOT-04, SEC-01, SEC-02
**Success Criteria** (what must be TRUE):
  1. `nix flake check` passes on the flake with all inputs (nixpkgs, home-manager, sops-nix, disko) pinned in flake.lock
  2. disko config defines EFI + root partition layout targeting the correct Contabo disk device
  3. GRUB boot loader is configured for hybrid BIOS/UEFI compatibility in the NixOS config
  4. Age public key derived from a pre-generated SSH host key is present in `.sops.yaml`, and at least one encrypted secrets file exists and can be decrypted locally
**Plans**: 2 plans

Plans:
- [ ] 01-01-PLAN.md -- NixOS flake configuration skeleton (flake.nix, host configs, modules, disko, boot, nix flake check)
- [ ] 01-02-PLAN.md -- sops-nix secrets bootstrap (SSH host key, age keys, .sops.yaml, encrypted secrets, local decryption)

### Phase 2: Bootable Base System
**Goal**: NixOS boots on the Contabo VPS and is accessible via SSH with a secure firewall
**Depends on**: Phase 1
**Requirements**: BOOT-01, BOOT-03, BOOT-05, BOOT-06, NET-01, NET-02, NET-04, SYS-01, SYS-02
**Success Criteria** (what must be TRUE):
  1. `nixos-anywhere` deploys the configuration to the Contabo VPS in a single command, and the server boots into NixOS
  2. User `dangirsh` can SSH into the server with key-only authentication (password auth rejected, root login rejected)
  3. Firewall is active with default-deny policy; only ports 22, 80, 443, and 22000 are open on the public interface (verified by external port scan)
  4. Hostname is `acfs`, timezone is `Europe/Berlin`, and Nix garbage collection is scheduled
**Plans**: TBD

Plans:
- [ ] 02-01: TBD

### Phase 2.1: Base System Fixups from Neurosys Review (INSERTED)
**Goal**: Apply settings, packages, and SSH hardening improvements identified in Phase 8 neurosys review
**Depends on**: Phase 2 (base system must be deployed)
**Requirements**: None (advisory improvements from Phase 8 audit)
**Success Criteria** (what must be TRUE):
  1. `modules/settings.nix` exists with `config.settings.{name,username,email}` options; all other modules reference `config.settings.*` instead of hardcoded strings
  2. `environment.systemPackages` includes agent-focused baseline (curl, wget, ripgrep, fd, jq, yq-go, tmux, git, shellcheck, sd, and others)
  3. `users.mutableUsers = false` is set, `security.sudo.wheelNeedsPassword = false`, `security.sudo.execWheelOnly = true`, and `programs.ssh.startAgent = true`
  4. `nix flake check` passes with all new modules
**Plans**: TBD

Plans:
- [ ] 02.1-01: TBD
  - [ ] TODO(from-neurosys): Settings module — centralized `config.settings.*` for name/username/email → new `modules/settings.nix`
  - [ ] TODO(from-neurosys): System packages baseline (agent-focused: curl, wget, zip/unzip, tree, rsync, ripgrep, fd, jq, yq-go, killall, lsof, tmux, git, file, shellcheck, sd) → `modules/base.nix`
  - [ ] TODO(from-neurosys): SSH hardening — `users.mutableUsers = false`, `security.sudo.wheelNeedsPassword = false`, `security.sudo.execWheelOnly = true`, `programs.ssh.startAgent = true` → `modules/users.nix`

### Phase 3: Networking + Secrets + Docker Foundation
**Goal**: Tailscale VPN, full secrets management, and Docker engine work together without firewall conflicts
**Depends on**: Phase 2
**Requirements**: NET-03, NET-05, NET-06, SEC-03, DOCK-01
**Success Criteria** (what must be TRUE):
  1. Tailscale is connected to the tailnet and the server is reachable via its Tailscale IP from another tailnet device
  2. All sops-nix secrets (Tailscale authkey, B2 credentials, Docker env files, SSH keys) decrypt successfully to `/run/secrets/` at activation time
  3. Docker engine is running with `--iptables=false` and containers can communicate on internal networks without bypassing the NixOS firewall (verified by external port scan showing no unexpected open ports)
  4. fail2ban is active and banning IPs after failed SSH attempts
  5. Tailscale routing works with reverse path filtering set to "loose" (no dropped packets on tailscale0 interface)
**Plans**: TBD

Plans:
- [ ] 03-01: TBD

### Phase 3.1: Parts Integration — Flake Module + Declarative Containers (INSERTED)

**Goal:** Parts repo exports a NixOS module (via flake) declaring its containers, networks, and secrets; agent-neurosys imports it as a flake input
**Depends on:** Phase 3 (Docker engine, Tailscale, secrets infrastructure)
**Success Criteria** (what must be TRUE):
  1. Parts repo has a `flake.nix` with `nixosModules.default` that declares its Docker containers (parts-agent, parts-tools), networks (agent_net, tools_net), and sops-nix secrets
  2. Agent-neurosys imports `inputs.parts.nixosModules.default` and `nix flake check` passes for both flakes
  3. Parts Docker images are built via Nix `dockerTools.buildImage` (no external registry, no Dockerfiles)
  4. All parts secrets (Telegram bot token, API keys, OAuth creds) use sops-nix (migrated from agenix) and decrypt at activation
  5. Parts repo has no `nixos-rebuild` in its CI; agent-neurosys handles all NixOS config deployment
**Plans:** 3 plans

Plans:
- [x] 03.1-01-PLAN.md -- Secrets migration (agenix to sops-nix) + parts flake.nix rewrite
- [x] 03.1-02-PLAN.md -- Docker image Nix expressions (parts-agent + parts-tools via dockerTools.buildLayeredImage)
- [x] 03.1-03-PLAN.md -- NixOS module (containers, networks, secrets wiring) + agent-neurosys flake integration

### Phase 4: Docker Services + Ollama
**Goal**: Production web services and AI inference are running and accessible
**Depends on**: Phase 3
**Requirements**: DOCK-02, DOCK-03, DOCK-04, SVC-01
**Success Criteria** (what must be TRUE):
  1. claw-swap.com resolves and serves HTTPS traffic through Caddy -> app -> PostgreSQL on the `claw-swap-net` Docker network
  2. grok-mcp container is running and responding on port 9601
  3. Ollama service is running and `ollama list` shows the server is responsive (models downloaded manually post-deploy)
  4. Docker network `claw-swap-net` is created before dependent containers start (verified by `docker network ls`)
**Plans**: TBD

Plans:
- [ ] 04-01: TBD

### Phase 5: User Environment + Dev Tools
**Goal**: The server provides a complete, comfortable development experience for daily use
**Depends on**: Phase 2 (user account must exist)
**Requirements**: HOME-01, HOME-02, HOME-03, HOME-04, HOME-05, DEV-01, DEV-02, DEV-03, DEV-04, DEV-05
**Success Criteria** (what must be TRUE):
  1. SSH into server drops user into Zsh with Starship prompt, syntax highlighting, autosuggestions, and completions working
  2. Tmux sessions persist across SSH disconnects and Atuin shell history is available and syncing
  3. `git`, `gh`, `bun`, `node`, `pnpm`, `go`, `python3`, `rustup`, `nvim`, `fd`, `rg`, `jq`, and `git-lfs` are all available on PATH and functional
  4. `git config user.name` returns "Dan Girshovich" and `gh auth status` confirms GitHub CLI is authenticated
  5. home-manager is integrated as a NixOS module and `home-manager generations` shows the active generation
**Plans**: TBD

Plans:
- [ ] 05-01: TBD
  - [ ] TODO(from-neurosys): SSH client config — controlMaster, controlPersist, serverAliveInterval, hashKnownHosts → new `home/ssh.nix`
  - [ ] TODO(from-neurosys): Direnv with nix-direnv for cached evaluations (minimize cd latency) → `home/direnv.nix`

### Phase 6: User Services + Agent Tooling
**Goal**: The AI agent development infrastructure is operational with file sync, code indexing, and config repos in place
**Depends on**: Phase 3 (Tailscale for Syncthing), Phase 5 (home-manager for CASS user service)
**Requirements**: SVC-02, SVC-03, AGENT-01, AGENT-02
**Success Criteria** (what must be TRUE):
  1. Syncthing web UI is accessible and configured with declarative devices and folders, syncing with at least one peer
  2. CASS indexer is running as a user-level systemd service (`systemctl --user status cass-indexer` shows active)
  3. `/data/projects/global-agent-conf` exists and `~/.claude` is a symlink pointing to it
  4. `/data/projects/parts` and `/data/projects/claw-swap` repos are cloned and present
**Plans**: TBD

Plans:
- [ ] 06-01: TBD
  - [ ] TODO(from-neurosys): Syncthing declarative config pattern — receive-only mode, versioning, rescan intervals, 4 device IDs declared in Nix (fresh params, not ported) → `modules/syncthing.nix`

### Phase 7: Backups
**Goal**: Critical server data is automatically backed up off-site with a defined retention policy
**Depends on**: Phase 3 (B2 credentials via sops-nix)
**Requirements**: BACK-01
**Success Criteria** (what must be TRUE):
  1. Restic backup runs successfully to Backblaze B2 via S3 API (verified by `restic snapshots` showing at least one snapshot)
  2. Automated daily backup timer is active (`systemctl status restic-backups-*.timer` shows enabled and scheduled)
  3. Retention policy is configured (7 daily, 5 weekly, 12 monthly) and `restic forget --dry-run` confirms policy
**Plans**: TBD

Plans:
- [ ] 07-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 2.1 -> 3 -> 3.1 -> 4 -> 5 -> 6 -> 7 -> 8
(Phase 2.1 applies fixups from Phase 8 review. Phase 3.1 must complete before Phase 4. Phases 4, 5, 6, 7 can partially overlap. Phase 8 is a research/audit phase — findings feed back into earlier phases via TODOs.)

| Phase | Plans Complete | Status | Completed |
|-------|---------------|--------|-----------|
| 1. Flake Scaffolding + Pre-Deploy | 0/2 | Planned | - |
| 2. Bootable Base System | 0/TBD | Not started | - |
| 2.1 Base System Fixups (INSERTED) | 0/TBD | Not started | - |
| 3. Networking + Secrets + Docker Foundation | 0/TBD | Not started | - |
| 3.1 Parts Integration (INSERTED) | 3/3 | ✓ Complete | 2026-02-15 |
| 4. Docker Services + Ollama | 0/TBD | Not started | - |
| 5. User Environment + Dev Tools | 0/TBD | Not started | - |
| 6. User Services + Agent Tooling | 0/TBD | Not started | - |
| 7. Backups | 0/TBD | Not started | - |
| 8. Review Old Neurosys + Doom.d | 1/1 | ✓ Complete | 2026-02-15 |

### Phase 8: Review Old Neurosys + Doom.d for Reusable Server Config
**Goal**: Audit dangirsh/neurosys and dangirsh/.doom.d on GitHub for server-relevant configurations, services, and patterns worth porting into agent-neurosys. Filter out anything laptop/Mac/Emacs-specific — only keep what's useful for a remote NixOS server managing personal services, agents, and projects. Present candidates to user for cherry-picking.
**Depends on**: Nothing (research phase, can run anytime)
**Requirements**: None (advisory — informs other phases)
**Success Criteria** (what must be TRUE):
  1. Both repos (dangirsh/neurosys, dangirsh/.doom.d) have been reviewed and a summary of server-relevant findings is presented
  2. Each candidate config/service includes: what it does, where it lived in the old repo, and which agent-neurosys phase/module it would slot into
  3. User has approved or rejected each candidate — approved items are captured as TODOs or folded into existing phase plans
**Plans**: 1 plan

Plans:
- [x] 08-01-PLAN.md -- Present candidates for user cherry-picking, capture decisions in ROADMAP.md and SUMMARY.md
