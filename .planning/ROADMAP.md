# Roadmap: agent-neurosys

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
- [x] **Phase 3.1: Parts Integration — Flake Module + Declarative Containers** - Parts exports NixOS module via flake, agent-neurosys imports it, containers via dockerTools, secrets migrated to sops-nix (INSERTED)
- [ ] **Phase 4: Docker Services** - claw-swap stack with security-hardened containers
- [x] **Phase 5: User Environment + Dev Tools** - home-manager shell, dev toolchain, full development experience
- [ ] **Phase 6: User Services + Agent Tooling** - Syncthing, CASS indexer, infrastructure repos cloned and symlinked
- [ ] **Phase 7: Backups** - Automated Restic backups to Backblaze B2
- [ ] **Phase 10: Parts Deployment Pipeline** - Research current deployment, implement agent-neurosys-owned deploy flow where parts defines its own components
- [ ] **Phase 11: Agent Sandboxing** - Default-on bubblewrap (srt) isolation for all coding agents — filesystem deny-by-default, network proxy-filtered, cgroup-limited
- [x] **Phase 8: Review Old Neurosys + Doom.d for Reusable Server Config** - Audit dangirsh/neurosys and dangirsh/.doom.d on GitHub, identify server-relevant config/services worth porting
- [x] **Phase 9: Audit & Simplify** - Deep review of all modules and unexecuted plans, optimize for simplicity, minimalism, and security
- [x] **Phase 13: Research Similar Personal Server Projects** - Survey ecosystem, present 11 ideas, user cherry-picks monitoring/notifications/security adoptions
- [ ] **Phase 14: Monitoring + Notifications** - Prometheus + node_exporter + Grafana dashboards + ntfy push notifications (Tailscale-only)
- [ ] **Phase 15: CrowdSec Intrusion Prevention** - Collaborative threat intelligence with community sharing, complementing fail2ban for public-facing services

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
- [x] 04-02-PLAN.md -- NixOS module (3 hardened containers, network, secrets) + agent-neurosys flake integration

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
| 14. Monitoring + Notifications | 0/TBD | Not started | - |
| 15. CrowdSec Intrusion Prevention | 0/TBD | Not started | - |

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

**Goal:** Understand how parts is currently deployed, then establish a deployment pipeline where agent-neurosys owns the deployment (nixos-rebuild/switch) but the parts repo defines what gets deployed for its own components (containers, services, secrets via its existing NixOS module)
**Depends on:** Phase 3.1 (parts NixOS module exists), Phase 3 (Docker + secrets infrastructure)
**Requirements:** None (operational — bridges existing infrastructure)
**Success Criteria** (what must be TRUE):
  1. Current parts deployment mechanism is fully documented (how it works today, what triggers it, what it deploys)
  2. A deployment command from agent-neurosys builds and switches the NixOS config including parts containers/services
  3. Parts repo defines its own deployable components (containers, networks, secrets) via its `nixosModules.default` — agent-neurosys does not hardcode parts internals
  4. The deployment flow is tested end-to-end: change in parts module → agent-neurosys picks it up → deploy → services running
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
- [ ] TODO(from-research): Enable Tailnet Key Authority (`tailscale lock init` + sign existing nodes)

### Phase 12: Security audit of agent-neurosys NixOS configuration — review all modules for hardening gaps, secret handling, network exposure, sandbox escape vectors, and supply chain risks

**Goal:** [To be planned]
**Depends on:** Phase 11
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 12 to break down)

### Phase 13: Research similar personal server projects (hyperion-hub, etc.) — enumerate good ideas for agent-neurosys: messaging integrations, monitoring patterns, security approaches, agent orchestration

**Goal:** Survey the ecosystem of NixOS homelab and personal server projects, curate a catalog of 11 ideas across 6 categories (monitoring, messaging, security, agent orchestration, backup, reverse proxy), and present findings to the user for cherry-picking — approved ideas become new phases or TODOs in the roadmap
**Depends on:** Phase 12
**Plans:** 1 plan

Plans:
- [x] 13-01-PLAN.md — Present 11 research ideas for user cherry-picking, capture decisions into ROADMAP.md and STATE.md

### Phase 14: Monitoring + Notifications — Prometheus + Grafana + ntfy

**Goal:** Declarative monitoring stack with persistent metrics history, Grafana dashboards (Tailscale-only), and ntfy push notifications for server events (deploy, backup, agent completion, security). Email for non-urgent, Android push for urgent.
**Depends on:** Phase 3 (Tailscale, secrets infrastructure)
**Requirements:** None (new capability from Phase 13 research)
**Success Criteria** (what must be TRUE):
  1. Prometheus scrapes node_exporter metrics (CPU, memory, disk, systemd services) and stores time-series data
  2. Grafana displays system dashboards accessible via Tailscale IP only (not public)
  3. ntfy-sh is running and reachable at localhost for internal notifications, with Android push and email delivery configured
  4. Deploy script, fail2ban, and restic backups send notifications via ntfy on success/failure
  5. `nix flake check` passes with monitoring module added
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 14 to break down)

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
