# Roadmap: neurosys

## Overview

This roadmap delivers a fully declarative NixOS server configuration that replaces a manually configured Ubuntu VPS. The critical path starts with pre-deployment scaffolding (flake structure, sops-nix bootstrap, disko config), then a minimal bootable system, then networking and Docker foundations, then services, then the user development environment, and finally backups. Each phase delivers a verifiable capability -- the server becomes progressively more functional and can be tested at each boundary.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Flake Scaffolding + Pre-Deploy** - Flake skeleton, disko config, sops-nix bootstrap, age key derivation
- [x] **Phase 2: Bootable Base System** - NixOS boots on Contabo, SSH works, firewall active, user exists
- [x] **Phase 2.1: Base System Fixups from Neurosys Review** - Absorbed into Phase 9 (mutableUsers, execWheelOnly applied; settings module dropped as unnecessary; dev tools moved to Phase 5)
- [x] **Phase 3: Networking + Secrets + Docker Foundation** - Tailscale connected, full secrets decryption, Docker engine running
- [x] **Phase 3.1: Parts Integration — Flake Module + Declarative Containers** - Parts exports NixOS module via flake, neurosys imports it, containers via dockerTools, secrets migrated to sops-nix (INSERTED)
- [ ] **Phase 4: Docker Services** - claw-swap stack with security-hardened containers
- [x] **Phase 5: User Environment + Dev Tools** - home-manager shell, dev toolchain, full development experience
- [ ] **Phase 6: User Services + Agent Tooling** - Syncthing, CASS indexer, infrastructure repos cloned and symlinked
- [ ] **Phase 7: Backups** - Automated Restic backups to Backblaze B2
- [ ] **Phase 10: Parts Deployment Pipeline** - Research current deployment, implement neurosys-owned deploy flow where parts defines its own components
- [ ] **Phase 11: Agent Sandboxing** - Default-on bubblewrap (srt) isolation for all coding agents — filesystem deny-by-default, network proxy-filtered, cgroup-limited
- [x] **Phase 8: Review Old Neurosys + Doom.d for Reusable Server Config** - Audit dangirsh/neurosys and dangirsh/.doom.d on GitHub, identify server-relevant config/services worth porting
- [x] **Phase 9: Audit & Simplify** - Deep review of all modules and unexecuted plans, optimize for simplicity, minimalism, and security
- [x] **Phase 13: Research Similar Personal Server Projects** - Survey ecosystem, present 11 ideas, user cherry-picks monitoring/notifications/security adoptions
- [ ] **Phase 14: Monitoring + Notifications** - Prometheus + node_exporter + Grafana dashboards + ntfy push notifications (Tailscale-only)
- [ ] **Phase 15: CrowdSec Intrusion Prevention** - Collaborative threat intelligence with community sharing, complementing fail2ban for public-facing services
- [x] **Phase 17: Hardcore Simplicity & Security Audit** - Critical review of all modules, services, secrets, networking, Docker, firewall, deployment for over-engineering and security gaps. Establish guardrails for future agentic development.
- [ ] **Phase 18: VPS Consolidation** - Merge acfs dev environment into neurosys. Single VPS for dev, personal services, prod. Component audit, security model, self-deploy ergonomics, state tracking, Parts management interface architecture.
- [x] **Phase 19: Generate Comprehensive Project README** - Concise, skimmable README.md enumerating all key features, goals, assumptions, constraints, and preferences. Bullets & tables over prose. Deployment quick-start, operating details, design decisions, accepted risks.
- [ ] **Phase 21: Impermanence (Ephemeral Root)** - Wipe root on every boot via nix-community/impermanence. BTRFS subvolumes + initrd rollback. Explicit /persist state manifest. Drift-proof, smaller backups, simpler DR.
- [ ] **Phase 22: Secret Proxy (Netclode Pattern)** - Two-tier proxy so real API keys never enter agent sandboxes. Header-only injection, per-session allowlisting, reflection prevention.
- [ ] **Phase 23: Tailscale Security & Self-Sovereignty** - TKA (Tailnet Key Authority), ACL hardening, device approval, auth key rotation, node key expiry. Self-custodied signing keys.
- [ ] **Phase 24: Server Hardening + DX** - srvos server profile, sandbox PID+cgroup isolation, devShell, treefmt-nix.
- [x] **Phase 25: Deploy Safety (deploy-rs)** - Magic rollback via inotify canary. Evolve deploy.sh into deploy-rs wrapper.
- [ ] **Phase 26: Agent Notifications (Telegram Bot)** - Telegram Bot API for agent reach-back. 2 sops secrets, outbound HTTPS only. Later: MCP server wrapper.

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
**Plans**: 2 plans

Plans:
- [ ] 02-01-PLAN.md -- Module config hardening (nftables, SSH lockdown, docker group, nix flake check)
- [ ] 02-02-PLAN.md -- nixos-anywhere deployment + post-deploy verification (human-interactive)

### Phase 2.1: Base System Fixups from Neurosys Review (INSERTED)
**Goal**: Absorbed into Phase 9. The settings module was dropped (unnecessary indirection for single-host config). mutableUsers=false and execWheelOnly=true applied in Phase 9 Plan 01. Dev tools and ssh-agent moved to Phase 5.
**Depends on**: Phase 2 (base system must be deployed)
**Requirements**: None (advisory improvements from Phase 8 audit)
**Success Criteria** (what must be TRUE):
  1. [DROPPED] Settings module — unnecessary indirection for single-host config; hardcoded values are fine
  2. [MOVED TO PHASE 5] System packages baseline — minimal system packages (git, curl, wget, rsync, jq, tmux) go into modules/base.nix during Phase 5; dev tools go into home-manager
  3. [SPLIT] `users.mutableUsers = false` and `security.sudo.execWheelOnly = true` applied in Phase 9 Plan 01; `security.sudo.wheelNeedsPassword = false` already set in Phase 2; `programs.ssh.startAgent = true` moved to Phase 5
  4. [COVERED BY 9-01] `nix flake check` passes with security hardening changes
