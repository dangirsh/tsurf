# Similar Projects to Neurosys: Comprehensive Research Report

**Date:** 2026-02-20
**Scope:** Projects optimizing for deploying dev envs + personal services/projects to a VPS, with a focus on agentic development, ideally NixOS-based

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [The Reference Point: Hyperion-Hub](#the-reference-point-hyperion-hub)
3. [Category 1: NixOS Flake-Based Server Configs](#category-1-nixos-flake-based-server-configs)
4. [Category 2: Agent-First VPS Setup Scripts](#category-2-agent-first-vps-setup-scripts)
5. [Category 3: Agent Sandboxing & Orchestration Platforms](#category-3-agent-sandboxing--orchestration-platforms)
6. [Category 4: Self-Hosted AI Dev Environments](#category-4-self-hosted-ai-dev-environments)
7. [Category 5: NixOS Deployment Tools & Frameworks](#category-5-nixos-deployment-tools--frameworks)
8. [Category 6: NixOS Configuration Frameworks & Libraries](#category-6-nixos-configuration-frameworks--libraries)
9. [Category 7: Notable Community Configs (Reference)](#category-7-notable-community-configs-reference)
10. [Category 8: Non-NixOS Infrastructure Alternatives](#category-8-non-nixos-infrastructure-alternatives)
11. [Comparison Matrix](#comparison-matrix)
12. [Neurosys Positioning Analysis](#neurosys-positioning-analysis)
13. [Recommendations](#recommendations)
14. [Sources](#sources)

---

## Executive Summary

We surveyed **60+ projects** across NixOS server configs, agentic dev infrastructure, agent sandboxing platforms, deployment tools, and personal homelab setups. Key findings:

**Neurosys occupies a unique niche.** No other public project combines NixOS declarative infrastructure with first-class AI agent compute (bubblewrap sandboxing, agent-spawn, llm-agents overlay) on a personal VPS. The closest comparisons are:

| Rank | Project | Why Similar | Key Difference |
|------|---------|-------------|----------------|
| 1 | **Netclode** | Self-hosted remote coding agent server, Tailscale, multiple agent SDKs | Uses k3s + Kata microVMs instead of NixOS + bubblewrap |
| 2 | **ACFS** | Same "bootstrap VPS for multi-agent dev" goal | Imperative Bash on Ubuntu, no NixOS |
| 3 | **barrucadu/nixfiles** | NixOS flake, Prometheus, restic-to-B2 | No agent compute focus |
| 4 | **nix-sandbox-mcp** | Nix + bubblewrap sandboxing for agents | MCP server only, not full server config |
| 5 | **hyperion-hub** | Claude Code on VPS with messaging MCP servers | Imperative Bash, no reproducibility/backups/monitoring |

**The landscape has three camps:**
1. **NixOS declarative configs** (neurosys, barrucadu, ryan4yin, Misterio77) — reproducible, atomic rollbacks, mature ecosystem. None except neurosys prioritize agent compute.
2. **Agent-first VPS scripts** (ACFS, hyperion-hub, claude_code_agent_farm) — fast to set up, no reproducibility, no security hardening. Growing rapidly since Claude Code launched.
3. **Agent sandbox platforms** (E2B, Daytona, Coder, Docker Sandboxes) — enterprise-grade isolation, often cloud-hosted. Self-hosting possible but complex.

**What neurosys does that nobody else does:**
- Declarative NixOS + agent sandboxing + personal services in one flake
- Build-time security assertions (port exposure guards, internalOnlyPorts)
- Tailscale-only SSH with nftables enforcement
- sops-nix encrypted secrets with template rendering
- Automated restic backups to B2 with blanket coverage

**What the ecosystem does that neurosys could adopt:**
- **Impermanence** (Misterio77) — stateless root for stronger reproducibility
- **microvm.nix** (Stapelberg) — full VM isolation for agents instead of bubblewrap
- **selfhostblocks** (ibizaman) — composable service modules with built-in backup/SSO/monitoring
- **srvos** (Numtide) — battle-tested server defaults for base.nix/networking.nix
- **nix-sandbox-mcp** — MCP-based sandboxed execution for agent workflows

---

## The Reference Point: Hyperion-Hub

**Repository:** [github.com/aeschylus/hyperion-hub](https://github.com/aeschylus/hyperion-hub)
**Stars:** 0 | **Created:** 2026-01-23 | **Tech:** Bash on Debian/Ubuntu

Hyperion-hub is a single Bash setup script (~600 lines) that transforms a fresh Debian/Ubuntu server into a "Claude Code hub" with messaging integrations.

### What It Deploys
- Claude Code (native binary via curl)
- Telegram MCP server (Python/Telethon)
- Signal MCP server (signal-cli + signal-mcp)
- Twilio SMS MCP server (Node.js)
- tmux with agent/dev/monitor layouts
- zsh + oh-my-zsh + Powerlevel10k

### Architecture
Everything lives in one `setup.sh`. No modules, no state tracking, no idempotency. Credentials are plain text in `.env.master`. No encryption, no backups, no monitoring, no firewall nuance (UFW allows SSH globally), no rollback capability.

### Comparison to Neurosys
These solve different problems at different layers. Hyperion-hub is a quick-start script for getting Claude Code + messaging running on a fresh Ubuntu box. Neurosys is a fully declarative, reproducible NixOS system with security hardening, encrypted secrets, automated backups, and monitoring. Hyperion-hub is roughly equivalent to what a single `agent-compute.nix` module does in neurosys, minus the security and reproducibility guarantees.

**What hyperion-hub does well:** Low barrier to entry (one command, no Nix knowledge), MCP messaging integrations (Telegram, Signal, Twilio), tmux ergonomics with agent-specific profiles.

---

## Category 1: NixOS Flake-Based Server Configs

### Tier A: Architecturally Closest to Neurosys

#### barrucadu/nixfiles ★173
**URL:** [github.com/barrucadu/nixfiles](https://github.com/barrucadu/nixfiles)
**Similarity:** HIGH — NixOS flake, Prometheus + Grafana + Alertmanager, restic backups to Backblaze B2

The single most architecturally similar project. Uses the exact same monitoring stack (Prometheus) and backup target (restic-to-B2). Multi-host with good documentation. Long-running project.

**Differences:** No agent compute, no Tailscale-only SSH, no security assertions. Multiple hosts vs neurosys's single VPS.

#### truxnell/nix-config ★53
**URL:** [github.com/truxnell/nix-config](https://github.com/truxnell/nix-config)
**Similarity:** HIGH — NixOS flake, sops-nix, restic with sops-managed credentials

Explicitly documents migration from Kubernetes to NixOS. Uses restic with sops-managed AWS/S3 credentials — very similar to neurosys's restic-to-B2 approach. Has a companion documentation website.

**Differences:** No agent compute. K8s migration story. Multiple hosts.

#### MathieuDR/nix-dock ★1
**URL:** [github.com/MathieuDR/nix-dock](https://github.com/MathieuDR/nix-dock)
**Similarity:** HIGH — NixOS flake, single VPS, restic backups, declarative services

Very close single-VPS scope. Uses agenix instead of sops-nix, Caddy reverse proxy. Deploys Glance, Actual, Calibre-web, CommaFeed, ReadDeck.

**Differences:** agenix vs sops-nix. Has reverse proxy (Caddy). No agent compute. Brand new.

### Tier B: Well-Known NixOS Server Configs

#### Misterio77/nix-config ★1,214
**URL:** [github.com/Misterio77/nix-config](https://github.com/Misterio77/nix-config)

The gold standard for stateless NixOS server design. Uses **impermanence** (root wiped on every boot, only explicitly declared state survives). YubiKey-based PGP secrets with sops-nix. Same author as nix-starter-configs (3,579 stars).

**Key innovation:** Opt-in persistence forces truly declarative config and makes disaster recovery trivial.

#### ryan4yin/nix-config ★1,807
**URL:** [github.com/ryan4yin/nix-config](https://github.com/ryan4yin/nix-config)

Author of the "NixOS & Nix Flakes Book" (the de facto community guide). Cross-platform (NixOS + macOS). Homelab servers with K3s. Private secrets repo.

**Key innovation:** Companion educational book. Tagged releases for reference.

#### EmergentMind/nix-config ★592
**URL:** [github.com/EmergentMind/nix-config](https://github.com/EmergentMind/nix-config)

Multi-user, multi-host NixOS with extensive documentation. Uses nixos-anywhere + disko. Separate private `nix-secrets` flake input for clean public/private separation.

**Key innovation:** Private secrets repo as flake input. Comprehensive docs (`docs/anatomy.md`, `docs/addnewhost.md`).

#### Mic92/dotfiles ★727
**URL:** [github.com/Mic92/dotfiles](https://github.com/Mic92/dotfiles)

Personal dotfiles from the creator of sops-nix, disko, and nixos-anywhere. Uses retiolum (Tinc mesh VPN), srvos server profiles, buildbot-nix for CI. A living reference for NixOS infrastructure tooling.

**Key innovation:** Uses srvos for battle-tested server defaults. Retiolum mesh VPN for inter-host connectivity.

#### badele/nix-homelab ★460
**URL:** [github.com/badele/nix-homelab](https://github.com/badele/nix-homelab)

Manages VPS + bare metal + Raspberry Pi from a single flake. Uses **Clan** for deployment instead of traditional tools.

**Key innovation:** Clan deployment tool. Multi-architecture (x86 + ARM).

#### xddxdd/nixos-config (Lan Tian) ★107
**URL:** [github.com/xddxdd/nixos-config](https://github.com/xddxdd/nixos-config)

Multi-server fleet with custom helper library. DNS management via Nix-to-DNSControl compiler. Uses impermanence. Detailed blog series documenting migration.

**Key innovation:** DNS records declared in Nix and compiled to DNSControl. Auto-discovery of hosts from directory structure.

---

## Category 2: Agent-First VPS Setup Scripts

These projects specifically target "get AI coding agents running on a VPS" — the same problem hyperion-hub addresses, at various levels of sophistication.

#### ACFS (Agentic Coding Flywheel Setup) ★~500
**URL:** [github.com/Dicklesworthstone/agentic_coding_flywheel_setup](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup)

Bootstraps a fresh Ubuntu VPS into a complete multi-agent AI development environment in ~30 minutes. Installs Claude Code, Codex CLI, Gemini CLI, session management, safety tools, and coordination infrastructure. Checkpointed installer that resumes on re-run. Companion website (agent-flywheel.com).

**Comparison to neurosys:** Closest in intent — "personal VPS for AI agents." But imperative (Bash), Ubuntu-based, no reproducibility, no secrets encryption, no backups. The "Rails installer" approach vs neurosys's declarative approach.

#### claude_code_agent_farm ★650
**URL:** [github.com/Dicklesworthstone/claude_code_agent_farm](https://github.com/Dicklesworthstone/claude_code_agent_farm)

20+ parallel Claude Code agents with tmux coordination, lock-based conflict prevention, and real-time monitoring dashboard. Same author as ACFS.

**Comparison to neurosys:** Agent orchestration layer only, not infrastructure. Could potentially run on top of neurosys.

#### dmux ★443
**URL:** [github.com/standardagents/dmux](https://github.com/standardagents/dmux)

Agent multiplexer using git worktrees and tmux. Each task gets its own tmux pane + git worktree. Agent-agnostic (Claude, Codex, Gemini).

**Comparison to neurosys:** Complementary tool, not infrastructure. Per-task isolation via git worktrees.

---

## Category 3: Agent Sandboxing & Orchestration Platforms

The agent sandboxing landscape has exploded in the past 6 months. The isolation spectrum runs from **bubblewrap** (lightweight, what neurosys uses) through **gVisor** (kernel interception) to **Firecracker microVMs** (hardware-level, strongest guarantees).

#### E2B ★~8,000
**URL:** [github.com/e2b-dev/E2B](https://github.com/e2b-dev/E2B) | [e2b.dev](https://e2b.dev/)

Open-source secure cloud runtime for AI code execution. Firecracker microVMs, sub-200ms startup, SDKs for Python/JS. Used by ~50% of Fortune 500. **Self-hostable** via Terraform (GCP, AWS coming).

**Relevance:** If neurosys wanted to move from bubblewrap to Firecracker isolation, E2B's self-hosted mode is the most mature option.

#### Daytona ★~5,000
**URL:** [github.com/daytonaio/daytona](https://github.com/daytonaio/daytona)

Pivoted from dev environments to "secure infrastructure for running AI-generated code." Container-based, sub-90ms startup, SDK for programmatic workspace creation. **Self-hostable.**

**Relevance:** API-first agent environment management. Deep integration with OpenHands.

#### Docker Sandboxes
**URL:** [docs.docker.com/ai/sandboxes](https://docs.docker.com/ai/sandboxes)

Official Docker support for AI coding agents in isolated microVMs. Supports Claude Code, Gemini, Codex, Kiro. `docker compose up` for entire agentic stacks. Docker Model Runner for local LLM execution.

**Relevance:** If Docker is already on the system (neurosys has Docker), this provides agent isolation without additional infrastructure.

#### microsandbox ★~3,300
**URL:** [github.com/zerocore-ai/microsandbox](https://github.com/zerocore-ai/microsandbox)

Self-hosted platform using libkrun (library-based KVM). Sub-200ms startup, OCI-compatible, MCP integration. Hardware-level isolation without full VM overhead. **Requires KVM.**

**Relevance:** Would be ideal for neurosys but **Contabo VPS doesn't expose KVM** — not usable without migration.

#### Arrakis
**URL:** [github.com/abshkbh/arrakis](https://github.com/abshkbh/arrakis)

Self-hosted sandboxing with snapshot-and-restore for agent backtracking. Each sandbox runs Ubuntu in a MicroVM with VNC. REST API + Python SDK + MCP server.

**Relevance:** First-class rollback/snapshot support — agents can try, fail, and restore.

#### nix-sandbox-mcp
**URL:** [github.com/SecBear/nix-sandbox-mcp](https://github.com/SecBear/nix-sandbox-mcp)

Sandboxed code execution for LLMs using **Nix + bubblewrap** (same stack as neurosys). Rust daemon, flake-based environments, MCP server. No Docker, no cloud. Token-efficient (~420 tokens).

**Relevance:** Directly comparable isolation approach. Could potentially be integrated into neurosys as an MCP server for agent workflows.

#### Kubernetes agent-sandbox (SIG Apps)
**URL:** [github.com/kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox)

Official Kubernetes CRD for agent sandboxes. gVisor + Kata Containers. Warm pool for sub-second starts. Google-backed.

**Relevance:** The Kubernetes-native approach. Overkill for single VPS but shows where enterprise is heading.

#### microvm.nix ★2,298
**URL:** [github.com/microvm-nix/microvm.nix](https://github.com/microvm-nix/microvm.nix)

NixOS MicroVMs — ephemeral, declarative VMs for sandboxed workloads. Michael Stapelberg's [blog post](https://michael.stapelberg.ch/posts/2026-02-01-coding-agent-microvm-nix/) demonstrates using microvm.nix to create sandboxed coding agent VMs. Each agent gets an ephemeral VM. **Requires KVM.**

**Relevance:** The most sophisticated NixOS-native approach to agent sandboxing. Not usable on Contabo (no KVM) but the gold standard for NixOS + agent isolation.

---

## Category 4: Self-Hosted AI Dev Environments

#### Netclode
**URL:** [github.com/angristan/netclode](https://github.com/angristan/netclode)

Self-hosted remote coding agent built with k3s + Kata Containers + Cloud Hypervisor microVMs + Tailscale. Native iOS app for controlling agents from phone. Multiple agent SDK support (including Claude Agent SDK). Session history with auto-snapshots and rollback.

**Relevance:** The single most directly comparable project to neurosys's agent compute architecture. Same philosophy (personal server for remote coding agents) with different tech choices (k3s vs NixOS, Kata vs bubblewrap).

#### Coder ★~8,000
**URL:** [github.com/coder/coder](https://github.com/coder/coder)

Open-source self-hosted cloud development environments. Terraform-based workspaces, Wireguard tunneling. 50M+ downloads. Governed workspaces specifically for AI coding agents with auditing and observability. Air-gapped deployment supported.

**Relevance:** Enterprise-grade version of neurosys's concept. If agent compute needed to scale to teams, Coder would be the natural upgrade path.

#### DevPod ★~10,000
**URL:** [github.com/loft-sh/devpod](https://github.com/loft-sh/devpod)

Client-only, open-source alternative to GitHub Codespaces. Uses DevContainer standard. No server needed. Creates reproducible dev environments on any backend (Docker, K8s, cloud VMs, SSH machines). 5-10x cheaper than Codespaces.

**Relevance:** Could provision agent workspaces on neurosys without a server component.

#### OpenHands (formerly OpenDevin) ★~40,000
**URL:** [github.com/OpenHands/OpenHands](https://github.com/OpenHands/OpenHands)

Open platform for cloud coding agents. Event-sourced architecture. Full Agent SDK. Docker/Kubernetes deployment. Massive community ($18.8M Series A).

**Relevance:** A full agent platform that could run on neurosys. Complements rather than competes.

#### OpenClaw ★~60,000
**URL:** [github.com/openclaw/openclaw](https://github.com/openclaw/openclaw)

Open-source personal AI assistant that runs 24/7 on your hardware. Multi-channel inbox (WhatsApp, Telegram, Slack, Discord, Signal, iMessage). Browses web, reads/writes files, runs shell commands. Uses Claude API or local models.

**Relevance:** Personal AI assistant running on personal server — same self-hosted philosophy as neurosys. Multi-channel messaging is what hyperion-hub was aiming for.

---

## Category 5: NixOS Deployment Tools & Frameworks

### Deployment Tools Comparison

| Tool | Stars | Type | Multi-host | Secrets | Rollback | Flake Support | Best For |
|------|-------|------|------------|---------|----------|---------------|----------|
| **nixos-rebuild** | built-in | Push | Manual | No | Via generations | Yes | Single host (neurosys) |
| **nixos-anywhere** | ~2,700 | Provision | Yes | --extra-files | N/A | Yes | Initial install |
| **deploy-rs** | ~1,800 | Push | Yes | No | Magic rollback | Yes | Multi-profile deploys |
| **Colmena** | ~2,000 | Push | Parallel | Built-in | No | Yes | Fleet management |
| **NixOps** | ~2,100 | Full lifecycle | Yes | deployment.keys | No | Poor | Legacy, avoid |
| **comin** | ~350 | Pull (GitOps) | Yes | Separate | N/A | Yes | GitOps workflows |
| **Clan** | ~500 | P2P platform | Yes | Built-in | N/A | Yes | Full platform with GUI |
| **Nixinate** | ~280 | Push (flake app) | Yes | No | No | Yes | Minimal wrapper |

**For neurosys (single VPS):** Plain `nixos-rebuild` via `deploy.sh` is the community-standard approach. deploy-rs or Colmena become justified at 3+ machines.

### Secret Management Comparison

| Tool | Stars | Encryption | Templating | Backend | Best For |
|------|-------|-----------|------------|---------|----------|
| **sops-nix** | ~2,600 | age, GPG, KMS | Yes | YAML/JSON/dotenv/INI | Flexibility (neurosys) |
| **agenix** | ~2,200 | age only | No | .age files | Simplicity |
| **ragenix** | ~250 | age only | No | .age files | Better agenix CLI |

**For neurosys:** sops-nix is the right choice — neurosys uses template rendering (`sops.templates`) which agenix doesn't support.

---

## Category 6: NixOS Configuration Frameworks & Libraries

#### srvos ★~900
**URL:** [github.com/nix-community/srvos](https://github.com/nix-community/srvos)

Opinionated, sharable NixOS server profiles maintained by Numtide (same team as llm-agents.nix). Provides `srvos.nixosModules.server` with sane defaults for headless servers. Hardware profiles for Hetzner Cloud, etc. Used by Mic92/dotfiles.

**Relevance:** Could replace/supplement neurosys's hand-written server hardening in `base.nix` and `networking.nix`. Battle-tested defaults.

#### selfhostblocks ★420
**URL:** [github.com/ibizaman/selfhostblocks](https://github.com/ibizaman/selfhostblocks)

Modular self-hosting framework. Service "blocks" compose together — adding backup to any service is one line. Includes LDAP/SSO (Authelia), monitoring (Grafana), reverse proxy, certificate management. All services come with NixOS integration tests.

**Relevance:** If neurosys grows to more services, consuming selfhostblocks modules rather than building from scratch would save significant effort.

#### impermanence ★1,689
**URL:** [github.com/nix-community/impermanence](https://github.com/nix-community/impermanence)

Modules for ephemeral root storage. Root filesystem wiped on boot — only `/boot`, `/nix`, and explicitly opted-in paths survive. Forces fully declarative config. Used by Misterio77, Lan Tian.

**Relevance:** Advanced pattern for stronger reproducibility guarantees. Would complement neurosys's existing restic backup strategy.

#### flake-parts ★~1,000
**URL:** [github.com/hercules-ci/flake-parts](https://github.com/hercules-ci/flake-parts)

Uses NixOS module system to write modular flakes. Eliminates per-system boilerplate. Growing ecosystem. Marginal benefit for single-host configs like neurosys.

#### Snowfall Lib ★602
**URL:** [github.com/snowfallorg/lib](https://github.com/snowfallorg/lib)

Convention-over-configuration framework. Structured directory layout with auto-discovery. Reduces boilerplate but locks you into Snowfall conventions.

---

## Category 7: Notable Community Configs (Reference)

These are widely-cited NixOS configs that serve as architectural references:

| Config | Stars | Notable For |
|--------|-------|------------|
| **Misterio77/nix-starter-configs** | 3,579 | THE canonical NixOS flake starter template |
| **mitchellh/nixos-config** | ~2,900 | HashiCorp co-founder's NixOS-in-VM setup |
| **hlissner/dotfiles** | 1,890 | Doom Emacs author, pioneering flake structure |
| **ryan4yin/nix-config** | 1,807 | NixOS & Flakes Book author |
| **Misterio77/nix-config** | 1,214 | Impermanence + YubiKey sops |
| **fufexan/dotfiles** | 1,054 | flake-parts organization |
| **MatthiasBenaets/nix-config** | 727 | Multi-platform with YouTube tutorials |
| **Mic92/dotfiles** | 727 | sops-nix/disko/nixos-anywhere creator |
| **wimpysworld/nix-config** | ~600 | Former Ubuntu MATE lead, Linux Matters podcast |
| **EmergentMind/nix-config** | 592 | Private secrets repo pattern |
| **srid/nixos-config** | 572 | KISS philosophy, flake-parts |

---

## Category 8: Non-NixOS Infrastructure Alternatives

For completeness — these are the major non-NixOS approaches to the same problem:

| Project | Stars | Tech | Approach |
|---------|-------|------|----------|
| **khuedoan/homelab** | 9,108 | Terraform + Ansible + K3s + ArgoCD | Full Kubernetes GitOps from bare metal |
| **matrix-docker-ansible-deploy** | 6,052 | Ansible + Docker | Single-service (Matrix) on one server |
| **anandslab/docker-traefik** | 3,416 | Docker Compose + Traefik + CrowdSec | Container stack with reverse proxy |
| **n8n self-hosted AI starter** | ~2,000 | Docker Compose + n8n + Ollama | Low-code agent workflows |

These demonstrate valid approaches but lack NixOS's atomic rollbacks, reproducibility, and declarative guarantees.

---

## Comparison Matrix

### Feature Matrix: Neurosys vs Top Similar Projects

| Feature | neurosys | barrucadu | Netclode | ACFS | hyperion-hub | nix-dock |
|---------|----------|-----------|----------|------|-------------|----------|
| **Infrastructure** | NixOS flake | NixOS flake | k3s + Ansible | Bash script | Bash script | NixOS flake |
| **Reproducible** | Yes | Yes | Partially | No | No | Yes |
| **Agent compute** | bubblewrap sandbox | No | Kata microVMs | Multiple CLIs | Claude Code | No |
| **Agent isolation** | bubblewrap | None | microVM | None | None | None |
| **Secrets** | sops-nix (age) | Yes | N/A | .env file | .env.master | agenix |
| **Backups** | restic to B2 | restic to B2 | JuiceFS | None | None | restic |
| **Monitoring** | Prometheus | Prometheus+Grafana | N/A | None | None (htop) | None |
| **SSH access** | Tailscale-only | Standard | Tailscale | Standard | UFW | Standard |
| **Deployment** | deploy.sh | nixos-rebuild | Ansible | bash setup.sh | bash setup.sh | nixos-rebuild |
| **Security assertions** | Build-time | No | N/A | No | No | No |
| **Rollback** | NixOS generations | NixOS generations | Snapshots | None | None | NixOS generations |
| **Multi-host** | No | Yes | No | No | No | No |
| **MCP integrations** | No | No | No | No | Telegram, Signal, SMS | No |
| **Mobile access** | No | No | iOS app | No | No | No |
| **Maturity** | Production | Production | Early | Active | Brand new | New |

### Isolation Spectrum

```
Lightweight ←————————————————————————————→ Strongest

bubblewrap    gVisor    Docker    Kata/Cloud-HV    Firecracker
(neurosys)   (K8s-sig)  (Docker   (Netclode,       (E2B,
              agent-     Sandbox)  microsandbox)     microvm.nix)
              sandbox)
```

Neurosys uses bubblewrap (leftmost) — lightest overhead, good for personal/trusted use. The trend in the industry is toward microVM isolation (rightmost) for production agent workloads.

---

## Neurosys Positioning Analysis

### What Neurosys Does That Nobody Else Does
1. **Declarative NixOS + agent sandbox + personal services** — unified in one flake
2. **Build-time security assertions** — port exposure guards, internalOnlyPorts assertion
3. **Tailscale-only SSH with nftables enforcement** — most configs just allow SSH globally
4. **@decision annotations** for security-relevant architectural choices
5. **Automated deploy pipeline** with locking, container health checks, notifications

### Neurosys's Competitive Advantages
- **Reproducibility**: Any commit can be deployed to recreate the exact system state
- **Atomic rollback**: `nixos-rebuild switch --rollback` instantly reverts
- **Security posture**: Port assertions, Tailscale-only access, sops-encrypted secrets, kernel hardening
- **Backup completeness**: Blanket root backup with exclusions, recovery runbook
- **Agent isolation**: bubblewrap sandbox is lightweight but effective for personal use

### Gaps Relative to the Ecosystem
- **No impermanence** — root is persistent, not wiped on boot
- **No multi-host** — single VPS only
- **No Grafana dashboards** — Prometheus data exists but no visualization
- **No reverse proxy** — relies entirely on Tailscale for service access
- **bubblewrap vs microVM** — lighter isolation than Firecracker/Kata (but Contabo blocks KVM)
- **No MCP messaging integrations** — unlike hyperion-hub's Telegram/Signal/SMS

---

## Recommendations

### High-Value Adoptions (Effort: Low-Medium)

1. **srvos server profiles** — Import `srvos.nixosModules.server` as a flake input. Battle-tested server defaults from Numtide (same team as llm-agents.nix). Supplements `base.nix` and `networking.nix` hardening. Effort: hours.

2. **nix-sandbox-mcp** — Evaluate as an MCP server for agent workflows. Uses the same Nix + bubblewrap approach neurosys already employs. Would give agents declarative, reproducible sandbox environments via MCP. Effort: hours.

3. **Private secrets repo pattern** — Extract `secrets/neurosys.yaml` to a private repo consumed as a flake input. Allows the main config to be fully public. Used by EmergentMind and ryan4yin. Effort: hours.

### Medium-Value Adoptions (Effort: Medium)

4. **selfhostblocks** — Consume as flake input when adding new services. Built-in backup, monitoring, and SSO integration. Most valuable when service count grows. Effort: days per service migration.

5. **Impermanence** — Adopt ephemeral root for stronger reproducibility. Forces explicit declaration of all stateful paths (neurosys's restic backup already tracks most of these). Significant refactoring. Effort: days.

### Future Considerations

6. **microvm.nix for agent isolation** — If neurosys migrates to a KVM-capable host, microvm.nix would provide the strongest agent isolation. Currently blocked by Contabo's lack of nested virtualization.

7. **Colmena/deploy-rs** — When/if neurosys expands to multiple hosts, replace `deploy.sh` with a purpose-built fleet deployment tool.

8. **MCP messaging integrations** — Hyperion-hub's Telegram/Signal/SMS MCP servers could be interesting for agent reach-back. Low priority but unique capability.

---

## Sources

### NixOS Server Configs
- [barrucadu/nixfiles](https://github.com/barrucadu/nixfiles)
- [truxnell/nix-config](https://github.com/truxnell/nix-config)
- [MathieuDR/nix-dock](https://github.com/MathieuDR/nix-dock)
- [Misterio77/nix-config](https://github.com/Misterio77/nix-config)
- [Misterio77/nix-starter-configs](https://github.com/Misterio77/nix-starter-configs)
- [ryan4yin/nix-config](https://github.com/ryan4yin/nix-config)
- [EmergentMind/nix-config](https://github.com/EmergentMind/nix-config)
- [Mic92/dotfiles](https://github.com/Mic92/dotfiles)
- [hlissner/dotfiles](https://github.com/hlissner/dotfiles)
- [fufexan/dotfiles](https://github.com/fufexan/dotfiles)
- [MatthiasBenaets/nix-config](https://github.com/MatthiasBenaets/nix-config)
- [srid/nixos-config](https://github.com/srid/nixos-config)
- [badele/nix-homelab](https://github.com/badele/nix-homelab)
- [xddxdd/nixos-config](https://github.com/xddxdd/nixos-config)
- [Swarsel/.dotfiles](https://github.com/Swarsel/.dotfiles)
- [wimpysworld/nix-config](https://github.com/wimpysworld/nix-config)
- [mitchellh/nixos-config](https://github.com/mitchellh/nixos-config)

### Agent Infrastructure
- [aeschylus/hyperion-hub](https://github.com/aeschylus/hyperion-hub)
- [Dicklesworthstone/agentic_coding_flywheel_setup](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup)
- [Dicklesworthstone/claude_code_agent_farm](https://github.com/Dicklesworthstone/claude_code_agent_farm)
- [standardagents/dmux](https://github.com/standardagents/dmux)
- [angristan/netclode](https://github.com/angristan/netclode)

### Sandboxing Platforms
- [e2b-dev/E2B](https://github.com/e2b-dev/E2B)
- [daytonaio/daytona](https://github.com/daytonaio/daytona)
- [Docker AI Sandboxes](https://docs.docker.com/ai/sandboxes)
- [zerocore-ai/microsandbox](https://github.com/zerocore-ai/microsandbox)
- [abshkbh/arrakis](https://github.com/abshkbh/arrakis)
- [kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox)
- [SecBear/nix-sandbox-mcp](https://github.com/SecBear/nix-sandbox-mcp)
- [microvm-nix/microvm.nix](https://github.com/microvm-nix/microvm.nix)

### Dev Environment Platforms
- [coder/coder](https://github.com/coder/coder)
- [loft-sh/devpod](https://github.com/loft-sh/devpod)
- [OpenHands/OpenHands](https://github.com/OpenHands/OpenHands)
- [openclaw/openclaw](https://github.com/openclaw/openclaw)
- [block/goose](https://github.com/block/goose)
- [Aider-AI/aider](https://github.com/Aider-AI/aider)
- [opencode-ai/opencode](https://github.com/opencode-ai/opencode)
- [cline/cline](https://github.com/cline/cline)

### NixOS Tools
- [nix-community/srvos](https://github.com/nix-community/srvos)
- [ibizaman/selfhostblocks](https://github.com/ibizaman/selfhostblocks)
- [nix-community/impermanence](https://github.com/nix-community/impermanence)
- [hercules-ci/flake-parts](https://github.com/hercules-ci/flake-parts)
- [zhaofengli/colmena](https://github.com/zhaofengli/colmena)
- [serokell/deploy-rs](https://github.com/serokell/deploy-rs)
- [nix-community/nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- [Mic92/sops-nix](https://github.com/Mic92/sops-nix)
- [ryantm/agenix](https://github.com/ryantm/agenix)
- [numtide/llm-agents.nix](https://github.com/numtide/llm-agents.nix)
- [sadjow/claude-code-nix](https://github.com/sadjow/claude-code-nix)

### Non-NixOS Homelab
- [khuedoan/homelab](https://github.com/khuedoan/homelab)
- [anandslab/docker-traefik](https://github.com/anandslab/docker-traefik)
- [spantaleev/matrix-docker-ansible-deploy](https://github.com/spantaleev/matrix-docker-ansible-deploy)
- [n8n-io/self-hosted-ai-starter-kit](https://github.com/n8n-io/self-hosted-ai-starter-kit)

### Reference Lists
- [nix-community/awesome-nix](https://github.com/nix-community/awesome-nix)
- [awesome-selfhosted/awesome-selfhosted](https://github.com/awesome-selfhosted/awesome-selfhosted)
- [mikeroyal/Self-Hosting-Guide](https://github.com/mikeroyal/Self-Hosting-Guide)
- [restyler/awesome-sandbox](https://github.com/restyler/awesome-sandbox)

### Blog Posts & Guides
- [Michael Stapelberg: Coding Agent VMs on NixOS (microvm.nix)](https://michael.stapelberg.ch/posts/2026-02-01-coding-agent-microvm-nix/)
- [Stanislas: Netclode Self-Hosted Cloud Coding Agent](https://stanislas.blog/2026/02/netclode-self-hosted-cloud-coding-agent/)
- [Senko Rasic: Sandboxing AI Agents in Linux](https://blog.senko.net/sandboxing-ai-agents-in-linux)
- [Ranti: Securing AI Agents with Nix and Bubblewrap](https://www.ranti.dev/blog/securing-ai-agents-with-nix-and-bubblewrap)
- [Northflank: How to Sandbox AI Agents in 2026](https://northflank.com/blog/how-to-sandbox-ai-agents)
- [Andrey Markin: Claude Code on VPS Full Setup](https://andrey-markin.com/blog/claude-code-vps-setup)
- [Grigio: Vibe Coding Safely with OpenCode and NixOS](https://grigio.org/vibe-coding-safely-the-ultimate-guide-to-ai-development-with-opencode-and-nixos-via-docker-nixuser/)
- [NixOS Discourse: Best Practice Flake Configs](https://discourse.nixos.org/t/best-practice-flake-nixos-configurations-to-draw-inspiration-from/31926)
- [Guekka: NixOS as a Server (Impermanence)](https://guekka.github.io/nixos-server-1/)