**Plans**: Absorbed into Phase 9 — no separate plans needed

Plans:
- [x] Absorbed into Phase 9 Plan 01 (security hardening) and Phase 5 (dev tools)

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
**Plans**: 2 plans

Plans:
- [x] 03-01-PLAN.md -- Tailscale VPN + sops-nix secrets + fail2ban + firewall hardening
- [x] 03-02-PLAN.md -- Docker engine (--iptables=false) + NixOS NAT + full stack validation

### Phase 3.1: Parts Integration — Flake Module + Declarative Containers (INSERTED)

**Goal:** Parts repo exports a NixOS module (via flake) declaring its containers, networks, and secrets; neurosys imports it as a flake input
**Depends on:** Phase 3 (Docker engine, Tailscale, secrets infrastructure)
**Success Criteria** (what must be TRUE):
  1. Parts repo has a `flake.nix` with `nixosModules.default` that declares its Docker containers (parts-agent, parts-tools), networks (agent_net, tools_net), and sops-nix secrets
  2. Agent-neurosys imports `inputs.parts.nixosModules.default` and `nix flake check` passes for both flakes
  3. Parts Docker images are built via Nix `dockerTools.buildImage` (no external registry, no Dockerfiles)
  4. All parts secrets (Telegram bot token, API keys, OAuth creds) use sops-nix (migrated from agenix) and decrypt at activation
  5. Parts repo has no `nixos-rebuild` in its CI; neurosys handles all NixOS config deployment
**Plans:** 3 plans

Plans:
- [x] 03.1-01-PLAN.md -- Secrets migration (agenix to sops-nix) + parts flake.nix rewrite
- [x] 03.1-02-PLAN.md -- Docker image Nix expressions (parts-agent + parts-tools via dockerTools.buildLayeredImage)
- [x] 03.1-03-PLAN.md -- NixOS module (containers, networks, secrets wiring) + neurosys flake integration

### Phase 4: Docker Services
**Goal**: claw-swap production stack running with security-hardened containers
**Depends on**: Phase 3
**Requirements**: DOCK-02, DOCK-04
**Success Criteria** (what must be TRUE):
  1. claw-swap.com resolves and serves HTTPS traffic through Caddy -> app -> PostgreSQL on the `claw-swap-net` Docker network
  2. Docker network `claw-swap-net` is created before dependent containers start (verified by `docker network ls`)
  3. All containers run with security hardening: `--read-only` rootfs with tmpfs for /tmp, `--cap-drop ALL`, `--security-opt=no-new-privileges`, and resource limits (`--memory`, `--cpus`)

**Note:** Container hardening pattern (from Phase 9 research): use `extraOptions` in oci-containers for read-only, cap-drop, no-new-privileges, resource limits. See 09-RESEARCH.md for implementation details.
**Note:** Ollama and grok-mcp dropped from this phase — no active v1 consumers. Can be added later.

**Plans**: 2 plans

Plans:
- [x] 04-01-PLAN.md -- claw-swap flake setup + sops secrets + Docker image Nix expression
- [x] 04-02-PLAN.md -- NixOS module (3 hardened containers, network, secrets) + neurosys flake integration

### Phase 5: User Environment + Dev Tools
**Goal**: The server provides an agent-optimized compute environment where AI coding agents can be launched and managed via tmux
**Depends on**: Phase 2 (user account must exist)
**Requirements**: HOME-01, HOME-03, DEV-01, DEV-05 (partial) -- superseded requirements: HOME-02 (zsh), HOME-04 (atuin), HOME-05 (starship), DEV-02 (bun/pnpm), DEV-03 (rustup), DEV-04 (go/python)
**Success Criteria** (what must be TRUE -- reframed for agent-first design per CONTEXT.md):
  1. SSH/mosh into server drops user into bash with direnv auto-loading project devShells
  2. Tmux sessions persist across disconnects with mouse mode enabled
  3. `git`, `gh`, `curl`, `wget`, `jq`, `yq`, `rg`, `fd`, `node`, `tmux`, `btop` are all on PATH
  4. `git config user.name` returns "Dan Girshovich" and `GH_TOKEN` env var authenticates gh CLI
  5. `claude` and `codex` CLI commands are available on PATH via llm-agents.nix
  6. `agent-spawn <name> <dir> [claude|codex]` creates an isolated tmux session in a cgroup slice
  7. ANTHROPIC_API_KEY and OPENAI_API_KEY are exported from sops-nix secrets
  8. home-manager is integrated as a NixOS module with bash, tmux, git, ssh, direnv modules

**Plans**: 2 plans

Plans:
- [x] 05-01-PLAN.md -- Home environment + system packages + secrets (bash, tmux, git, ssh, direnv, mosh, system packages, sops secrets)
- [x] 05-02-PLAN.md -- Agent CLIs + compute infrastructure (llm-agents.nix, agent-spawn, cgroup slice, binary cache)
- [ ] TODO(from-research): Add `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=true` env var to agent-spawn
- [ ] TODO(from-research): Add MCP-NixOS server to `.mcp.json` — evaluate, remove if context-polluting

### Phase 6: User Services + Agent Tooling
**Goal**: The AI agent development infrastructure is operational with file sync, code indexing, and config repos in place
**Depends on**: Phase 3 (Tailscale for Syncthing), Phase 5 (home-manager for CASS user service)
**Requirements**: SVC-02, SVC-03, AGENT-01, AGENT-02
**Success Criteria** (what must be TRUE):
  1. Syncthing web UI is accessible and configured with declarative devices and folders, syncing with at least one peer
  2. CASS indexer is running as a user-level systemd service (`systemctl --user status cass-indexer` shows active)
  3. `/data/projects/global-agent-conf` exists and `~/.claude` is a symlink pointing to it
  4. `/data/projects/parts` and `/data/projects/claw-swap` repos are cloned and present
**Plans**: 2 plans

Plans:
- [x] 06-01-PLAN.md -- Syncthing declarative NixOS module (4 devices, 1 Sync folder, staggered versioning, Tailscale-only GUI)
- [x] 06-02-PLAN.md -- CASS binary + timer, repo cloning activation scripts, agent config symlinks (~/.claude, ~/.codex)

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
Phases execute in numeric order: 1 -> 2 -> 3 -> 3.1 -> 9 -> 4 -> 5 -> 6 -> 7
(Phase 2.1 absorbed into Phase 9; Phase 8 already complete. Phase 3.1 must complete before Phase 4. Phases 4, 5, 6, 7 can partially overlap. Phase 9 is a quality gate — applies security hardening and streamlines future plans.)

| Phase | Plans Complete | Status | Completed |
|-------|---------------|--------|-----------|
| 1. Flake Scaffolding + Pre-Deploy | 2/2 | ✓ Complete | 2026-02-13 |
| 2. Bootable Base System | 2/2 | ✓ Complete | 2026-02-15 |
| 2.1 Base System Fixups (INSERTED) | N/A | Absorbed into Phase 9 | 2026-02-15 |
| 3. Networking + Secrets + Docker Foundation | 2/2 | ✓ Complete | 2026-02-15 |
| 3.1 Parts Integration (INSERTED) | 3/3 | ✓ Complete | 2026-02-15 |
| 4. Docker Services | 2/2 | ✓ Complete | 2026-02-16 |
| 5. User Environment + Dev Tools | 2/2 | ✓ Complete | 2026-02-16 |
| 6. User Services + Agent Tooling | 2/2 | ✓ Complete | 2026-02-16 |
| 7. Backups | 0/TBD | Not started | - |
| 8. Review Old Neurosys + Doom.d | 1/1 | ✓ Complete | 2026-02-15 |
| 9. Audit & Simplify | 2/2 | ✓ Complete | 2026-02-15 |
| 10. Parts Deployment Pipeline | 2/2 | ✓ Complete | 2026-02-17 |
| 11. Agent Sandboxing (bubblewrap/srt) | 2/2 | ✓ Complete | 2026-02-17 |
| 12. Security Audit | 0/TBD | Not started | - |
| 13. Research Similar Projects | 1/1 | ✓ Complete | 2026-02-18 |
| 14. Monitoring + Notifications | 2/2 | ✓ Complete | 2026-02-18 |
| 15. CrowdSec Intrusion Prevention | 0/TBD | Not started | - |
| 16. Disaster Recovery & Backup Completeness | 2/2 | ✓ Complete | 2026-02-19 |
| 17. Hardcore Simplicity & Security Audit | 4/4 | ✓ Complete | 2026-02-19 |
| 18. VPS Consolidation | 0/TBD | Not started | - |
| 19. Generate Project README | 1/1 | ✓ Complete | 2026-02-20 |
| 20. Deep Ecosystem Research | 1/1 | ✓ Complete | 2026-02-20 |
| 21. Impermanence (Ephemeral Root) | 1/2 | In progress | - |
| 22. Secret Proxy (Netclode Pattern) | 0/TBD | Not started | - |
| 23. Tailscale Security & Self-Sovereignty | 1/2 | In progress | - |
| 24. Server Hardening + DX | 0/1 | Not started | - |
| 25. Deploy Safety (deploy-rs) | 1/1 | ✓ Complete | 2026-02-21 |
| 26. Agent Notifications (Telegram Bot) | 0/TBD | Not started | - |

### Phase 8: Review Old Neurosys + Doom.d for Reusable Server Config
**Goal**: Audit dangirsh/neurosys and dangirsh/.doom.d on GitHub for server-relevant configurations, services, and patterns worth porting into neurosys. Filter out anything laptop/Mac/Emacs-specific — only keep what's useful for a remote NixOS server managing personal services, agents, and projects. Present candidates to user for cherry-picking.
**Depends on**: Nothing (research phase, can run anytime)
**Requirements**: None (advisory — informs other phases)
**Success Criteria** (what must be TRUE):
  1. Both repos (dangirsh/neurosys, dangirsh/.doom.d) have been reviewed and a summary of server-relevant findings is presented
  2. Each candidate config/service includes: what it does, where it lived in the old repo, and which neurosys phase/module it would slot into
  3. User has approved or rejected each candidate — approved items are captured as TODOs or folded into existing phase plans
**Plans**: 1 plan

Plans:
- [x] 08-01-PLAN.md -- Present candidates for user cherry-picking, capture decisions in ROADMAP.md and SUMMARY.md

### Phase 9: Audit & Simplify — Implementation Review + Plan Optimization

**Goal:** Deep review of all committed NixOS modules (flake.nix, modules/, secrets, .sops.yaml) and all unexecuted phase plans (2, 2.1, 4, 5, 6, 7). Optimize the entire repo for simplicity, minimalism, and security — remove unnecessary complexity, tighten security defaults, simplify module structure, and streamline future plans.
**Depends on:** Phase 3 (reviews all work through Phase 3 + 3.1)
**Requirements**: None (quality gate — improves existing work and plans)
**Success Criteria** (what must be TRUE):
  1. Every committed module has been reviewed for unnecessary complexity, and simplifications are applied or documented
  2. Security posture reviewed: no overly permissive defaults, secrets handling is minimal and correct, firewall rules are tight
  3. Unexecuted phase plans (2, 2.1, 4, 5, 6, 7) are reviewed and revised for minimalism — scope creep removed, plans streamlined
  4. `nix flake check` passes after any implementation changes
**Plans:** 2 plans

Plans:
- [x] 09-01-PLAN.md -- Security hardening + dead code removal (SSH-to-Tailscale-only, root SSH elimination, mutableUsers, execWheelOnly, example_secret cleanup)
- [x] 09-02-PLAN.md -- Roadmap revision (absorb Phase 2.1, update Phase 4/5 goals, tighten unexecuted phase plans)

### Phase 10: Parts Deployment Pipeline — Research + Implementation

**Goal:** Understand how parts is currently deployed, then establish a deployment pipeline where neurosys owns the deployment (nixos-rebuild/switch) but the parts repo defines what gets deployed for its own components (containers, services, secrets via its existing NixOS module)
**Depends on:** Phase 3.1 (parts NixOS module exists), Phase 3 (Docker + secrets infrastructure)
**Requirements:** None (operational — bridges existing infrastructure)
**Success Criteria** (what must be TRUE):
  1. Current parts deployment mechanism is fully documented (how it works today, what triggers it, what it deploys)
  2. A deployment command from neurosys builds and switches the NixOS config including parts containers/services
  3. Parts repo defines its own deployable components (containers, networks, secrets) via its `nixosModules.default` — neurosys does not hardcode parts internals
  4. The deployment flow is tested end-to-end: change in parts module → neurosys picks it up → deploy → services running
  5. Deployment is documented with a clear runbook (what to run, from where, expected output)
**Plans:** 2 plans

Plans:
- [ ] 10-01-PLAN.md -- Flake input change (path: to github:) + deploy script (scripts/deploy.sh) with both modes and health verification
- [ ] 10-02-PLAN.md -- End-to-end deploy verification + user sign-off (checkpoint)

### Phase 11: Agent Sandboxing — Default-on bubblewrap (srt) isolation for all coding agents

**Goal:** Every coding agent spawned on acfs runs inside a bubblewrap sandbox by default — filesystem deny-by-default (project workspace writable, sibling projects read-only, secrets/SSH invisible), rootless Podman for Docker workflows, unrestricted network, PID-limited. Prompt injection of a YOLO-mode agent cannot read secrets, escalate via Docker, or move laterally.
**Depends on:** Phase 5 (agent-spawn exists), Phase 3 (secrets infrastructure to protect)
**Requirements:** None (security hardening — new capability)
**Success Criteria** (what must be TRUE):
  1. `agent-spawn <name> <dir>` wraps every agent session in a bubblewrap sandbox with `--unshare-all` (PID, net, mount, user namespaces)
  2. Sandboxed agents can see `/nix/store` (read-only) and their project workspace (read-write) — nothing else (no `~/.ssh`, no `/run/secrets`, no other projects)
  3. Network isolation via `--unshare-net` + proxy: agents can reach allowlisted domains (npm, pip, GitHub, Anthropic API) but cannot make arbitrary outbound connections
  4. Per-agent cgroup limits enforced via systemd slices (memory cap, CPU quota, PID limit)
  5. `agent-spawn --no-sandbox` exists as explicit opt-out but is not the default
  6. 100 concurrent sandboxed agents run comfortably within VPS resources (96 GB RAM, 18 vCPU)
  7. Existing agent workflows (Claude Code, Codex CLI) work identically inside the sandbox — no DX regression
**Research:** Evaluated Daytona, E2B, Firecracker, gVisor, nsjail, Docker, systemd-nspawn, DevContainers. bubblewrap (via Anthropic's open-source srt) selected for: zero overhead (~4KB/sandbox), proven by Claude Code's own sandbox mode, NixOS-native, direct host bind-mounts, proxy-based network filtering.
**Plans:** 2 plans

Plans:
- [ ] 11-01-PLAN.md -- Rewrite agent-spawn with bwrap sandbox, Podman NixOS config, metadata IP block, subUid/subGid ranges
- [ ] 11-02-PLAN.md -- Deploy to VPS, iterative testing of all sandbox behaviors, user verification checkpoint
- [x] TODO(from-research): Enable Tailnet Key Authority — moved to Phase 23 (Tailscale Security & Self-Sovereignty)

### Phase 12: Security audit of neurosys NixOS configuration — review all modules for hardening gaps, secret handling, network exposure, sandbox escape vectors, and supply chain risks

**Goal:** [To be planned]
**Depends on:** Phase 11
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 12 to break down)

### Phase 13: Research similar personal server projects (hyperion-hub, etc.) — enumerate good ideas for neurosys: messaging integrations, monitoring patterns, security approaches, agent orchestration

**Goal:** Survey the ecosystem of NixOS homelab and personal server projects, curate a catalog of 11 ideas across 6 categories (monitoring, messaging, security, agent orchestration, backup, reverse proxy), and present findings to the user for cherry-picking — approved ideas become new phases or TODOs in the roadmap
**Depends on:** Phase 12
**Plans:** 1 plan

Plans:
- [x] 13-01-PLAN.md — Present 11 research ideas for user cherry-picking, capture decisions into ROADMAP.md and STATE.md

### Phase 14: Monitoring + Notifications — Prometheus + Grafana + ntfy

**Goal:** Declarative monitoring stack with persistent metrics history, Grafana dashboards (Tailscale-only), and ntfy push notifications for server events (deploy, agent completion, security). Email for non-urgent, Android push for urgent. Backup notifications (restic -> ntfy) deferred to Phase 7 when backups are implemented.
**Depends on:** Phase 3 (Tailscale, secrets infrastructure)
**Requirements:** None (new capability from Phase 13 research)
**Success Criteria** (what must be TRUE):
  1. Prometheus scrapes node_exporter metrics (CPU, memory, disk, systemd services) and stores time-series data
  2. Grafana displays system dashboards accessible via Tailscale IP only (not public)
  3. ntfy-sh is running and reachable at localhost for internal notifications, with write-only default access (Tailscale-only, safe)
  4. Deploy script and fail2ban send notifications via ntfy on success/failure; a generic notify.sh helper exists for agent completion and future backup hooks (Phase 7)
  5. `nix flake check` passes with monitoring module added
**Plans:** 2 plans

Plans:
- [x] 14-01-PLAN.md -- Core monitoring + notification modules (Prometheus, node_exporter, Alertmanager, alertmanager-ntfy, ntfy-sh, Grafana, sops secrets, fail2ban ntfy action)
- [x] 14-02-PLAN.md -- Deploy script ntfy integration + generic notify.sh helper + final validation (nix flake check)

### Phase 15: CrowdSec Intrusion Prevention — Collaborative threat intelligence

**Goal:** CrowdSec analyzes logs for attack patterns and shares threat intelligence with the community. Complements existing fail2ban for public-facing services (claw-swap). Community sharing enabled (user approved).
**Depends on:** Phase 12 (security audit), Phase 14 (ntfy for CrowdSec alerts)
**Requirements:** None (security hardening from Phase 13 research)
**Success Criteria** (what must be TRUE):
  1. CrowdSec agent is running and analyzing SSH + web access logs
  2. Community blocklists are active and CrowdSec shares anonymized attack signals back
  3. CrowdSec bouncer blocks IPs from community blocklists at firewall level
  4. CrowdSec alerts route to ntfy for notification
  5. `nix flake check` passes with CrowdSec module added
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 15 to break down)

### Phase 16: Disaster Recovery & Backup Completeness

**Goal:** Catastrophic VPS loss recovers in < few hours from `neurosys` git state + Backblaze B2 backup. Audit all stateful paths, add missing ones to restic (Tailscale state, SSH host keys, claw-swap DB, parts state, ESPHome configs, Prometheus metrics). Document exactly what's restorable from backups vs what needs manual re-auth/setup. Create and test a recovery runbook: `nixos-anywhere` + `restic restore` + minimal manual steps = fully working server.
**Depends on:** Phase 7 (restic backups operational)
**Requirements:** None (operational resilience)
**Success Criteria** (what must be TRUE):
  1. All critical stateful paths are backed up to B2 (audit complete, no gaps)
  2. Recovery runbook exists documenting exact steps: nixos-anywhere deploy → restic restore → manual re-auth list
  3. Manual re-auth list is minimal and documented (Tailscale re-auth, any API keys that are node-specific)
  4. Recovery has been tested (at minimum: dry-run restore of a snapshot, verify file integrity)
  5. SSH host keys are backed up so sops-nix age key derivation works on restore
  6. Total estimated recovery time is documented and under 2 hours
**Plans:** 2 plans

Plans:
- [x] 16-01-PLAN.md -- Close backup gaps (SSH host keys, Docker bind mounts, Tailscale state, pg_dump hook) + deploy + dry-run restore verification
- [x] 16-02-PLAN.md -- Disaster recovery runbook (docs/recovery-runbook.md)

### Phase 17: Hardcore Simplicity & Security Audit

**Goal:** Meticulous, critical review of the entire NixOS infrastructure — every module, service, secret, network rule, Docker config, firewall rule, and deployment script — through two lenses: (1) simplicity (YAGNI violations, over-engineering, unnecessary abstraction, dead code, premature generalization) and (2) security (hardening gaps, attack surface, secret exposure, privilege escalation, network exposure, supply chain risks). This infrastructure is the foundation for a digital life managed by agent swarms — it must be rock solid. Beyond fixing existing issues, establish repo-level guardrails (CLAUDE.md conventions, hooks, linting rules) that keep simplicity and security standards high as agents autonomously develop on this codebase.
**Depends on:** Nothing (independent audit — can run anytime, but benefits from all current work being complete)
**Requirements:** None (quality gate)
**Success Criteria** (what must be TRUE):
  1. Every Nix module has been reviewed line-by-line for unnecessary complexity, dead code, unused options, and over-abstraction — findings documented with concrete fixes
  2. Every network-facing service has been audited for minimum-privilege: bind addresses, firewall rules, authentication, TLS — no unnecessary exposure
  3. All sops-nix secrets reviewed: no unused secrets, no secrets with overly broad access, no secrets that could be eliminated
  4. Docker containers audited for security hardening: read-only rootfs, cap-drop, no-new-privileges, resource limits, network isolation
  5. Deployment scripts reviewed for security: no credential leaks, proper error handling, no TOCTOU races
  6. Agent sandbox (bubblewrap) escape vectors assessed — can a compromised agent reach secrets, other projects, or the host?
  7. Supply chain review: flake inputs pinned, no unnecessary inputs, lock file hygiene
  8. CLAUDE.md and repo conventions updated with explicit simplicity and security guardrails for future agentic development
  9. All actionable findings implemented (not just documented) — `nix flake check` passes after changes
**Plans:** 4 plans

Plans:
- [x] 17-01-PLAN.md — Simplicity cleanup + kernel hardening (remove dead code, duplicate packages, unused features, stale keys; add sysctl hardening, fix llm-agents supply chain)
- [x] 17-02-PLAN.md — SSH hardening + credential leak fix (remove port 22 from public firewall, fix token leak in repo cloning, exclude .git/config from backups)
- [x] 17-03-PLAN.md — CLAUDE.md guardrails (update project structure, add security conventions, simplicity conventions, module change checklist)
- [x] 17-04-PLAN.md — Docker container hardening audit + agent sandbox escape vector assessment (SEC3 audit with BEADS entries, SEC5/SEC6 confirmation, audit log tamper protection)

### Phase 18: VPS Consolidation — Merge acfs Dev Environment into neurosys

**Goal:** Consolidate from two VPSes (acfs dev + neurosys prod) into a single neurosys VPS that serves as the one-stop shop: development environment, personal services (Parts), production services (claw-swap), monitoring, backups, and agent infrastructure. The acfs VPS can then be decommissioned entirely. This phase requires deep research and planning across five dimensions:

1. **Component Gap Audit** — Enumerate every component on acfs not yet in neurosys (AgentBox/Tetragon, GitHub Actions runner, PostgreSQL 18, codex-monitor-daemon, agent-mail, custom scripts, 33+ project dirs, plaintext API keys). For each: migrate, drop, or defer.
2. **Security — Co-located Dev + Prod** — Analyze implications of prompt-injectable dev agents sharing a host with production services (claw-swap public traffic, Parts with Telegram/API access). Cover: sandbox blast radius, Docker network isolation, secrets boundaries, nixos-rebuild cross-contamination, resource contention.
3. **Dev Ergonomics — Self-Deploying NixOS** — When the single VPS runs nixos-rebuild on itself: SSH session survival, tmux/zmx persistence, Docker container restart behavior, active agent session continuity, deploy script self-execution safety. Design safe self-deployment patterns with staging builds, atomic switches, and rollback.
4. **State Tracking — Nothing Left Behind** — Audit all state against the constraint: "If it's not in git, Syncthing, or B2, it doesn't survive a rebuild." Cross-reference Phase 16 (Disaster Recovery). Cover: /data/projects/ git status, database state, Docker volumes, Syncthing sync state, sops-nix vs manual secrets, home directory dotfiles.
5. **Parts as Agent-Neurosys Management Interface** — Design architecture for Parts to become the primary interface for managing the entire system (configure Syncthing, redeploy services, read Prometheus, manage dev agents, view logs). ALL destructive/irreversible/sensitive operations MUST go through an explicit human approval gate that a compromised Parts agent cannot bypass. Likely requires a custom CLI/MCP with discrete typed operations, audit logging, and read-only auto-approve vs write-requires-confirmation split. Implementation may be a follow-up phase, but the consolidation design MUST NOT paint into a corner.

**Depends on:** Phase 16 (Disaster Recovery — ensures backups cover all state before consolidation), Phase 17 (Hardcore Simplicity — clean foundation to consolidate onto)
**Requirements:** None (architectural migration)
**Success Criteria** (what must be TRUE):
  1. Complete inventory of acfs components with migrate/drop/defer decisions for each
  2. Security model documented for co-located dev+prod with concrete isolation boundaries
  3. Self-deployment workflow designed and tested (nixos-rebuild on self, session survival, rollback)
  4. State audit complete — every important artifact tracked in git, Syncthing, or B2
  5. Parts management interface architecture designed (CLI/MCP spec, approval gate design, capability model)
  6. Migration runbook: exact steps to go from two VPSes to one, with rollback plan
  7. acfs VPS can be decommissioned with confidence that nothing is lost
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 18 to break down)

### Phase 19: Generate Comprehensive Project README

**Goal:** Create a concise, skimmable README.md that enumerates all key features, goals, assumptions, constraints, and preferences — gleaned from `.planning/` docs and the actual implementation. Prefer bullets and tables over long prose. Include: project overview, architecture summary, all services/modules, security model, deployment quick-start for first-timers, key operating details (deploy, backup, monitoring, secrets management), design decisions table, and accepted risks. Target audience: someone who needs to understand and operate this system quickly.
**Depends on:** Nothing (documentation — can run anytime)
**Requirements:** None (documentation)
**Success Criteria** (what must be TRUE):
  1. README.md exists at repo root with complete, accurate content covering all modules and services
  2. First-time deployer can follow the quick-start section to deploy the system
  3. Key operating details (deploy, backup, monitoring, secrets) are documented with concrete commands
  4. Design decisions and accepted risks are enumerated in table format
  5. Content is skimmable — bullets, tables, and headers over prose paragraphs
**Plans:** 1 plan

Plans:
- [x] 19-01-PLAN.md — Write and validate comprehensive README.md (all modules, services, security, deployment, operations, decisions, risks)

### Phase 20: Deep Ecosystem Research — What to Adopt for Neurosys

**Goal:** Comprehensive research across the NixOS ecosystem to identify tools, patterns, libraries, and configurations that neurosys should adopt. 10 parallel research agents deep-dive into: Netclode (secret proxy), nix-sandbox-mcp (bubblewrap patterns), microvm.nix (agent VMs), impermanence (ephemeral root), srvos + selfhostblocks (server hardening), Mic92 + EmergentMind configs (reference patterns), MCP messaging + OpenClaw (agent reach-back), deployment tools (deploy-rs/Colmena/comin/Clan), multi-node scaling, and E2B + Docker sandboxes (VM sandboxing platforms).
**Depends on:** Nothing (research phase)
**Requirements:** None (research — informs future phases)
**Success Criteria** (what must be TRUE):
  1. All 10 research dimensions covered with concrete findings
  2. Each finding includes: what it is, why it matters for neurosys, integration effort, and recommendation (adopt/defer/skip)
  3. Actionable adoption roadmap with immediate, short-term, medium-term, and long-term categories
  4. Key decisions documented with rationale
**Plans:** 1 plan

Plans:
- [x] 20-01-SUMMARY.md — Synthesize 10 parallel agent reports into unified adoption report

### Phase 21: Impermanence (Ephemeral Root)

**Goal:** Wipe root filesystem on every boot via [nix-community/impermanence](https://github.com/nix-community/impermanence). Only explicitly declared paths survive via bind-mounts from `/persist`. BTRFS subvolumes + initrd rollback to blank snapshot (not tmpfs — server workloads need disk-backed root). Drift-proof state, explicit state manifest, smaller backups (`/persist` instead of `/`), simpler disaster recovery. From ecosystem research item 6.
**Depends on:** Phase 16 (disaster recovery — must have solid backups before disk reprovisioning)
**Requirements:** None (architectural improvement)
**Success Criteria** (what must be TRUE):
  1. Root filesystem is wiped on every boot via BTRFS subvolume rollback to blank snapshot in initrd
  2. `/persist` subvolume holds all stateful paths: `/etc/ssh`, `/var/lib/tailscale`, `/var/lib/docker`, sops age key, etc.
  3. `environment.persistence."/persist"` declares every stateful path — nothing survives reboot unless explicitly listed
  4. sops-nix age key re-pointed to `/persist/etc/ssh/ssh_host_ed25519_key`
  5. Restic backup path updated from `/` to `/persist` (smaller, more focused backups)
  6. Recovery runbook updated for impermanence (restore `/persist` from restic, reboot, done)
  7. Disk reprovisioning via nixos-anywhere redeploy tested successfully
  8. All services survive a reboot with ephemeral root (Docker, Tailscale, sops secrets, Syncthing, Home Assistant, Prometheus)
**Effort:** High — requires disk reprovisioning (nixos-anywhere redeploy). Test in VM first.
**Plans:** 2 plans

Plans:
- [x] 21-01-PLAN.md -- NixOS config changes: BTRFS disko, impermanence module, initrd rollback, restic path migration, recovery runbook
- [ ] 21-02-PLAN.md -- Migration execution: backup verification, nixos-anywhere redeploy, state restoration, service verification (human checkpoint)

### Phase 22: Secret Proxy (Netclode Pattern)

**Goal:** Two-tier proxy where real API keys never enter agent sandboxes. Inspired by [Netclode](https://github.com/nichochar/netclode) and [Fly's Tokenizer](https://github.com/superfly/tokenizer). Agents see placeholder keys + HTTP_PROXY; the secret-proxy (outside sandbox) validates agent identity, replaces placeholders in HTTP headers only (not body — prevents reflection attacks), and forwards to upstream APIs. Per-session SDK-type allowlisting (Claude → anthropic.com only). From ecosystem research item 7.
**Depends on:** Phase 11 (agent sandboxing — proxy integrates with sandbox HTTP_PROXY)
**Requirements:** None (security hardening — new capability)
**Success Criteria** (what must be TRUE):
  1. Secret proxy service runs outside agent sandboxes, listening on localhost
  2. Agents receive `ANTHROPIC_API_KEY=PLACEHOLDER` and `HTTP_PROXY=localhost:<port>` — real keys never enter sandbox
  3. Proxy performs header-only token injection (prevents reflection/exfiltration of real keys via response body)
  4. Per-session allowlisting: Claude agents can only reach anthropic.com, Codex agents only openai.com
  5. Validation failure blocks the request entirely (placeholder never leaks to upstream)
  6. Agent identity validated before token injection (session ID or sandbox identity)
  7. Real API keys sourced from sops-nix secrets, read only by the proxy service
  8. Existing agent workflows (Claude Code, Codex CLI) work transparently through the proxy
**Effort:** Medium — small Go/Rust proxy service + NixOS module + agent-spawn integration.
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 22 to break down)

### Phase 23: Tailscale Security and Self-Sovereignty

**Goal:** Harden Tailscale configuration for maximum security and self-sovereignty. Enable Tailnet Key Authority (TKA) so Tailscale coordination server compromise cannot inject rogue nodes — signing keys are self-custodied. Audit and tighten ACLs (device-level, user-level, tag-based). Review auth key rotation, device approval policies, MagicDNS configuration, and exit node settings. Ensure neurosys owns its identity chain end-to-end. Previously adopted in Phase 13 research (TKA quick task) but never executed; Headscale was rejected since TKA covers the key sovereignty concern.
**Depends on:** Phase 3 (Tailscale operational)
**Requirements:** None (security hardening)
**Success Criteria** (what must be TRUE):
  1. Tailnet Key Authority enabled (`tailscale lock init`) — all existing nodes signed
  2. New nodes cannot join the tailnet without explicit TKA signing (coordination server compromise cannot inject rogue nodes)
  3. ACLs reviewed and tightened: principle of least privilege for each device/service (neurosys, laptops, phones)
  4. New devices cannot join without cryptographic TKA signing (TKA replaces device approval — they are mutually exclusive)
  5. Auth key rotation policy documented and implemented (no long-lived pre-auth keys)
  6. MagicDNS configuration reviewed for information leakage
  7. Tailscale node key expiry policy configured (force periodic re-authentication)
  8. SSH via Tailscale verified hardened (no fallback to public IP possible)
  9. `nix flake check` passes with any Tailscale module changes
**Effort:** Low-Medium — mostly operational (CLI commands + ACL policy), small NixOS config changes.
**Plans:** 2 plans

Plans:
- [x] 23-01-PLAN.md -- Restore port 22 firewall hardening + TKA operational runbook in recovery docs
- [ ] 23-02-PLAN.md -- Execute TKA initialization + ACL hardening + verification (human checkpoints)

### Phase 24: Server Hardening and DX

**Goal:** Adopt srvos server profile for ~40 battle-tested hardening defaults (watchdog, OOM priority, auto-GC, LLMNR off, emergency mode off, etc.). Add `--unshare-pid` and `--unshare-cgroup` to agent-spawn bubblewrap flags so agents can't see host processes or cgroup hierarchy. Improve DX: devShell with sops+age+deploy tooling, treefmt-nix (nixfmt + shellcheck). gVisor, flake check toplevel, and systemd initrd are explicitly out of scope (deferred per CONTEXT.md).
**Depends on:** Nothing (independent hardening -- can run anytime)
**Requirements:** None (hardening + DX improvements)
**Success Criteria** (what must be TRUE):
  1. srvos flake input added and `srvos.nixosModules.server` imported -- redundant manual settings removed
  2. `networking.useNetworkd` overridden to `false` with `mkForce` (Contabo static IP uses scripted networking)
  3. `--unshare-pid` and `--unshare-cgroup` added to agent-spawn bwrap flags -- agents can't see host `/proc` or cgroups
  4. DevShell includes sops, age, deploy-rs CLI, nixfmt, shellcheck
  5. treefmt-nix configured with nixfmt + shellcheck
  6. `nix flake check` passes with all changes
**Effort:** Low-Medium -- srvos is the bulk, rest are small additions.
**Plans:** 1 plan

Plans:
- [ ] 24-01-PLAN.md -- srvos adoption + host overrides, devShell + treefmt-nix, sandbox PID+cgroup isolation

### Phase 25: Deploy Safety with deploy-rs

**Goal:** Add [deploy-rs](https://github.com/serokell/deploy-rs) magic rollback alongside existing deploy.sh. For a Tailscale-only server, a misconfigured firewall or networking change locks you out permanently. deploy-rs auto-rolls back via inotify canary if the deployer can't SSH back within the confirmation timeout. Evolve deploy.sh into a wrapper: `nix flake update parts && deploy .#neurosys --confirm-timeout 120 && <container health check>`. From ecosystem research item 5.
**Depends on:** Phase 10 (existing deploy pipeline)
**Requirements:** None (deployment safety)
**Success Criteria** (what must be TRUE):
  1. deploy-rs added as flake input with `deploy.nodes.neurosys` configuration
  2. Magic rollback works: intentionally break networking config → deploy → rollback fires within timeout → server recovers
  3. deploy.sh evolved into wrapper that calls `deploy .#neurosys` with confirmation timeout
  4. Container health check still runs after successful deploy
  5. `nix flake check` passes (deploy-rs includes its own flake checks)
  6. Rollback behavior documented in deploy runbook
**Effort:** Low — 15 lines flake config + deploy.sh wrapper evolution.
**Plans:** 1 plan

Plans:
- [x] 25-01-PLAN.md -- deploy-rs flake integration + deploy.sh wrapper evolution + recovery runbook update

### Phase 26: Agent Notifications via Telegram Bot

**Goal:** Minimal Telegram Bot API integration so agents can notify the operator. Currently no agent reach-back mechanism — agents can't proactively notify when done, stuck, or need approval. Uses Bot API (not Telethon user API) for simplicity and no account suspension risk. Outbound HTTPS only, no inbound ports. 2 sops secrets: `telegram-bot-token`, `telegram-chat-id`. Later: wrap as MCP server for bidirectional agent-operator messaging. From ecosystem research item 4.
**Depends on:** Phase 3 (sops-nix secrets infrastructure)
**Requirements:** None (new capability)
**Success Criteria** (what must be TRUE):
  1. `notify-telegram` script available on PATH via `pkgs.writeShellApplication`
  2. `notify-telegram "test message"` sends message to configured Telegram chat
  3. 2 sops secrets added: `telegram-bot-token`, `telegram-chat-id` — decrypted at activation
  4. agent-spawn integration: agents can call `notify-telegram` from inside sandbox (outbound HTTPS)
  5. Deploy script sends Telegram notification on success/failure (alongside existing notification mechanisms)
  6. No inbound ports opened — outbound HTTPS only
  7. `nix flake check` passes with notification module
**Effort:** Low — writeShellApplication + 2 sops secrets + agent-spawn PATH.
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 26 to break down)
