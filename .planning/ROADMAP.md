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
- [x] **Phase 4: Docker Services** - claw-swap stack with security-hardened containers
- [x] **Phase 5: User Environment + Dev Tools** - home-manager shell, dev toolchain, full development experience
- [x] **Phase 6: User Services + Agent Tooling** - Syncthing, CASS indexer, infrastructure repos cloned and symlinked
- [x] **Phase 7: Backups** - Automated Restic backups to Backblaze B2
- [x] **Phase 10: Parts Deployment Pipeline** - Research current deployment, implement neurosys-owned deploy flow where parts defines its own components
- [x] **Phase 11: Agent Sandboxing** - Default-on bubblewrap (srt) isolation for all coding agents — filesystem deny-by-default, network proxy-filtered, cgroup-limited
- [x] **Phase 8: Review Old Neurosys + Doom.d for Reusable Server Config** - Audit dangirsh/neurosys and dangirsh/.doom.d on GitHub, identify server-relevant config/services worth porting
- [x] **Phase 9: Audit & Simplify** - Deep review of all modules and unexecuted plans, optimize for simplicity, minimalism, and security
- [x] **Phase 13: Research Similar Personal Server Projects** - Survey ecosystem, present 11 ideas, user cherry-picks monitoring/notifications/security adoptions
- [x] **Phase 14: Monitoring + Notifications** - ARCHIVED -- monitoring removed in Phase 54 (Prometheus/node_exporter/alerts removed as unused complexity)
- [x] **Phase 15: CrowdSec Intrusion Prevention** - ARCHIVED -- fail2ban via srvos is sufficient; CrowdSec deferred indefinitely
- [x] **Phase 17: Hardcore Simplicity & Security Audit** - Critical review of all modules, services, secrets, networking, Docker, firewall, deployment for over-engineering and security gaps. Establish guardrails for future agentic development.
- [x] **Phase 18: VPS Consolidation** - ARCHIVED -- consolidation completed organically; both VPS hosts managed by unified flake
- [x] **Phase 19: Generate Comprehensive Project README** - Concise, skimmable README.md enumerating all key features, goals, assumptions, constraints, and preferences. Bullets & tables over prose. Deployment quick-start, operating details, design decisions, accepted risks.
- [x] **Phase 21: Impermanence (Ephemeral Root)** - Wipe root on every boot via nix-community/impermanence. BTRFS subvolumes + initrd rollback. Explicit /persist state manifest. Drift-proof, smaller backups, simpler DR.
- [x] **Phase 22: Secret Proxy (Netclode Pattern)** - Two-tier proxy so real API keys never enter agent sandboxes. Header-only injection, per-session allowlisting, reflection prevention.
- [x] **Phase 23: Tailscale Security & Self-Sovereignty** - ARCHIVED -- Tailscale ACLs managed in Tailscale admin; TKA deferred indefinitely
- [x] **Phase 24: Server Hardening + DX** - srvos server profile, sandbox PID+cgroup isolation, devShell, treefmt-nix.
- [x] **Phase 25: Deploy Safety (deploy-rs)** - Magic rollback via inotify canary. Evolve deploy.sh into deploy-rs wrapper.
- [x] **Phase 26: Agent Notifications (Telegram Bot)** - ARCHIVED -- agent notifications handled via Parts Telegram bot
- [ ] **Phase 27: OVH VPS Production Migration** - Deploy neurosys to new OVH VPS as production server. Multi-host NixOS config, nixos-anywhere deployment, Tailscale setup, deploy script updates, Contabo repurposed as staging.
- [x] **Phase 28: dangirsh.org Static Site on Neurosys** - Move dangirsh.org from NearlyFreeSpeech to OVH host. Hakyll site as Nix flake package. nginx unified reverse proxy (replaces Docker Caddy). ACME TLS. DNS cutover.
- [x] **Phase 29: Agentic Dev Maxing — Batteries Included** - opencode, gemini-cli, pi (Mario Zechner) installed + sandbox-integrated. GOOGLE_API_KEY, XAI_API_KEY, OPENROUTER_API_KEY secrets added. Secret proxy extended to new providers. Session search + Rust beads CLI for agents.
- [x] **Phase 30: Claw-Swap Native NixOS Service** - Replace Docker containers with native services.postgresql + systemd service. Unix socket trust auth. Docker stays for parts only.
- [x] **Phase 31: Conway Automaton — Single Agent MVP** - Deploy 1 sovereign AI agent on Conway Cloud with seed hypothesis #1 (x402 APIs). ~$250 USDC, Sonnet 4.6 primary model, BYOK keys. Terminal monitoring dashboard on neurosys.
- [x] **Phase 32: Self-Hosted Conway Automaton on Neurosys** - Run Conway Automaton framework as NixOS systemd service on neurosys, eliminating Conway Cloud compute costs for agent runtime. BYOK inference via secret proxy. State persisted locally.
- [x] **Phase 37: Open Source Prep** - Privacy audit, public/private repo split, lean README. Remove personal identifiers; extract personal config to private flake overlay; publish infrastructure patterns.
- [x] **Phase 44: Android CO2 Alert** - Push notification to Pixel 10 Pro when Apollo AIR-1 CO2 exceeds 1000 ppm. HA automation in home-assistant-config, cooldown to prevent spam, recovery notification when CO2 returns to normal.
- [x] **Phase 45: Neurosys MCP Server** - ARCHIVED -- MCP removed in Phase 54 (didn't work with Claude Android)
- [x] **Phase 47: Comprehensive Security Review** - Detailed security audit of both public and private neurosys components. Network attack surface hardening, intrusion blast radius containment, systemd service isolation, secrets boundary verification, Docker/container escape paths, Tailscale ACL audit, agent sandbox breakout analysis.
- [x] **Phase 49: Security Hardening Follow-up** - Fix HIGH priority issues from Phase 47 audit: remove hardcoded passwords from bootstrap scripts, complete internalOnlyPorts coverage, verify Matrix registration, pin Docker image digests.
- [x] **Phase 50: Coherence & Simplicity Audit** - Holistic review of public + private neurosys for architectural coherence, threat model consistency, over-engineering, code smells, surprising non-standard decisions, feature conflicts, and design inconsistencies. Prioritized findings report + fixes.
- [x] **Phase 52: Nativize the Lobster Farm — Docker-Free Contabo** - Replace remaining Docker containers (OpenClaw x6, Spacebot) with native NixOS systemd services. buildNpmPackage for OpenClaw, Nix package for Spacebot. Zero data loss (preserve /var/lib state dirs). Same ports, same secrets injection (sops env files), same nginx/homepage integration. Goal: eliminate Docker daemon dependency on Contabo entirely. Activation-time data migration with rollback safety.
- [ ] **Phase 53: Conway Dashboard Auth + Prompt Editor** - Token-based auth for public internet access (bearer token via sops-nix + nginx HTTPS). UI to edit genesis prompt and restart automaton agent without NixOS rebuild.
- [x] **Phase 55: Evaluate absurd Durable Execution** - Research-only. All 5 components REJECT or DEFER. No adoption warranted. Conway Automaton DEFER pending upstream plugin support or permanent fork.
- [x] **Phase 56: Voice Interface Research — Low-Latency Parts Assistant** - Research and compare approaches (Claude Android voice+MCP baseline, ClawdTalk/Telnyx PSTN, WebRTC-native with LiveKit/Daily/Vapi) for a Parts-aware voice assistant on Android + Mac. Produce recommendation + Phase 57 implementation plan.
- [ ] **Phase 57: OVH Re-bootstrap as neurosys-dev** - Fresh Ubuntu 25 on OVH VPS. nixos-anywhere install, hostname neurosys-dev, dev agent workloads only (services stay on Contabo). Verify SSH, bootstrap, Tailscale, agent tooling.
- [x] **Phase 58: Agent Canvas — Generic Visualization Service** - Agent-driven visualization canvas on port 8083. Agents push Vega-Lite charts and markdown panels via REST API. Persistent panels, real-time SSE, GridStack.js layout. Single NixOS module (canvas.nix) with writePython3Bin stdlib-only server. Tailscale-only. Completed 2026-03-04.
- [x] **Phase 59: Logseq PKM Agent Suite** - Three read-only Logseq org-mode MCP tools (`logseq_get_todos`, `logseq_search_pages`, `logseq_get_page`) added to neurosys MCP server via orgparse. Private overlay wired with vault path + ProtectHome override. logseq-agent-suite GitHub repo with triage/graph-maintenance/review instruction files. Completed 2026-03-02.
- [x] **Phase 60: Dashboard DM Pairing & Backup Decrypt Guide** - DM guide service (port 8086) with QR pairing for Signal/WhatsApp, phone flow for Telegram, and backup upload/decrypt pipeline (Signal .backup, WhatsApp .zip, Telegram JSON). Matrix provisioning API enabled on all bridges. Completed 2026-03-02.
- [ ] **Phase 62: LLM Cost Tracking & Display** - Track LLM API costs at the secret proxy level. Per-request cost estimation from token counts + model pricing tables. Daily/weekly/monthly aggregation. Expose via MCP tool (`llm_cost_summary`) and optional Telegram inline display on parts agent responses.
- [x] **Phase 61: Nix-Derived Dynamic Dashboard** - Replace homepage-dashboard with Nix-derived dashboard. NixOS option schema `services.dashboard.entries`, build-time JSON manifest, Python HTTP server + dark-theme HTML frontend, systemd service on port 8082. All modules annotated with dashboard entries. Completed 2026-03-04.
- [x] **Phase 64: Repo Layout Simplification** - Rename hosts/neurosys→services, hosts/ovh→dev. Remove beads, logseq, docs, spacebot port. Delete modules hub; per-host explicit imports. Merge/inline small modules and packages. Completed 2026-03-04.
- [x] **Phase 63: Google OAuth + Gmail/Calendar MCP Tools** - Completed 2026-03-04. Added Google OAuth flow plus Gmail and Calendar MCP tools.
- [x] **Phase 65: Open Source Cleanup (v2)** - Completed 2026-03-04. Public repo reduced to minimal forkable skeleton with private overlay extension points.
- [x] **Phase 66: Secret Placeholder Proxy Module** - Generic NixOS secret placeholder injection module and Rust proxy package (axum + reqwest). Per-service systemd isolation, bwrapArgs derived attr, port-collision assertion. Completed 2026-03-07.
- [x] **Phase 67: Review and Document Secret Proxy** - Consumer-facing architecture doc (`docs/secret-proxy-architecture.md`): 8 design features, 10 limitations, test coverage gaps, 7 improvement areas. Completed 2026-03-07.
- [x] **Phase 68: Extract secret-proxy into standalone nix-secret-proxy flake** - Standalone `nix-secret-proxy` flake with Rust binary + NixOS module. neurosys and private-neurosys consume via flake input. Completed 2026-03-09.
- [x] **Phase 69: OVH Dev Environment Migration** - OVH VPS configured as primary dev host. secret-proxy-dev service, per-host repo clone scripts, real sops secrets, setupSecrets dep fix. Deploy infrastructure: `--node all` parallel deploy. Acceptance test: Claude Code works via secret-proxy on OVH. Completed 2026-03-10.
- [x] **Phase 72: Secret Proxy — Issue Resolution & Hardening** - Phase 72 nix-secret-proxy fixes: /health endpoint, large-body support (DefaultBodyLimit removed), JSON-structured 502 errors, configurable bind address, upstream timeout, graceful shutdown. 8 integration tests. Completed 2026-03-10.
- [ ] **Phase 72.1: OVH Secret Proxy — Deploy Phase 72 & Live Acceptance Tests** (INSERTED) - Deploy Phase 72 nix-secret-proxy to OVH; BATS live tests for /health, 403 host-reject, service user, journal errors; end-to-end agent smoke test; prerequisite for Phase 73. Progress: 72.1-01 complete, 72.1-02 pending.
- [x] **Phase 73: OVH Agent Sandbox Enforcement** - OVH wrappers now enforce bubblewrap sandboxing by default for `claude`/`codex`, gate `--no-sandbox` behind `AGENT_ALLOW_NOSANDBOX=1`, log launch audits, and include eval/live test coverage (`agent-audit-dir`, OVH wrapper BATS). Completed 2026-03-11.
- [x] **Phase 74: Open Source Release Prep v3** - Identifier scrub (74-01), dead code removal + README polish (74-02), git history reset to single clean commit (74-03). 54 tracked files, zero personal identifiers, all 33 eval checks pass. Completed 2026-03-11.
- [x] **Phase 75: Dashboard UI Modernization** - Unified tab navigation (Services/Cost/Canvas), inline cost table with 5-min refresh, removed standalone cost page, `/cost` redirect. Completed 2026-03-12.
- [ ] **Phase 76: Code Review Integration + README Rewrite + Simplicity Pass** - SUPERSEDED by Phases 150-157 (March 2026 comprehensive review). Remaining items absorbed into themed phases.
- [x] **Phase 77: Unified Design System** - Canonical neurosys CSS design tokens, Dashboard migrated, Conway Dashboard and Logseq Triage dark mode aligned to palette. Completed 2026-03-12.
- [ ] **Phase 78: Unified Agent Context Layer — neurosys-context** - Consolidate all agent-facing data/context services into a single neurosys-context flake repo.
- [x] **Phase 79: Public Repo Showcase Review** - Review public and private repos to identify features worth moving or better advertising in the public repo. Plans 79-01 and 79-02 complete. Completed 2026-03-12.
- [x] **Phase 80: Integrate nono — replace nix-secret-proxy and bwrap with nono, update README** - Replace nix-secret-proxy and bubblewrap with nono as the sole sandbox/credential injection layer. Remove all bwrap references. Update README for nono-only security model.
- [x] **Phase 85: Service Type Framework** - Define a small set of service types (prod-web, dev-agent, internal, system) with sensible defaults for host assignment, networking, sandboxing, systemd hardening, and dashboard integration. Implement as a NixOS option schema (`neurosys.serviceType`). Refactor existing modules/services to declare their type. Each type encodes invariants (e.g., internal services bind 127.0.0.1, prod-web gets ACME+nginx, dev-agents run in nono sandbox). Document the taxonomy in README. Completed 2026-03-15.
- [x] **Phase 86: Feature Abstraction Layer — core vs swappable capabilities** - Research and design an abstraction layer that separates neurosys's high-level capabilities (backup, file-sync, agent-sandbox, secret-management) from their current implementations (restic/B2, syncthing, nono, sops-nix). Evaluate whether the indirection is worth it: does a backup interface help ensure new backends respect impermanence paths? Does a sync abstraction enforce Tailscale-only networking? Clearly denote core (non-swappable) features (impermanence, Tailscale, nftables, sops-nix) vs swappable capability backends. Produce a design doc with concrete NixOS option schemas and a go/no-go recommendation per capability.
- [x] **Phase 88: Guix Port Feasibility Study** - Research-only. Deep investigation of porting neurosys from NixOS to GNU Guix System. Package coverage gaps, security update latency, community health, hardware support, Guile Scheme ergonomics for coding agents, impermanence/reproducibility/secrets/sandbox/deployment equivalents. Executive summary with migration difficulty estimate and go/no-go recommendation. Context: user prefers Lisp long-term; all dev by coding agents; user does not plan to learn Nix language. Completed 2026-03-14.
- [ ] **Phase 89: NixOS Agent Infrastructure Research** - Literature search for projects combining NixOS configurations with AI agent infrastructure. Focus on projects with recent commits (last few weeks). Document findings: project name, repo URL, last commit date, key features, relevance score (1-10), adoption recommendations. Identify patterns worth integrating into neurosys.
- [x] **Phase 93: Syncthing Mesh — automatic cross-host sync** - `neurosys.syncthing.mesh` option interface for device registry + shared folders. Public repo provides mechanism; private overlay configures real hosts. Completed 2026-03-16.
- [ ] **Phase 144: GSD — High-Impact Security + Core Dev-Agent Ops Remediation** - SUPERSEDED by Phase 154 (Agent Sandbox Architecture Overhaul). Control-plane concept removed; dev-agent reworked as thin wrapper.
- [ ] **Phase 150: Relocate Private Concerns from Public Core** — RUNS FIRST (independent, reduces surface area for all subsequent phases). Move Tailscale to priv overlay, remove dashboard module + all `services.dashboard.entries` refs across 7+ files, remove restic status server, remove syncthing example. Clean up eval tests (dashboard checks, Tailscale assertions). Absorbs syncthing removal from old Phase 155.
- [ ] **Phase 151: Repo Hygiene — Git History Only** — Purge .planning from git history (BFG/filter-repo), add commit hook to block re-addition. SKIP file headers (deferred to Phase 157 after all rewrites complete).
- [ ] **Phase 152: User Model + Agent Sandbox Architecture Overhaul** — MERGED from old 151+154 to avoid double-rewriting agent-sandbox.nix/agent-wrapper.sh/users.nix. Remove dev user (root+agent only), fix all dev-user refs in home config/cass/codex/host configs. Simplify break-glass to root SSH key. Remove control-plane concept + .tsurf-control-plane marker. Rewrite agent-sandbox.nix as generic systemd launcher (inherently removes sudo). Make nono generic. Simplify dev-agent to thin wrapper. Remove pi.nix + opencode.nix. Re-evaluate zmx. Supersedes Phase 144.
- [ ] **Phase 153: Base System & Networking Simplification** — Runs after 150 (Tailscale gone) and 152 (user model settled). Simplify networking.nix (lean on srvos). Agent egress stays in networking.nix per @decision NET-144-01 — do NOT move to nono. Review base.nix packages. Disable coredumps. Review/document IMP-05. Add impermanence.nix per-module docs.
- [ ] **Phase 154: Deploy & Examples Rework** — Simplify deploy.sh, promote to core template. Fix deploy skill (remove private refs). Improve/replace greeter example. Update private overlay docs for new user model. Syncthing already removed in Phase 150.
- [ ] **Phase 155: tsurf CLI & Commit Tooling** — Create `tsurf init` wizard (root SSH key gen, placeholder fill). Create `tsurf status` CLI (replaces dashboard). Add complexity metric + commit hook.
- [ ] **Phase 156: Final Polish — Guardrails, File Headers, Doc Cleanup** — MERGED from old 157+158+deferred-150-headers. Move cass.nix to core with resource limits. Integrate agentic-dev-base. Add sensitive-info commit hooks + README modification guard. Add 2-3 sentence description headers to all surviving files (deferred from 151). Final docs/specs update. Audit @decision annotations — keep only critical + concise, remove stale references to dev user, control-plane, dashboard, pi/opencode, break-glass key.
- [ ] **Phase 157: Address Review Notes** — Review and address findings from per-phase xhigh review agents (accumulated in `tmp/review-notes.md`). Fix any correctness, technical excellence, or minimalism issues identified. Final `nix flake check` pass.
- [ ] **Phase 158: Complexity Hotspot Report** — Research-only. Scan the repo using the complexity metric (scripts/complexity-metric.sh) and manual analysis to produce a prioritized report of the most complex areas (files, modules, scripts). For each hotspot: current eLOC, cyclomatic complexity estimate, why it's complex, and 2-3 concrete suggestions for how it could be simplified or removed. Executive summary with top-5 targets. No code changes.

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
| 22. Secret Proxy (Netclode Pattern) | 1/1 | ✓ Complete | 2026-02-24 |
| 29. Agentic Dev Maxing — Batteries Included | 0/TBD | Not started | - |
| 23. Tailscale Security & Self-Sovereignty | 1/2 | In progress | - |
| 24. Server Hardening + DX | 1/1 | ✓ Complete | 2026-02-23 |
| 25. Deploy Safety (deploy-rs) | 1/1 | ✓ Complete | 2026-02-21 |
| 26. Agent Notifications (Telegram Bot) | 0/TBD | Not started | - |
| 27. OVH VPS Production Migration | 0/5 | Not started | - |
| 28. dangirsh.org Static Site on Neurosys | 0/4 | Not started | - |
| 44. Android CO2 Alert | 0/1 | In progress (A/B complete; C checkpoint pending) | - |
| 46. Big Push — Deploy + Integrate + Test | 0/TBD | Not started | - |
| 93. Syncthing Mesh — cross-host sync | 1/1 | ✓ Complete | 2026-03-16 |

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

**Goal:** Two-tier proxy where real API keys never enter agent sandboxes. Inspired by [Netclode](https://github.com/nichochar/netclode) and [Fly's Tokenizer](https://github.com/superfly/tokenizer). Agents see placeholder keys + `ANTHROPIC_BASE_URL` pointing at the proxy; the proxy (outside sandbox) injects the real key via the `x-api-key` header on the way out. Real key never enters sandbox env. Scoped to claw-swap projects for initial rollout.
**Depends on:** Phase 11 (agent sandboxing — proxy integrates with sandbox env injection)
**Requirements:** None (security hardening — new capability)
**Actual approach:** `ANTHROPIC_BASE_URL=http://127.0.0.1:9091` (simpler than HTTP_PROXY/TLS MITM — SDK makes plain HTTP to proxy, proxy forwards HTTPS upstream). ~60-line Python stdlib proxy via `pkgs.writers.writePython3Bin`. Dedicated `secret-proxy` system user with sops template ownership.
**Plans:** 1 plan

Plans:
- [x] 22-01-PLAN.md -- Python stdlib secret proxy NixOS module + agent-spawn claw-swap integration

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

### Phase 27: OVH VPS Production Migration

**Goal:** Deploy neurosys NixOS config to a new OVH VPS (135.125.196.143) as the production server. Refactor from single-host to multi-host NixOS configuration (neurosys-prod on OVH, neurosys-staging on Contabo). nixos-anywhere deployment, Tailscale join, deploy-rs multi-node support, secrets bootstrap, service migration, and DNS/role cutover. Contabo becomes a staging/testing target for rapid iteration.
**Depends on:** Phase 25 (deploy-rs), Phase 3 (Tailscale + secrets infrastructure)
**Plans:** 5 plans

Plans:
- [ ] 27-01-PLAN.md -- Pre-deploy recon of OVH VPS + SSH host key generation + sops secrets bootstrap
- [ ] 27-02-PLAN.md -- Multi-host flake refactor (mkHost helper, hosts/ovh/, parameterize modules, deploy.sh --node)
- [ ] 27-03-PLAN.md -- nixos-anywhere deployment to OVH VPS (human checkpoint: destructive operation)
- [ ] 27-04-PLAN.md -- Post-deploy verification: Tailscale join, service validation, deploy-rs test, recovery runbook update
- [ ] 27-05-PLAN.md -- Service migration (Docker state rsync), DNS cutover, Contabo staging repurpose

### Phase 28: dangirsh.org Static Site on Neurosys

**Goal:** Move dangirsh.org from NearlyFreeSpeech (NFS) to the OVH production host. Hakyll static site built as a Nix flake package (`github:dangirsh/dangirsh.org`). NixOS nginx becomes the unified reverse proxy for all web traffic (replaces Docker Caddy in claw-swap). ACME (Let's Encrypt) handles TLS for dangirsh.org and claw-swap.com. Manual update workflow: push to GitHub + `nix flake update dangirsh-site` + deploy.
**Depends on:** Phase 27 (OVH VPS deployed and operational)
**Plans:** 4 plans

Plans:
- [x] 28-01-PLAN.md -- Modernize dangirsh-site Hakyll build (add flake.nix to dangirsh/dangirsh.org repo, nixpkgs-25.11 compatible)
- [x] 28-02-PLAN.md -- nginx unified reverse proxy + ACME + claw-swap Caddy removal + impermanence + deploy (wave 1, parallel with 28-01)
- [ ] 28-03-PLAN.md -- Deploy to OVH + DNS cutover from NFS (human checkpoint: DNS change)
- [ ] 28-04-PLAN.md -- Post-cutover cleanup: validate workflow, confirm NFS decommission, update docs

### Phase 29: Agentic Dev Maxing — Batteries Included

**Goal:** Make neurosys the definitive batteries-included agentic development platform. Install all major CLI coding agents pre-configured and ready to use. Add API keys for every major model provider so any agent can be used without manual setup. Research vibe-kanban (BloopAI) for remote agent session management. Every commonly-used agentic dev tool should work out-of-the-box after a fresh deploy.
**Depends on:** Phase 5 (agent tooling baseline — claude-code, codex, agent-spawn already in place)
**Requirements:** None (developer experience improvement)

**Research findings (pre-researched via parallel agents):**

Tools in nixpkgs (ready to add):
- **opencode** (`pkgs.opencode`): Multi-provider TUI with plan/build agents. Go CLI. Include.
- **goose-cli** (`pkgs.goose-cli`): Block's extensible agent, 25+ LLM providers, MCP-native. Rust. Include.
- **aider-chat** (`pkgs.aider-chat`): Session-based pair programmer, strong git integration. Include.
- **plandex** (`pkgs.plandex`): In nixpkgs but project winding down (Oct 2025) — skip.

Tools needing custom packaging:
- **gemini-cli** (`@google/gemini-cli` npm): Env: `GOOGLE_API_KEY`. nixpkgs status unclear — `buildNpmPackage` fallback.
- **pi** (`@mariozechner/pi-coding-agent` npm): Minimalist 4-tool TS agent by Mario Zechner. NOT in nixpkgs — defer.
- **fabric** (Go, 100+ AI patterns): NOT in nixpkgs — defer.

Agent management UI:
- **vibe-kanban** (BloopAI, Tauri/Rust): Kanban for parallel agent orchestration with git worktree isolation. NOT in nixpkgs. Tauri app needs WebKitGTK — headless server deployment requires investigation (buildRustPackage + virtual display, or run locally + SSH tunnel). Decide during planning.

**API providers to add** (sops secrets + bash.nix exports):
- `GOOGLE_API_KEY` — Gemini 2.5, 60 req/min free tier
- `XAI_API_KEY` — Grok-3/2, fast inference (xai-... format)
- `OPENROUTER_API_KEY` — unified access to 200+ models (sk-or-... format)
- `GROQ_API_KEY` — very fast inference on Llama/Mixtral (optional)
- `MISTRAL_API_KEY` — Mistral models (optional)

**Success Criteria** (what must be TRUE):
  1. `opencode`, `goose-cli`, `aider-chat` available on PATH (nixpkgs packages in agent-compute.nix)
  2. `gemini-cli` packaged and available (nixpkgs or buildNpmPackage)
  3. `GOOGLE_API_KEY`, `XAI_API_KEY`, `OPENROUTER_API_KEY` in sops-nix and exported in bash.nix
  4. Each agent CLI smoke-tested on the live server
  5. vibe-kanban deployment decision made with rationale (headless Rust package vs local + tunnel vs defer)
  6. `nix flake check` passes with all new packages and secrets
**Effort:** Medium — nixpkgs coverage is solid for main tools; gemini-cli packaging + API key additions + vibe-kanban investigation is the main work.
**Plans:** TBD (run /gsd:plan-phase 29 to break down)

Plans:
- [ ] TBD (run /gsd:plan-phase 29 to break down)

### Phase 30: Claw-Swap Native NixOS Service

**Goal:** Replace claw-swap's Docker containers with native NixOS services — `services.postgresql` for the database and a systemd service running the Nix-built Node.js package. Remove the claw-swap Docker network, `virtualisation.oci-containers` declarations, and custom bridge. All existing sops-nix secrets preserved and injected natively (no env-file template indirection). Docker engine stays for parts but claw-swap exits the container layer entirely, improving simplicity (fewer layers, native journald logs, systemd dependency management) and security (no Docker socket involvement, native DynamicUser isolation, no cap-drop workarounds).
**Depends on:** Phase 28 (nginx already handles reverse proxy to 127.0.0.1:3000)
**Requirements:** None (simplification + security hardening)
**Success Criteria** (what must be TRUE):
  1. `services.postgresql` running with `claw_swap` database and `claw` role
  2. `claw-swap-app` systemd service running the Nix-built package (nix/claw-swap-app.nix) on port 3000
  3. All existing sops secrets injected natively (DB password, R2 keys, World ID app ID)
  4. nginx still proxies `claw-swap.com` → `127.0.0.1:3000` unchanged
  5. `virtualisation.oci-containers.containers.claw-swap-*` removed from module.nix
  6. Docker network `claw-swap-net` and its systemd unit removed
  7. Docker engine and parts containers unaffected (no regressions)
  8. `nix flake check` passes
  9. Live smoke test: `curl https://claw-swap.com` returns 200
**Effort:** Medium — PostgreSQL NixOS service is trivial; Node.js systemd service needs Nix package wiring + secrets injection pattern.
**Plans:** 2 plans complete

Plans:
- [x] 30-01-PLAN.md -- module rewrite + flake validation
- [x] 30-02-PLAN.md -- deploy to production OVH

### Phase 31: Conway Automaton — Single Agent MVP

**Goal:** Deploy 1 sovereign AI agent (Conway Automaton) on Conway Cloud, funded with ~$250 USDC. Seed hypothesis #1: "Build x402 APIs that other agents will pay for." Maximum autonomy — agent decides its own execution plan. Terminal monitoring dashboard on neurosys via `scripts/fleet-status.sh`.
**Depends on:** Nothing (external platform — Conway Cloud)
**Plans:** 1 plan

**Research:** See `.planning/phases/31-conway-automaton-single-agent-mvp/31-RESEARCH.md` (comprehensive Conway Cloud, Automaton framework, x402 protocol research from 2026-02-22).

**Success Criteria** (what must be TRUE):
  1. 1 automaton agent running on Conway Cloud with seed hypothesis #1 as genesis prompt
  2. Agent wallet funded with ~$250 USDC on Base chain
  3. Agent using claude-sonnet-4.6 as primary model with BYOK Anthropic key
  4. `scripts/fleet-status.sh` on neurosys shows agent balance, tier, burn, turn count
  5. Agent has completed its first reasoning turn within 1 hour of deployment
**Effort:** Low for neurosys changes (fleet-status.sh only); human-interactive for Conway Cloud setup and agent deployment.

Plans:
- [ ] 31-01-PLAN.md -- Conway Cloud setup + agent deployment + fleet monitoring script

### Phase 32: Self-Hosted Conway Automaton on Neurosys

**Goal:** Run the Conway Automaton framework directly on neurosys as a NixOS service instead of paying Conway Cloud for agent compute. Agents execute as persistent systemd services on neurosys hardware (no external cloud sandbox fees), use BYOK Anthropic key through the existing secret proxy, and persist state to `/var/lib/automaton/`. Conway Cloud tools remain available to agents for external workloads (spinning up sandboxes, buying domains, exposing ports) but the agent runtime itself runs free on owned hardware.
**Depends on:** Phase 22 (secret proxy for BYOK Anthropic key), Phase 31 (understanding of automaton config + genesis prompts)
**Requirements:** None
**Success Criteria** (what must be TRUE):
  1. `automaton` systemd service running on neurosys, agent loop active
  2. Agent uses BYOK Anthropic key via secret proxy (no Conway Compute billing for inference)
  3. Agent state persisted at `/var/lib/automaton/` (SQLite + git-versioned)
  4. Agent can reach Conway Cloud tools (for external sandboxes, domains, payments) if needed
  5. `nix flake check` passes with new automaton module
  6. Agent completes at least one reasoning turn without errors
**Effort:** Medium — TypeScript/Node.js NixOS packaging + sops secret wiring + automaton config tuning
**Plans:** TBD (run /gsd:plan-phase 32 to break down)

Plans:
- [x] 32-01: Package Conway Automaton as NixOS derivation (complete)
- [ ] 32-02: NixOS service module + secrets + deployment (pending)

### Phase 33: Research spacebot security: prompt injection defenses + ironclaw integration feasibility

**Goal:** [To be planned]
**Depends on:** Phase 32
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 33 to break down)

### Phase 34: Voice MCP — Claude Android app tools via Home Assistant

**Goal:** Enable Claude Android voice mode to control lights, query CO2 levels, and read other Home Assistant sensors via a remote MCP server on neurosys. Say "turn off the lights" or "what's the CO2 level?" and have it actually work.
**Depends on:** Phase 3 (Home Assistant operational, Tailscale infrastructure)
**Plans:** 0 plans

**Approach:**
- **MCP server**: Home Assistant has a native MCP integration (added in HA 2024.11). Enable it — it auto-exposes all HA entities as MCP tools (lights, sensors, switches). No separate service to write or maintain.
- **Access layer**: Claude Android app needs HTTPS. Use Tailscale Serve to provision a TLS endpoint at `https://neurosys.<tailnet>.ts.net` without public internet exposure. Keeps MCP server Tailscale-only (same security posture as all other internal services); Tailscale Serve handles Let's Encrypt certs automatically.
- **CO2 data**: Assumed to come from a HA sensor (ESPHome device or Hue sensor). If not yet in HA, note that the CO2 sensor must be paired first before MCP can surface it.

**Deliverables:**
1. `modules/home-assistant.nix` — enable `mcp_server` integration, HA long-lived access token via sops secret
2. `modules/networking.nix` — add any new ports to `internalOnlyPorts`
3. Tailscale Serve config in NixOS to proxy HA MCP endpoint over HTTPS
4. `secrets/neurosys.yaml` — add HA long-lived token (sops-encrypted)
5. Manual verification: Claude Android app connects and can toggle a light + read a sensor via voice

Plans:
- [ ] TBD (run /gsd:plan-phase 34 to break down)

### Phase 35: Unified Messaging Bridge — Signal + WhatsApp + Telegram → AI

**Goal:** Self-hosted Matrix hub (Conduit) with mautrix bridges for Telegram, WhatsApp, and Signal, giving AI read access to all DMs. All packages are in nixpkgs — no Docker needed.

**Architecture:**
- Conduit (Rust, ~32MB RAM) as Matrix homeserver — `services.matrix-conduit`, federation disabled
- mautrix-telegram — official MTProto API, highest stability, no account ban risk
- mautrix-whatsapp — unofficial WA Web protocol, `services.mautrix-whatsapp`, medium ban risk (documented)
- mautrix-signal — signal-cli backend, `services.mautrix-signal`, medium stability
- AI read access: dedicated Matrix bot user + Client-Server API (`/sync`, `/messages`) — no admin privilege needed
- All services Tailscale-only; ports in `internalOnlyPorts`

**Historical data strategy** (bridges only sync forward — history goes to Spacebot LanceDB):
- Telegram: official JSON export → one-time ingest script
- Signal: Android `.backup` → `signalbackup-tools` decrypt → one-time ingest
- WhatsApp: `.zip` export (.txt) → one-time ingest

**Security notes:**
- E2E encryption breaks at bridge by design (messages decrypted on server) — self-hosted mitigates trust concern
- sops-nix for all bridge credentials (Telegram API id/hash, Signal registration, WA pairing code)
- mautrix-signal: `MemoryDenyWriteExecute=false` required for libsignal JIT (systemd hardening caveat)
- WA account detection/disconnection risk: documented as accepted risk

**Depends on:** Phase 34
**Plans:** 3 plans

Plans:
- [ ] 35-01: Conduit homeserver + mautrix-telegram (prove architecture, lowest risk first)
- [ ] 35-02: mautrix-whatsapp + mautrix-signal bridges (add remaining platforms, document WA ban risk)
- [ ] 35-03: AI read bot + historical ingest pipeline (Matrix CS API bot → Spacebot LanceDB; one-time import scripts)

### [x] Phase 36: Research stereOS ecosystem (stereOS, masterblaster, stereosd, agentd)

**Goal:** Comprehensive source-level study of stereOS ecosystem (agentd, masterblaster, stereosd, stereOS, tapes, flake-skills) — adoption table, switch recommendation, action items for neurosys roadmap
**Depends on:** None (standalone research, no Phase 35 dependency)
**Plans:** 1 plan

Plans:
- [x] 36-01: Clone repos, deep-read source, write research report with adoption table and switch recommendation (complete)

### Phase 37: Open Source Prep

**Goal**: Prepare the neurosys NixOS configuration for public open source release with three outputs: (1) privacy-audited public repo with personal identifiers removed, (2) private flake overlay repo adding personal config on top, (3) lean public README.

**Depends on:** Phase 32
**Plans:** 3 plans

Plans:
- [x] 37-01-SUMMARY.md -- Full privacy/security audit for public release (PII scrub, private input/module removal, nix flake check pass)
- [ ] 37-02-PLAN.md -- Split private overlay patterns and write principles for composing private services on top of the public flake
- [ ] 37-03-PLAN.md -- Write lean public README focused on reusable infrastructure patterns and private-overlay onboarding

### Phase 38: Dual-host role separation: Contabo as services host, OVH as dev-agent host

**Goal:** [To be planned]
**Depends on:** Phase 37
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 38 to break down)

### Phase 39: Conway Automaton monitoring dashboard

**Goal:** Lightweight web UI (Tailscale-only) showing live agent status. Reads from journald + automaton SQLite state.db. Displays: agent state (running/sleeping/thinking), Conway credits balance, total turns, current goal + task progress, recent tool calls, spend rate ($/hr). Served on an internal port with no public exposure. Linked from the main neurosys homepage dashboard as a new service entry.
**Depends on:** Phase 32
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 39 to break down)

### Phase 40: agentd Integration — Supervised Agent Lifecycle

**Goal:** Research whether agentd is the right supervision model for neurosys agents, then adopt it. Validate against alternatives (pure systemd supervision, s6/runit, supervisord) before building. If validated: replace one-shot `agent-spawn` with agentd — reconciliation-loop daemon, restart policy (on-failure/always), HTTP API for live agent status. Keep bubblewrap sandbox via agentd `custom` harness. Wire sops-nix secret dir. jcard.toml declarative config per agent.
**Depends on:** Phase 38 (dual-host separation — agentd should live on the OVH dev-agent host)
**Requirements:** None (robustness + dev ergonomics improvement)
**Success Criteria** (what must be TRUE):
  1. Research confirms agentd is the right choice vs. alternatives — or recommends a better option with rationale
  2. agentd running as NixOS systemd service with correct tmux socket ownership (`DynamicUser=false`, group `admin`)
  3. `GET /v1/agents` returns live agent status (running, restarts, session)
  4. Agent crashes trigger automatic restart within configured policy — verified by killing agent process and observing recovery
  5. jcard.toml for claude-code harness committed to repo; `agent-spawn` replaced or deprecated
  6. bubblewrap sandbox preserved — agentd launches via `custom` harness wrapping existing bwrap invocation
  7. `nix flake check` passes
**Effort:** Medium — research first, then 1-2 implementation plans
**Plans:** 0 plans

Plans:
- [ ] 40-01: Research — validate agentd vs. alternatives (systemd, s6, supervisord); assess current maturity; evaluate jcard.toml schema fit
- [ ] 40-02: Implementation — NixOS module, sops-nix wiring, jcard.toml, bwrap harness, Prometheus integration

### Phase 41: Agent User Isolation — Curated PATH + Sudo Denial

**Goal:** Research whether a dedicated `agent` system user with curated `buildEnv` PATH and explicit sudo denial fills a meaningful security gap beyond the existing bubblewrap namespace isolation, then implement if validated. Inspired by stereOS's `stereos-agent-shell` pattern. Defense-in-depth: bwrap provides namespace isolation; agent user limits what a bwrap-escaped agent can do on the host. If research shows bwrap's user namespace already covers this, skip.
**Depends on:** Phase 40 (agentd introduces the agent user concept — coordinate user design)
**Requirements:** None (security hardening)
**Success Criteria** (what must be TRUE):
  1. Research documents the concrete threat model gap between bwrap alone vs. bwrap + dedicated agent user
  2. If adopted: dedicated `agent` system user in `users.nix`, curated `buildEnv` in `agent-compute.nix`
  3. Agent cannot execute `nix build`, `nix-env`, `sudo`, or binaries outside the curated set — verified by attempting each from an agent session
  4. Existing bubblewrap sandbox remains functional — no regression in agent DX
  5. `nix flake check` passes
**Effort:** Low-Medium — research is the bulk; implementation is ~30 lines of Nix
**Plans:** 0 plans

Plans:
- [ ] 41-01: Research — threat model analysis (what bwrap misses, what agent user adds); audit current agent binary requirements; evaluate whether buildEnv + sudo denial is worth the operational friction
- [ ] 41-02: Implementation — if validated: `agent` user, buildEnv, sudo denial, session wiring

### Phase 42: masterblaster — VM-Based Agent Isolation

**Goal:** Research whether OVH VPS has KVM, whether masterblaster is mature enough to adopt, and whether VM-level isolation provides meaningful security improvement over the bwrap + agent-user stack for neurosys's agent threat model. If validated: adopt masterblaster on the OVH dev-agent host — `mb up` per agent session, stereOS mixtape images, QCOW2 overlays, agentd inside VMs. This is the highest security ceiling available: kernel boundary vs. namespace boundary.
**Depends on:** Phase 38 (dual-host — masterblaster runs on OVH), Phase 41 (agent user isolation baseline established)
**Requirements:** KVM available on OVH VPS (verify in research phase — hard blocker if absent)
**Success Criteria** (what must be TRUE):
  1. OVH KVM availability confirmed: `grep -c vmx /proc/cpuinfo` on neurosys-prod returns > 0
  2. Research evaluates alternatives: Firecracker (AWS, production-grade), Kata Containers (OCI-compatible), cloud-hypervisor — recommends masterblaster or an alternative with rationale
  3. masterblaster current release maturity assessed — if still pre-release single-developer, document acceptance criteria for adoption vs. further deferral
  4. If adopted: `mb up` launches a stereOS VM on OVH; agent runs inside VM with agentd supervision
  5. VM agent cannot read host filesystem, host `/run/secrets`, or host Docker sockets — verified
  6. `mb destroy` cleanly terminates VM; disk overlay removed
  7. Startup latency measured and documented (acceptable: <10s for interactive use)
**Effort:** High — KVM verification + significant research + complex NixOS integration
**Plans:** 0 plans

Plans:
- [ ] 42-01: Research — OVH KVM check; masterblaster current maturity; Firecracker/Kata/cloud-hypervisor comparison; threat model analysis; go/no-go recommendation
- [ ] 42-02: Implementation — masterblaster NixOS service, mixtape build, sops-nix host secrets, jcard.toml per agent (if research gives go)

### Phase 43: tapes — Agent Session Telemetry

**Goal:** Research whether tapes fills a real observability gap for neurosys's agent workloads vs. existing tools (Spacebot LanceDB, Prometheus), and whether it's mature enough to operate. tapes is a transparent proxy that records agent↔LLM conversations with content-addressable storage, semantic search (via Ollama embeddings), and session replay. If validated: deploy on neurosys as a proxy layer, all agent sessions recorded and searchable.
**Depends on:** Phase 40 (agentd — agents route through tapes proxy; coordinates with agentd session model)
**Requirements:** None (dev ergonomics improvement)
**Success Criteria** (what must be TRUE):
  1. Research documents what Spacebot already captures and where the gap is — no adoption if Spacebot covers it
  2. Research evaluates production-grade alternatives: LangFuse (OSS, self-hosted), Helicone, Weave (W&B) — recommends tapes or an alternative
  3. Privacy model documented: what is stored, where, retention policy, whether prompt content is acceptable to record
  4. If adopted: tapes proxy running on neurosys; `ANTHROPIC_BASE_URL` set to tapes proxy (chains with existing secret proxy)
  5. `tapes search "query"` returns relevant past sessions within 2s
  6. No measurable latency regression on agent inference (p99 < 200ms overhead)
  7. Ollama infrastructure cost assessed — if embeddings require running Ollama full-time, document the resource cost
**Effort:** Medium — research is substantial; proxy deployment is straightforward if validated
**Plans:** 0 plans

Plans:
- [ ] 43-01: Research — gap analysis vs. Spacebot; LangFuse/Helicone/Weave comparison; tapes current maturity; privacy model; Ollama infrastructure cost
- [ ] 43-02: Implementation — tapes NixOS service, proxy chaining with secret-proxy, session retention config (if research validates)

### Phase 44: Android CO2 Alert

**Goal:** Send a push notification to the Pixel 10 Pro when the Apollo AIR-1 CO2 sensor exceeds 1000 ppm. Add a Home Assistant automation to `dangirsh/home-assistant-config` that calls `notify.mobile_app_*` with a cooldown so it doesn't spam. Include a recovery notification when CO2 drops back to normal.
**Depends on:** None (HA companion app already paired; ESPHome sensor already in HA)
**Requirements:** None (quality-of-life automation)
**Success Criteria** (what must be TRUE):
  1. Automation triggers on `sensor.apollo_air_1_5221b0_co2` exceeding 1000 ppm
  2. Push notification arrives on Pixel 10 Pro with CO2 reading in the message body
  3. Cooldown of at least 30 minutes between repeat alerts (no spam)
  4. Recovery notification sent when CO2 drops back below 900 ppm
  5. Automation committed to `dangirsh/home-assistant-config` and loaded by HA
**Effort:** Low — single automation YAML file, no NixOS module changes needed
**Plans:** 1 plan

Plans:
- [ ] 44-01-PLAN.md -- CO2 alert automation: threshold trigger + cooldown + recovery notification in automations.yaml (tasks A/B complete; task C checkpoint pending)

### Phase 45: Neurosys MCP Server

**Goal:** Custom MCP server for Claude Android app. Python FastMCP with Streamable HTTP + OAuth 2.1. HA control + Matrix/Conduit DM queries. NixOS systemd service behind Tailscale Funnel.
**Depends on:** Phase 38
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 45 to break down)

### Phase 46: Big Push — Deploy, Integrate, and Test All Recent Work

**Goal:** Combine all recent in-progress work into one deployment push. Contabo VPS just had Ubuntu reinstalled — needs full NixOS re-bootstrap via nixos-anywhere. OVH should already be running. Merge unmerged branches, enable disabled modules, deploy both hosts, verify all services green, test MCP connectivity from Claude Android, set up DM bridges (Signal/WhatsApp/Telegram), verify circadian lighting automation, and confirm open-source readiness. This phase absorbs and closes Phases 27, 28, 32, 37, 39, and 44.
**Depends on:** Phase 38 (dual-host role separation complete)
**Plans:** TBD

**Success Criteria** (what must be TRUE):
  1. Both hosts (Contabo + OVH) running NixOS with all services green
  2. Public neurosys repo is open-source ready (no PII, builds clean, README accurate)
  3. Claude Android app connects to HA MCP and can control lights + query CO2
  4. Signal, WhatsApp, and Telegram bridges linked with history imported (OVH), queryable over MCP
  5. Deployment uses Cachix for speed on both hosts
  6. Circadian lighting automation active (lights follow the sun)
  7. All previously in-progress phases (27, 28, 32, 37, 39, 44) resolved

Plans:
- [ ] TBD (run /gsd:plan-phase 46 to break down)

### Phase 47: Comprehensive Security Review — Network hardening, intrusion blast radius containment, and attack surface minimization across public and private components

**Goal:** End-to-end security audit of the full neurosys infrastructure — both the public repo and private overlay — with three focus areas: (1) **Network attack surface hardening** — audit every listening port, firewall rule, nftables chain, Tailscale ACL, and public-facing service for unnecessary exposure or misconfiguration; verify defense-in-depth (fail2ban + nftables + Tailscale) has no gaps. (2) **Intrusion blast radius containment** — assess what an attacker can reach after compromising each component (agent sandbox, Docker container, systemd service, user session, sops secret); verify isolation boundaries (namespaces, cgroups, filesystem mounts, network segments, Unix users) limit lateral movement; ensure no single compromise grants access to all secrets or all services. (3) **Attack surface minimization** — identify unnecessary packages, services, open ports, elevated privileges, writable paths, and ambient capabilities that could be removed without functional impact. Covers: public modules, private overlay modules (nginx, repos, spacebot, automaton, homepage overrides, agent-compute overrides), Docker containers, sops secrets, deployment pipeline, and the agent sandbox.
**Depends on:** Nothing (independent audit — can run anytime)
**Requirements:** None (security hardening gate)
**Success Criteria** (what must be TRUE):
  1. Every listening port on both hosts (Contabo + OVH) has been enumerated and justified — no unnecessary listeners
  2. Every systemd service audited for isolation: ProtectSystem, ProtectHome, PrivateTmp, NoNewPrivileges, CapabilityBoundingSet, DynamicUser where applicable
  3. Blast radius matrix documented: for each component (agent sandbox, Docker container, HA, Matrix/Conduit, nginx, claw-swap, parts, spacebot, automaton), what can an attacker reach if that component is compromised?
  4. Tailscale ACLs reviewed and tightened — device-to-service access follows least privilege
  5. Docker containers audited for hardening: read-only rootfs, cap-drop ALL, no-new-privileges, resource limits, network isolation, no unnecessary volume mounts
  6. sops secrets audit: no over-broad access (each secret accessible only by the service that needs it), no unused secrets, owner/group permissions minimal
  7. Agent sandbox escape paths re-assessed with current config — cross-project read, Docker socket, /run/secrets visibility, network access
  8. Private overlay security review: nginx TLS config, proxy headers, ACME, public-facing service hardening
  9. All actionable findings implemented — `nix flake check` passes for both hosts after changes
  10. Residual accepted risks documented with @decision annotations and added to CLAUDE.md Accepted Risks
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 47 to break down)

### Phase 48: Test Automation Infrastructure

**Goal:** [To be planned]
**Depends on:** Phase 47
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 48 to break down)

### Phase 49: Security Hardening Follow-up — Fix HIGH priority issues from Phase 47 audit

**Goal:** Fix all HIGH priority security issues identified during the Phase 47 comprehensive security review. Four issues: (1) hardcoded passwords in bootstrap scripts visible in public repo history, (2) incomplete internalOnlyPorts coverage leaving 12+ ports without build-time assertion protection, (3) Matrix Conduit open registration potentially allowing unauthorized account creation, (4) Docker container images using unpinned tags (:latest/:slim) creating supply chain risk.
**Depends on:** Phase 47
**Success Criteria** (what must be TRUE):
  1. `scripts/bootstrap-contabo.sh` and `scripts/bootstrap-ovh.sh` contain no hardcoded passwords — env vars required or random generation used
  2. `internalOnlyPorts` in `networking.nix` covers all service ports including OpenClaw (18789-18794), Spacebot (19898), and Matrix (6167, 29317, 29318, 29328)
  3. Matrix Conduit registration is either token-protected (verified) or disabled
  4. All Docker container images in `openclaw.nix` and `spacebot.nix` are pinned to SHA256 digests
  5. `nix flake check` passes for both configurations
**Plans:** 1 plan

Plans:
- [x] 49-01: Remove hardcoded passwords, expand internalOnlyPorts to 23, document SEC49-01 accepted risk (2min, 2026-03-01)

### Phase 50: Coherence & Simplicity Audit

**Goal:** Holistic review of public + private neurosys for architectural coherence, threat model consistency, over-engineering, code smells, surprising non-standard decisions, feature conflicts, and design inconsistencies. Cross-cutting analysis: do modules compose cleanly? Are security boundaries consistent across the pub/priv split? Is complexity justified everywhere? Are there features that contradict each other or patterns that should be unified? Examine: flake structure, module design, service architecture (Docker vs native vs systemd), secret handling patterns, deployment pipeline, agent sandbox model, impermanence integration, monitoring, backup, and private overlay layering. Produce a prioritized findings report with concrete fix recommendations — then implement the fixes.
**Depends on:** Phase 49
**Success Criteria** (what must be TRUE):
  1. Every module in public repo reviewed for coherence with its neighbors — no contradictory patterns, no orphaned abstractions, no features that fight each other
  2. Private overlay modules reviewed for clean composition with public base — no surprising overrides, no copy-paste divergence, no unnecessary `mkForce`
  3. Threat model reviewed for consistency — security boundaries don't contradict each other (e.g., hardened service X next to unhardened service Y with same trust level)
  4. Over-engineering identified and removed — abstractions without justification, premature generalization, dead options, unused flexibility
  5. Code smells fixed — inconsistent naming, duplicated logic across modules, surprising conventions that could be standard NixOS patterns
  6. Non-standard decisions either documented with rationale (@decision annotations) or replaced with standard approaches
  7. Findings report produced with severity ratings (fix now / fix later / accept with documentation)
  8. All "fix now" items implemented — `nix flake check` passes for both configurations
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 50 to break down)

### Phase 51: Conway Automaton profitability research — why the agent loop fails and how to fix it

**Goal:** Diagnose why the automaton agent loop fails to produce profitable outcomes, reconfigure for productive work, and validate the agent can complete a revenue cycle.
**Depends on:** Phase 50
**Plans:** 4 plans (3 waves)

Plans:
- [x] 51-01-PLAN.md -- Diagnostic: SSH to verify service status, wallet, API key, DB state (wave 1)
- [x] 51-02-PLAN.md -- Reconfiguration: genesis prompt, token budget, maxChildren, social relay, SOUL.md (wave 2)
- [x] 51-03-PLAN.md -- Infrastructure: verify Conway API key, wallet funding deferred (wave 2, parallel with 51-02)
- [ ] 51-04-PLAN.md -- Validation: end-to-end revenue cycle verification (wave 3, pending)

### Phase 52: Nativize the Lobster Farm — Docker-Free Contabo
**Goal**: Eliminate Docker from Contabo by converting OpenClaw (6 instances) and Spacebot from OCI containers to native NixOS systemd services. Active users must not notice the transition — no data loss, no downtime beyond a single `nixos-rebuild switch`.
**Depends on**: Phase 50 (coherence audit may surface relevant findings)
**Requirements**:
  - OpenClaw: `buildNpmPackage` from `ghcr.io/openclaw/openclaw` source (Node.js). 6 instances with per-instance systemd services, same ports (18789-18794), same gateway config, same sops env templates.
  - Spacebot: Nix package from source or pre-built binary (Rust + React). Same port (19898), same `/var/lib/spacebot` state, same sops env template.
  - Data continuity: `/var/lib/openclaw-{user}/` and `/var/lib/spacebot/` volumes preserved in-place (Docker bind mounts → systemd StateDirectory). Activation script verifies data integrity.
  - Secret injection: Convert Docker `--env-file` to systemd `EnvironmentFile` (same sops templates, no secret changes needed).
  - Nginx: No changes — already proxies to `127.0.0.1:{port}`, Docker IP not used.
  - Homepage dashboard: Update from Docker container widgets to systemd service widgets. Remove `homepage-dashboard` user from `docker` group. Remove Docker socket dependency.
  - Monitoring: Service health checks stay on same ports. No Prometheus config changes.
  - openclaw-auto-approve.nix: Replace `docker exec` commands with direct CLI invocation.
  - Docker teardown: Remove `virtualisation.docker` and `virtualisation.oci-containers` from Contabo config once all containers are migrated. Prune Docker data after verification.
  - Rollback: Keep Docker config available on a branch for emergency revert during the transition window.
**Success Criteria** (what must be TRUE):
  1. All 6 OpenClaw instances respond on their original ports with working gateway + WebSocket connections
  2. Spacebot responds on port 19898 with existing SQLite DB and LanceDB embeddings intact
  3. `docker ps` returns empty on Contabo (no running containers)
  4. `systemctl status docker` is inactive/disabled on Contabo
  5. Homepage dashboard shows all services healthy without Docker socket access
  6. WhatsApp/messaging sessions remain active (no re-pairing required)
  7. `nix flake check` passes with updated config
  8. Restic backup still covers all state directories
**Plans**: 2/2 complete (2026-03-02)
**Status**: COMPLETE — OpenClaw nativized (6 native systemd services replace Docker containers). Spacebot stays Docker. Private overlay updated.

Plans:
- [x] 52-01: Package OpenClaw + Rewrite Public Module
- [x] 52-02: Update Private Overlay + Tests for Native OpenClaw

### Phase 53: Conway Dashboard Auth + Prompt Editor ✓

**Goal:** Two features for the Conway automaton dashboard: (1) Token-based authentication so the dashboard can be accessed over the public internet (not just Tailscale), via a bearer token in sops-nix and nginx reverse proxy with HTTPS. (2) A UI feature to edit the genesis prompt and restart the automaton agent with the new prompt — currently the prompt is hardcoded in Nix and requires a full NixOS rebuild to change. Changes span: `conway-dashboard` repo (server.py + dashboard.html), `private-neurosys` (automaton-dashboard.nix, automaton.nix, nginx.nix).
**Depends on:** Phase 39 (dashboard exists), Phase 32 (automaton service)
**Plans:** 3/3 complete
**Completed:** 2026-03-02

Plans:
- [x] 53-01: Dashboard Backend — Prompt Editing + Lifecycle Control + Token Forwarding
- [x] 53-02: Public Repo — Add Port 9093 to internalOnlyPorts
- [x] 53-03: Private Overlay — nginx Auth Proxy, Secrets, Dashboard Hardening, Tests

### Phase 54: Comprehensive Feature Review & Simplification

**Goal:** [To be planned]
**Depends on:** Phase 53
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 54 to break down)

### Phase 55: Evaluate absurd durable-execution for neurosys components

**Goal:** Assess whether https://github.com/earendil-works/absurd (PostgreSQL-backed durable execution with step checkpointing) should be adopted in neurosys or any component repo. Identify which workloads would benefit most, what the adoption cost is, and produce a concrete go/no-go recommendation per component.
**Depends on:** Phase 54
**Plans:** 1 plan

**Context:**
- absurd is a TypeScript/Python workflow engine backed by PostgreSQL (already deployed on neurosys)
- Core value: step checkpointing so long-running tasks survive crashes/restarts; "exactly-once" semantics; event wait/resume; pull-based worker model
- No extra services needed beyond Postgres + a Node/Python worker process

**Components to evaluate:**
1. **HA lights controller** — automations.yaml circadian cycle, CO2 alert, multi-step scenes. Do these multi-step light sequences need durability, or is HA's built-in automation engine sufficient?
2. **Conway Automaton** — long-running agentic loops with inference cost tracking, goal checkpointing, tool call sequences. Highest candidate for durable execution benefit.
3. **claw-swap** — agent task queue. Does it already have its own workflow/queue, or would absurd replace/complement it?
4. **MCP server (neurosys-mcp)** — request handlers are stateless; unlikely candidate, but verify.
5. **agentd** — manages agent lifecycle; compare absurd's worker model to agentd's reconciliation loop.

**Research questions:**
- Does absurd's Python SDK exist and is it usable? (README says "unpublished")
- What's the operational overhead (schema migrations, `absurdctl`, `habitat` web UI)?
- Is there a NixOS module or packaging path for absurd?
- What's the license?
- For each candidate: what specific failure modes does absurd fix? What's the status quo resilience?

**Deliverable:** A research report with a per-component adoption table (ADOPT / DEFER / REJECT + rationale) and, if any component is ADOPT, a concrete integration sketch (where absurd runs, how Postgres connection is wired via sops-nix, what steps the workflow has).

Plans:
- [x] 55-01: Research conclusion — per-component evaluation complete (4 REJECT, 1 DEFER). Decision recorded in STATE.md. No NixOS changes.

### Phase 56: Voice Interface Research — Low-Latency Parts Assistant

**Goal:** Research and compare approaches for a natural, low-latency voice assistant with full access to neurosys/Parts context. Evaluate options usable from Android and Mac. Produce a concrete recommendation + implementation plan (Phase 57 skeleton).

**Depends on:** Phase 55

**Context:**
- Phase 45 already built a neurosys MCP server (FastMCP, Streamable HTTP, OAuth 2.1, Tailscale Funnel)
- Current candidate: Claude Android built-in voice mode + MCP → neurosys (works today, unknown latency/UX)
- ClawdTalk pattern: Phone → Telnyx STT → ClawdTalk Server → WebSocket → OpenClaw Gateway → Agent → TTS → Phone (PSTN-based)
- Parts is the personal agent runtime on neurosys; voice-enabling it is preferred over a standalone bot

**Research questions:**
1. Latency of Claude Android voice mode + MCP — is TTFB acceptable for natural conversation?
2. ClawdTalk/Telnyx vs MCP approach — PSTN vs app, latency, context persistence, tools access
3. WebRTC-native approaches (LiveKit Agents, Daily RTVI, Vapi, Bland AI) connecting to Parts/OpenClaw gateway
4. Does Claude have a Realtime API? If not, best STT+LLM+TTS pipeline for Claude-based agents
5. Simplest path to Parts-aware voice on Android + Mac with <500ms perceived latency
6. Required neurosys infrastructure changes for the winning approach

**Success Criteria:**
1. All major approaches documented with latency estimates, complexity scores, neurosys integration requirements
2. Clear winning approach identified with justification
3. Phase 57 implementation skeleton drafted (ready to plan/execute)
4. Required neurosys additions identified (ports, sops secrets, new modules)

**Plans:** 1 plan

Plans:
- [x] 56-01: Voice interface research compiled into docs/VOICE-RESEARCH.md. 5 approaches evaluated, LiveKit Agents recommended. Phase 57 skeleton drafted. Decision recorded in STATE.md.

### Phase 57: OVH Re-bootstrap as neurosys-dev

**Goal:** Re-bootstrap the OVH VPS (135.125.196.143) with NixOS from fresh Ubuntu 25. Rename hostname from neurosys-prod to neurosys-dev. Configure as a dedicated dev agent workstation — no service modules (lobster farm, conway, parts stay on Contabo). Verify SSH, NixOS boot, Tailscale, and agent tooling.
**Depends on:** Phase 50 (current config must be coherent)
**Success Criteria** (what must be TRUE):
  1. `bootstrap-ovh.sh` completes successfully against the fresh Ubuntu 25 install
  2. NixOS boots on OVH VPS with hostname `neurosys-dev` and joins the tailnet
  3. Agent tooling (claude-code, codex, bubblewrap sandbox) works on the VPS
  4. Service modules not needed for dev agents are excluded from the OVH host config
  5. `nix flake check` passes for both neurosys and ovh configurations
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 57 to break down)

### Phase 58: Agent Canvas — Generic Visualization Service for Agents

**Goal:** Build a generic agent-driven visualization canvas service. Agents push Vega-Lite charts and markdown panels via REST API. Persistent panels, real-time SSE updates, GridStack.js drag-and-drop layout. Port 8083, Tailscale-only. Single NixOS module (modules/canvas.nix) following writePython3Bin stdlib-only pattern.
**Depends on:** Phase 61
**Research:** Complete (58-RESEARCH.md — custom minimal canvas recommended, Grafana/Observable/Evidence/Panel disqualified)
**Plans:** 1 plan

Plans:
- [ ] 58-01-PLAN.md -- Agent Canvas Service: module, Python server (REST API + SSE), HTML/JS client (Vega-Lite + GridStack + marked), systemd service, networking + host integration, eval checks

### Phase 59: Logseq PKM Agent Suite

**Goal:** Create a private repo (`logseq-agent-suite`) and a matching neurosys private overlay component that turns the Logseq PKM vault (already in Syncthing) into an agent-accessible knowledge interface. Deliverables: (1) a documented Datalog query library and Logseq API helpers for navigating/manipulating the graph, (2) agent instruction files (system prompts / SOUL.md) covering todo triage, graph maintenance, and review flows, (3) a lightweight neurosys NixOS module exposing the vault path and optional tooling to agentd agents, and (4) a parts-agent interface so parts services can read/write the personal graph for task tracking and knowledge retrieval. The Logseq vault lives in the Syncthing folder already managed by neurosys.
**Depends on:** Phase 57
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 59 to break down)

### Phase 60: Dashboard DM Pairing & Backup Decrypt Guide

**Goal:** Ensure the neurosys homepage dashboard links to a self-hosted guide page that walks through two workflows: (1) pairing each DM bridge service (Signal, WhatsApp, Telegram via mautrix) — QR codes, auth flows, verification steps, and (2) uploading & decrypting message backups for historical import into the Matrix bridge / Spacebot LanceDB. Lightweight static or server-rendered page behind Tailscale, linked from the homepage Services section.
**Depends on:** Phase 59
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 60 to break down)

### Phase 61: Nix-Derived Dynamic Dashboard — COMPLETE

**Goal:** Replace homepage-dashboard with a Nix-derived dynamic dashboard. NixOS option schema `services.dashboard.entries` (attrsOf submodule), build-time JSON manifest via `builtins.toJSON`, Python HTTP server (stdlib only, `writePython3Bin`) serving dark-theme HTML + `/api/status` for live systemd status. All public modules annotated with dashboard entries. Port 8082, DynamicUser systemd service. Old homepage.nix removed.
**Depends on:** None
**Plans:** 2 plans (complete)

Plans:
- [x] 61-01: Dashboard Module + Annotations + Frontend (Codex)
- [x] 61-02: Port swap to 8082, remove old homepage

### Phase 62: LLM Cost Tracking & Display

**Goal:** Track LLM API costs at the secret proxy level so all inference usage across parts, Conway automaton, and other agents is captured in one place. Per-request cost estimation from token counts and model pricing tables. Daily/weekly/monthly aggregation stored in SQLite or Postgres. Expose via MCP tool (`llm_cost_summary`) for querying from Claude Android or parts. Optionally display inline on parts agent Telegram responses (e.g., `~$0.03` after each reply).

**Depends on:** Phase 22 (secret proxy deployed)

**Key areas:**
1. **Request-level tracking** — intercept OpenRouter/Anthropic responses at the proxy, extract `usage` fields, calculate cost using model pricing table
2. **Aggregation** — daily/weekly/monthly rollups, per-model and per-caller breakdown
3. **MCP tool** — `llm_cost_summary` with time range and granularity parameters
4. **Parts integration** — parts displays per-response cost in Telegram (lightweight — just reads the cost header/field from the proxied response)

**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 62 to break down)

### Phase 63: Google OAuth + Gmail/Calendar MCP Tools

**Goal:** Add Google OAuth 2.0 to the neurosys MCP server so Gmail and Google Calendar are accessible as MCP tools alongside existing HA, Matrix, and Logseq integrations. OAuth callback via Tailscale Funnel (already set up for MCP). Token storage with automatic refresh. Gmail tools cover read, search, draft, send, and archive. Calendar tools cover list events, search, free/busy, create, update, and delete. Parts connects to these via its MCP client layer (Phase 45 pattern) with approval gating — sending email and creating events with attendees require `contact_human` approval.

**Depends on:** Phase 45 (MCP server deployed with Tailscale Funnel)

**Key areas:**
1. **OAuth 2.0 flow** — Google Cloud Console project, OAuth consent screen, credential storage in sops-nix, callback endpoint on MCP server, token persistence + refresh
2. **Gmail MCP tools** — `gmail_read`, `gmail_search`, `gmail_draft`, `gmail_send`, `gmail_archive` (mirrors parts-old surface but as MCP tools)
3. **Calendar MCP tools** — `calendar_list`, `calendar_search`, `calendar_free_busy`, `calendar_create`, `calendar_update`, `calendar_delete`
4. **Parts integration** — MCP client wraps Gmail/Calendar tools with parts approval gate (`gmail_send` = `contact_human`, reads = `observe`)

**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 63 to break down)

### Phase 64: Repo Layout Simplification — rename hosts, remove dead code, flatten imports, merge modules

**Goal:** Simplify repo structure for rapid iteration
**Depends on:** Phase 63
**Plans:** 2 plans (COMPLETE 2026-03-04)

Plans:
- [x] 64-01-PLAN.md -- Remove dead code (beads, logseq, docs, spacebot port)
- [x] 64-02-PLAN.md -- Structural refactoring (rename hosts, flatten imports, merge/inline modules)

### Phase 65: Open Source Cleanup (v2) — minimal forkable skeleton ✅ (2026-03-04)

**Goal:** Strip the public repo down to a minimal, forkable skeleton for agentic NixOS servers. The public repo should contain only the core infrastructure (security hardening, agent sandboxing, secret proxy, deployment, backup, dashboard framework) and clear overlay extension points. All personal service modules move to the private overlay. README gains an "Example Use Cases" section with generic descriptions of real deployments so users see what's possible without exposing the exact private setup.

**Depends on:** Phase 64 (repo layout simplification)

**Key areas:**
1. **Remove personal modules from public repo** — automaton.nix, matrix.nix, openclaw.nix, dm-guide.nix, home-assistant.nix all move to private overlay (they're already overridden there, so this is just deleting the public copies)
2. **Trim host imports** — hosts/services/default.nix and hosts/dev/default.nix should only import core modules; personal modules imported by private overlay
3. **Clean impermanence.nix** — remove personal service state dirs (openclaw, mautrix, automaton, matrix-conduit); leave only core persist paths. Add comments showing how to add service-specific paths
4. **Clean flake.nix** — drop openclaw and neurosys-mcp package exports; keep deploy-rs only
5. **Remove home/agentic-dev-base.nix** — personal repo reference; inline the pattern as a comment in home/default.nix if useful
6. **Clean networking.nix internalOnlyPorts** — remove personal service ports; keep only core ports (dashboard, syncthing GUI, secret proxy). Add comment showing how to add ports for private services
7. **README "Example Use Cases"** — document generic versions of real deployments: autonomous AI agents (automaton pattern), chat bridge hub (matrix + mautrix pattern), home automation (HA + ESPHome pattern), multi-instance SaaS (openclaw fleet pattern), LLM cost tracking (secret proxy extension). Each with enough detail to be a starting point, none exposing exact private config
8. **README cleanup** — update module table (remove personal modules), verify all sections match slimmed-down repo

**Success Criteria** (what must be TRUE):
  1. `nix flake check` passes with only core modules
  2. No personal service names (automaton, openclaw, matrix, dm-guide, home-assistant) in any public module
  3. `grep -r "conway\|openclaw\|mautrix\|dm-guide" modules/` returns zero matches
  4. README has "Example Use Cases" section with at least 4 generic examples
  5. Private overlay still works (imports moved modules from its own tree)
  6. hosts/services/default.nix imports only core modules (base, boot, networking, users, secrets, docker, syncthing, agent-compute, secret-proxy, impermanence, restic, dashboard, nginx)
  7. impermanence.nix contains no personal service paths

**Plans:** 3 plans

Plans:
- [x] 65-01-PLAN.md -- Move personal modules and packages to private overlay (wave 1)
- [x] 65-02-PLAN.md -- Clean core modules: remove personal service references (wave 2, depends on 65-01)
- [x] 65-03-PLAN.md -- README update: example use cases and module table cleanup (wave 3, depends on 65-02)

### Phase 66: Secret Placeholder Proxy Module — Generic NixOS Secret Injection for Sandboxed Agents

**Goal:** Extract the Phase 22 secret-proxy trick into a generic, well-tested, maximally nix-native NixOS module. Research-heavy: survey ironclaw, gondolin (earendil-works), and all relevant NixOS/nixpkgs secret management approaches to take the best ideas. The module should: (1) let sandboxed agents use placeholder tokens while a proxy transparently re-injects real secrets, (2) tie each secret to a list of allowed destination domains so exfiltration is blocked even if the agent is prompt-injected, (3) decouple from specific secret backends (sops, agenix) and sandbox implementations (bwrap) where possible — surface any mandatory coupling in review, (4) be seamless, performant, and secure — "just work" with minimal configuration. The agent should be able to do everything as if it had real secrets, but never see them.
**Depends on:** Phase 22 (existing secret-proxy), Phase 65
**Plans:** 3 plans (completed 2026-03-07)

Plans:
- [x] 66-01-PLAN.md -- Rust `secret-proxy` binary + Nix package + flake export (completed 2026-03-07)
- [x] 66-02-PLAN.md -- generic reusable NixOS module (`services.secretProxy.services`) + networking cleanup (completed 2026-03-07)
- [x] 66-03-PLAN.md -- private overlay consumer migration + eval/live test updates (completed 2026-03-07)

### Phase 67: Review and document the secret proxy — read all source, tests, and module code; produce an executive summary of key design features, limitations, and improvement areas

**Goal:** Produce `docs/secret-proxy-architecture.md` — a consumer-facing executive summary of the secret-proxy design (8 features, 10 limitations, test coverage gaps, and 7 improvement areas) for anyone adopting the neurosys template.
**Depends on:** Phase 66
**Plans:** 1 plan (completed 2026-03-07)

Plans:
- [x] 67-01-PLAN.md -- architecture doc (docs/secret-proxy-architecture.md)

### Phase 68: Extract secret-proxy into standalone nix-secret-proxy flake

**Goal:** Extract the Rust secret-proxy binary + NixOS module from neurosys into a standalone public flake at `/data/projects/nix-secret-proxy`, then migrate both the public neurosys repo and the private-neurosys overlay to consume it as a flake input rather than carrying inline source code.
**Depends on:** Phase 67
**Plans:** 3 plans (completed 2026-03-09)

Plans:
- [x] 68-01-PLAN.md -- Standalone nix-secret-proxy flake creation (wave 1)
- [x] 68-02-PLAN.md -- neurosys consumes nix-secret-proxy as flake input (wave 2)
- [x] 68-03-PLAN.md -- private-neurosys migrates to nix-secret-proxy via follows (wave 3)

### Phase 69: OVH Dev Environment Migration

**Goal:** Migrate daily development workflow from acfs (local machine) to OVH VPS (neurosys-dev). OVH becomes the primary dev host with all project repos, agent sandbox tooling, and secret-proxy for dev agents. Contabo keeps running services (HA, claw-swap, Matrix, MCP, etc.). Success: sandboxed Claude Code session works on OVH, acfs goes unused.
**Depends on:** Phase 66
**Plans:** 3 plans (completed 2026-03-10)

Plans:
- [x] 69-01: private-neurosys ovhModules — secret-proxy-dev + per-host clone scripts (wave 1)
- [x] 69-02: Deploy to OVH; populate sops secrets; verify acceptance test (wave 2)
- [x] 69-03: Deploy infrastructure — `--node all` parallel deploy, skill update, eval/live tests (wave 3)

### Phase 70: Deployment Lockout Prevention ✓

**Goal:** Make it structurally impossible for a normal deploy to permanently break remote access. Cover: (1) OOB recovery runbook — Contabo KVM console + OVH rescue mode documented as a 5-minute procedure; (2) break-glass emergency SSH key — hardcoded in users.nix independently of sops-managed keys, so a sops failure can never lock out root; (3) strengthened pre-deploy assertions — catch more lockout scenarios (sshd not in PATH, impermanence mount races, Tailscale auth key expiry, empty authorized_keys after sops failure); (4) SSH canary systemd timer — runs every 5 minutes post-deploy, confirms inbound SSH works from loopback, triggers nixos-rebuild --rollback if it fails three times consecutively; (5) hardened watchdog reliability in deploy.sh — ensure nohup watchdog survives systemd activation reliably and verify rollback path; (6) NixOS VM test — `nixos-test` that activates the config in a VM and asserts SSH is reachable before any deploy touches prod. Goal: even a broken agent-authored config cannot strand the server.
**Depends on:** Phase 69
**Plans:** 3 plans (all complete)

Plans:
- [x] 70-01: OOB runbook + break-glass SSH key + strengthened assertions
- [x] 70-02: SSH canary + hardened deploy watchdog
- [x] 70-03: NixOS VM SSH integration test

### Phase 71: Secret Proxy — Reference Documentation & Issue Audit ✓

**Goal:** Transform `nix-secret-proxy` into a canonical reference for the "API key placeholder substitution proxy" pattern. The NixOS module remains the primary concrete example, but the repo gains thorough conceptual documentation making the pattern adoptable by non-NixOS projects (Docker, systemd, bare-metal, CI). No code changes this phase — audit and document only.

**Attribution:** The placeholder-proxy pattern was independently described by Stanislas Polu in his February 2026 post "Netclode: Self-Hosted Cloud Coding Agent" (https://stanislas.blog/2026/02/netclode-self-hosted-cloud-coding-agent/#secret-proxy-api-keys-never-enter-the-sandbox). His implementation (Netclode) adds HTTPS MITM + ServiceAccount identity validation on top; this repo's implementation is a simpler variant (HTTP-only, no caller identity check). Both the README and architecture doc must credit this post.

Work breaks into two tracks:

**Track A — Pattern documentation:**
- Architecture doc: what the pattern is, why it exists (credential isolation for sandboxed agents), what it protects against, what it explicitly does not protect against
- Conceptual overview diagram: sandbox → placeholder key → proxy → real key → Anthropic API
- Security model section: threat model, trust boundaries, assumptions
- Usage guide for three deployment targets: NixOS (current), Docker Compose, plain systemd — each showing how to wire secrets, configure the proxy, and set agent env vars
- Configuration reference: all knobs, their defaults, and rationale

**Track B — Real-world issue catalogue:**
Systematically enumerate every known class of issue. For each: describe the problem, classify severity (blocking / degraded / cosmetic / informational), and propose mitigation (fix / doc / accept).

Issue classes to cover:

*Streaming & protocol:*
- SSE/chunked-transfer passthrough — does Axum proxy buffer the full body before forwarding, or stream incrementally? Buffering breaks token-by-token streaming for long generations.
- HTTP/1.1 vs HTTP/2 — proxy currently HTTP/1.1 only; upstream Anthropic supports H2; downstream SDK may negotiate H2 and get a 400.
- `transfer-encoding: chunked` strip behavior — must not be forwarded to HTTP/1.1 upstream if already framed.
- Large request bodies — multimodal prompts with base64-encoded images can reach 20–50 MB; default Axum body limit is 2 MB.
- Long-timeout requests — extended thinking / tool-use chains can run 5–10 min; proxy may close the upstream connection on a short read timeout.

*Security:*
- Bind surface — if proxy binds `0.0.0.0`, it's reachable from all interfaces including public; default should be `127.0.0.1`.
- Placeholder guessability — `sk-placeholder` or short fixed strings allow an attacker with network access to forge requests using the placeholder and receive real API responses via the proxy.
- Header injection via real key value — if the real key contains CRLF or whitespace, it could corrupt the forwarded request header. Should be validated/stripped on load.
- TLS verification of upstream — reqwest default verifies; confirm this is not disabled anywhere in the build.
- SSRF via upstream URL — if upstream URL is ever runtime-configurable, an attacker could redirect the proxy to internal endpoints (metadata service, internal APIs).
- Request body logging — if debug logging is enabled, full request bodies (including prompts and user data) may be written to journald. Should warn operators.
- Replay via intercepted placeholder — a process that observes the placeholder from env vars can replay requests directly through the proxy. Mitigated by binding to loopback only.

*Library / SDK interactions:*
- Anthropic SDK key format validation — SDK v0.3+ validates that `ANTHROPIC_API_KEY` matches `sk-ant-api03-*` before sending. A random placeholder will cause client-side rejection before the request reaches the proxy. Operators must use a regex-valid placeholder or disable validation.
- OpenAI-compat clients — Anthropic's OpenAI-compatible endpoint uses `Authorization: Bearer <key>`, not `x-api-key`. The proxy only substitutes `x-api-key`. Agents using the OpenAI SDK against Anthropic's compat URL bypass the proxy entirely.
- SDK retry behavior — on 429/503 the SDK auto-retries with exponential backoff. Proxy must not swallow retry-after headers.
- `anthropic-beta` and custom headers — proxy must forward all non-auth headers verbatim; any allowlist-based forwarding would silently drop beta feature flags.

*Operational:*
- Key rotation — requires service restart to reload the secret from disk. No hot-reload. Acceptable for declarative NixOS (sops-nix activation), but blocks zero-downtime rotation.
- No health endpoint — no `/health` or `/ready` route; operators cannot health-check the proxy without making a real API call.
- Opaque upstream errors — if the proxy can't reach Anthropic, raw TCP errors may propagate instead of a structured JSON error in Anthropic's error format, confusing SDK error handling.
- Graceful shutdown — SIGTERM during an active streaming response; proxy should drain in-flight requests before exiting.
- Multi-agent rate limiting — all sandboxed agents share one real API key, so one agent's burst consumes rate limit headroom for all others. No per-agent quota enforcement.
- No per-request audit trail — cannot attribute a given API call to a specific sandbox or agent invocation from proxy logs alone.
- Proxy chaining — environments behind a corporate HTTP proxy require `HTTP_PROXY`/`HTTPS_PROXY` to be set; reqwest honors them but this is undocumented.
- Docker/container networking — agents in Docker containers cannot reach `127.0.0.1` on the host; need `host.docker.internal` or explicit bind to the Docker bridge IP.
- IPv6 — bind and upstream connection behavior on IPv6-only or dual-stack hosts is untested.

**Depends on:** Phase 68
**Plans:** 2 plans (completed 2026-03-10)

Plans:
- [x] 71-01: Pattern documentation — architecture doc, security model, three-target usage guide, config reference
- [x] 71-02: Issue catalogue — structured document covering all issue classes above, each with severity + proposed mitigation

### Phase 72: Secret Proxy — Issue Resolution & Hardening ✓

**Goal:** Address every issue catalogued in Phase 71. For each issue: either implement a fix in `nix-secret-proxy`, or write an explicit "known limitation" entry with rationale for why the current behavior is acceptable. After this phase the proxy is suitable for most common simple use-cases, has a clean pedagogical implementation, and documents its own limits honestly.

Implementation fixes (likely):
- **Streaming** — integration test for SSE passthrough; fix if body is buffered
- **Request body size** — raise Axum body limit to 100 MB (covers multimodal); document the knob
- **Upstream timeout** — add configurable timeout, default 10 min for extended thinking; expose as config option
- **Bind address** — change default from `0.0.0.0` to `127.0.0.1`; add `bind` config field
- **Health endpoint** — `GET /health` → `200 OK` with `{"status":"ok"}`
- **Structured upstream errors** — catch connection errors and emit `{"error":{"type":"proxy_error","message":"..."}}` in Anthropic error format
- **Header injection** — validate real key on startup: strip whitespace, reject CRLF
- **Graceful shutdown** — verify Axum's shutdown hook drains in-flight streaming responses; add if missing
- **Retry-after passthrough** — ensure `retry-after` and `x-ratelimit-*` headers are forwarded verbatim

Documentation / known-limitation entries (for issues that won't be fixed in code):
- **SDK key format** — document: use a regex-valid placeholder (e.g. `sk-ant-api03-placeholder-...`); or patch the SDK check; note which SDK versions are affected
- **OpenAI-compat** — document: proxy only covers `x-api-key`; for OpenAI-compat endpoint, run a second proxy instance or add `Authorization: Bearer` substitution support (future)
- **Key rotation** — document: service restart required; acceptable for NixOS; hot-reload is future work
- **Rate limiting** — document: one key = shared quota; use per-consumer keys in production multi-agent deployments
- **Audit trail** — document: no per-agent attribution from proxy alone; rely on Anthropic's usage dashboard or add structured request logging (future)
- **Placeholder guessability** — document: generate a cryptographically random placeholder (e.g. `openssl rand -hex 32`); never use well-known strings
- **SSRF** — document: upstream URL is static config only; never accept it from user input or env at runtime
- **Docker networking** — document: bind to `0.0.0.0` or Docker bridge IP; use `ANTHROPIC_BASE_URL=http://host.docker.internal:<port>`
- **Corporate proxy** — document: set `HTTP_PROXY`/`HTTPS_PROXY` in the proxy's systemd/NixOS service env
- **IPv6** — document: untested; bind to `::1` for loopback-only IPv6; report issues

End state: `nix-secret-proxy` README serves as the definitive reference for the pattern. Someone adopting it for a non-NixOS project can read the docs, understand the security model, identify which issues apply to their deployment, and wire it up confidently.

**Depends on:** Phase 71
**Plans:** 3 plans

Plans:
- [x] 72-01: Implementation fixes — configurable bind, upstream timeout, graceful shutdown, JSON 502, /health endpoint, sk-ant-api03-placeholder default
- [x] 72-02: Documentation updates — known-issues.md updated with fix status, deployment docs updated for bind/health
- [x] 72-03: Integration test suite — 8 tests covering all fixes (streaming, body size, 502 shape, health, bind, graceful shutdown)

### Phase 72.1: OVH Secret Proxy — Deploy Phase 72 & Live Acceptance Tests (INSERTED)

**Goal:** Deploy Phase 72 nix-secret-proxy updates to OVH and verify live acceptance behavior before sandbox enforcement rollout.
**Depends on:** Phase 72
**Plans:** 2 plans

Plans:
- [x] 72.1-01: Add OVH live BATS acceptance tests (/health, host reject 403, service user, journal errors, opt-in e2e proxy)
- [ ] 72.1-02: Push/bump lock chain, deploy OVH, run live tests and manual e2e verification

### Phase 73: OVH Agent Sandbox Enforcement

**Goal:** Ensure dev agents running on OVH are always sandboxed by default. Sandboxed execution should be the easy path, and unsandboxed execution should require an explicit override with a visible warning. Covers: (1) default agent-launch aliases (`claude`, `codex`, etc.) that always invoke the bubblewrap sandbox wrapper on OVH; (2) shell-level interception so bare `claude` or `codex` in an interactive shell runs sandboxed — no unsafe shortcut; (3) a warning or hard block when `--no-sandbox` is passed without an explicit override env var (`AGENT_ALLOW_NOSANDBOX=1`) or flag; (4) audit logging of sandboxed vs unsandboxed invocations to a persistent log file; (5) NixOS `agent-compute.nix` changes declaratively enforcing this on OVH (not Contabo, which already has agentd); (6) verify secret-proxy placeholder key is wired into sandboxed sessions so agents can reach the Anthropic API through the proxy without seeing the real key.
**Depends on:** Phase 69
**Plans:** 2 plans

Plans:
- [x] 73-01: Module + OVH enablement + eval checks (`agent-sandbox-ovh-enabled`, `agent-sandbox-module-has-bwrap`)
- [x] 73-02: OVH live BATS wrapper verification + eval check `agent-audit-dir`

### Phase 74: Open Source Release Prep v3
**Goal**: Public repo is clean, minimal, impressive, and ready for strangers to discover. Zero personal identifiers, zero dead code, maximum signal-to-noise ratio. Git history reset.
**Depends on**: None (can run independently)
**Success Criteria** (what must be TRUE):
  1. `grep -r "dangirsh\|worldcoin\|161.97.74\|135.125.196\|100.104.43\|100.113.72" modules/ home/ scripts/ src/ docs/ README.md flake.nix` returns zero matches
  2. Every file in the repo justifies its existence — no stubs, no empty modules, no unused code
  3. README gives a stranger an immediate "this is cool, I want to fork this" reaction in <30 seconds
  4. `nix flake check` passes after all changes
  5. Git history is clean (single squashed commit or fresh init)
  6. Private overlay continues to work with the cleaned public repo
**Plans**: 3 plans

Plans:
- [x] 74-01: Identifier scrub + flake input fix (wave 1, autonomous)
- [x] 74-02: Dead code removal + README polish (wave 1, autonomous)
- [x] 74-03: Git history reset + final verification (wave 2, user confirmed force push)

### Phase 75: Dashboard UI Modernization ✓ (2026-03-12)

**Goal:** Modern, sleek UI pass over the homepage dashboard. Keep it compact and highly functional. Reduce redundant/duplicate visual info. Lean into on-demand expanding sections for detail. High information density with a clean, modern look.
**Depends on:** Phase 74
**Plans:** 2 plans

Plans:
- [x] 75-01: Core UI Modernization (wave 1, autonomous) — compact rows, SVG icons, collapsed modules, status summary bar, pulse animations
- [x] 75-02: Navigation Tabs + Cost Page Integration (wave 2, autonomous) — tab bar, inline cost table, costHtml removal, /cost redirect

### Phase 76: Code Review Integration + README Rewrite + Simplicity Pass
**Goal**: Meticulously address all 19 findings from `neurosys-code-review.md`, integrate the updated README from `neurosys-readme-rewrite.md`, and do a final simplicity/minimalism/concision pass. Three tiers: (1) trust repair — self-contained flake, sandbox PWD fix, sandbox --clearenv, doc/test alignment; (2) structural simplification — network model, persistence cleanup, deploy.sh generics, dashboard/canvas split, operator/base separation; (3) hardening — privilege model split, opt-in nix daemon socket, port policy single source of truth, egress documentation.
**Depends on:** Phase 75
**Success Criteria** (what must be TRUE):
  1. `nix flake check` passes on a clean clone (no local path inputs)
  2. Sandbox refuses execution from `/`, `/home`, or any path outside allowed project root
  3. Sandbox uses `--clearenv` with explicit allowlist — no secret-bearing env vars leak
  4. Every claim in README and CLAUDE.md is verifiable against the current public repo
  5. Tests pass against the public repo without private overlay
  6. No private-overlay-specific assertions in public tests
  7. `docker0` not in default `trustedInterfaces`; dashboard/canvas/syncthing bind `127.0.0.1`
  8. README replaced with `neurosys-readme-rewrite.md` content (adapted for changes)
  9. Final simplicity pass: no dead code, no overclaiming, no unnecessary complexity
**Plans**: 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 76 to break down)

### Phase 77: Unified Design System — Homogenize UI across all neurosys web apps — COMPLETE (2026-03-12)

**Goal:** Define a canonical neurosys design system (CSS custom properties with `ns-` prefix) in the public repo, migrate Dashboard to use it, and align Conway Dashboard + Logseq Triage dark mode to the same palette. Canvas (not on main) and DM Guide (private overlay) adopt later.
**Depends on:** Phase 76
**Plans:** 2/2 complete

Plans:
- [x] 77-01: Define shared theme and migrate Dashboard (wave 1)
- [x] 77-02: Migrate Conway Dashboard and Logseq Triage to neurosys palette (wave 2)

### Phase 78: Unified Agent Context Layer — neurosys-context

**Goal:** Consolidate all agent-facing data/context services into a single `neurosys-context` flake repo. Today these services are scattered across 3 repos and 6+ NixOS modules with no unified access control, auditing, or monitoring. This phase merges them under one roof so that future guardrails (rate limits, PII filtering, audit logging, access policies) can be applied in a single place.

**Services to consolidate:**
- **context-bot** (`/data/projects/context-bot/`) — FastMCP personal context engine (doc ingest, search, entities, whisper transcription). Already has `NeurosysClient` integration for messaging. This becomes the **core** of neurosys-context.
- **logseq-triage** (private `logseq-triage.nix`, code in `logseq-agent-suite/`) — Logseq todo triage web UI (port 8888)
- **logseq-sync-merger** (private `logseq-sync-merger.nix`) — Syncthing conflict auto-merger timer
- **x-link-fetcher** (private `x-link-fetcher.nix`, code in `logseq-agent-suite/`) — X/Twitter content fetcher (port 8889)
- **syncthing** (public `syncthing.nix` + private override) — file sync substrate
- **matrix ecosystem** (private `matrix.nix` + `dm-guide.nix`) — Conduit + 3 mautrix bridges + DM login helper
- **neurosys-mcp** (private `neurosys-mcp.nix`) — existing MCP server with HA/Matrix/Google integrations

**Architecture direction:**
- Extend context-bot into the unified MCP server (absorb neurosys-mcp's HA/Matrix/Google tools). context-bot already uses FastMCP with proper lifespan, auth, security filtering, and a plugin-style tool registration pattern — ideal hub.
- logseq-triage + x-link-fetcher + sync-merger become sub-services managed by the neurosys-context flake (their code moves from `logseq-agent-suite/` into the new repo).
- syncthing + matrix remain NixOS-native services but get dashboard regrouped under a "Context" category.
- New `neurosys-context` flake exports a NixOS module consumed by the private overlay (same pattern as `nix-secret-proxy`).
- Dashboard gains a top-level "Context" category with all consolidated services as sub-entries.

**Depends on:** None (can run independently, but benefits from Phase 77 design tokens for dashboard category)
**Success Criteria** (what must be TRUE):
  1. `neurosys-context` repo exists as a flake with NixOS module export
  2. context-bot is the unified MCP server — agents get documents, messages, calendar, logseq todos, x-link content, and HA state through a single MCP endpoint
  3. Dashboard shows "Context" top-level category with all services grouped
  4. Private overlay imports `neurosys-context` flake input and enables the module
  5. All existing service functionality preserved (no regressions in logseq-triage, x-link-fetcher, sync-merger, matrix)
  6. Single audit log / access point exists for future guardrail installation
  7. `nix flake check` passes on both public neurosys and neurosys-context repos
**Plans**: 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 78 to break down)

### Phase 79: Public Repo Showcase Review

**Goal:** Review both public and private repos to identify features, patterns, and modules from the private overlay that could strengthen the public repo as an impressive, complete NixOS foundation template. Examples: Cachix integration, service patterns, dashboard config, deployment patterns. Suggest what to move, extract, or better advertise.
**Depends on:** None
**Plans:** 2 plans

Plans:
- [x] 79-01-PLAN.md -- README + docs showcase improvements (public template positioning, private overlay guide, service template guide, deploy post-hook example)
- [x] 79-02-PLAN.md -- Follow-on module/config improvements from research findings

### Phase 80: Integrate nono — replace nix-secret-proxy and bwrap with nono, update README

**Goal:** Replace nix-secret-proxy and bubblewrap with nono as the sole sandbox/credential injection layer. Update all configuration, modules, and README to reflect nono-only security model. Remove all bwrap references.
**Depends on:** None (can run independently)
**Success Criteria** (what must be TRUE):
  1. nix-secret-proxy flake input and all references removed from neurosys flake and modules
  2. bubblewrap/bwrap sandbox wrappers replaced by nono equivalents in all agent tooling
  3. All NixOS modules updated: no bwrapArgs, no secret-proxy service references
  4. README updated to describe nono-based security model (credential injection, sandboxing, network filtering)
  5. `nix flake check` passes with no remaining nix-secret-proxy or bwrap references
  6. Agent tooling (claude, codex, opencode, etc.) launches correctly through nono sandbox
  7. Secrets reach agents via nono injection — no plaintext env leakage verified
**Plans**: 2 plans

Plans:
- [x] 80-01-PLAN.md — Public repo nono-only cleanup (remove nix-secret-proxy, update modules/tests/docs)
- [x] 80-02-PLAN.md — Private overlay cleanup (remove nix-secret-proxy follows, migrate automaton to nono)

### Phase 81: Audit, deploy, context-bot integration, and README polish

**Goal:** Audit phases 72.1–80 for stale references, deploy both hosts (OVH then Contabo) and verify all services, integrate context-bot (personal context MCP server) as a NixOS service in the private overlay, and tighten the public README for OSS adoption (minimal, link-heavy).
**Depends on:** Phase 80
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 81 to break down)

### Phase 82: Public repo cleanup: consolidate docs into README + AGENTS.md, rm load-api-keys, minimalism pass, verify README claims

**Goal:** Consolidate docs into README + AGENTS.md, remove load-api-keys, minimalism pass, verify README claims
**Depends on:** Phase 81
**Plans:** 3 plans (3/3 complete — 2026-03-13)

Plans:
- [x] 82-01: Remove dead code, trim stale docs and accepted risks
- [x] 82-02: Create AGENTS.md — single agent quick-start reference
- [x] 82-03: Update README, fold recovery docs, delete docs/ directory

### Phase 83: Meticulous security review: all modules, nono profile, credential flow, firewall assertions, systemd hardening, accepted risks audit

**Goal:** Comprehensive security audit of all public repo modules, nono sandbox profile, credential injection chain, firewall assertions, and systemd hardening. Produce structured findings, fix actionable issues, and update accepted risks in CLAUDE.md.
**Depends on:** Phase 82
**Success Criteria** (what must be TRUE):
  1. Every module in modules/ reviewed for port exposure, secret handling, systemd hardening, and file permissions
  2. Nono neurosys profile filesystem allow-list verified for minimality
  3. Full credential flow traced from sops to sandboxed child — no leaks identified or all leaks documented as accepted risks
  4. internalOnlyPorts list verified complete against all services in the repo
  5. All networking.nix assertions validated for correctness and completeness
  6. Systemd hardening added to services that were missing it (especially restic-status-server)
  7. CLAUDE.md accepted risks section is current and accurate after Phase 80-82 changes
  8. nix flake check passes after all changes
**Plans:** 3 plans

Plans:
- [ ] 83-01: Module-by-module security audit (all .nix files, systemd hardening matrix)
- [ ] 83-02: Nono profile, credential flow, and firewall assertions deep-dive
- [ ] 83-03: Fix issues, update accepted risks, validate with nix flake check

### Phase 84: Address critical Phase 83 audit findings: break-glass key, nono .ssh verify, gemini proxy-credential fix, Syncthing discovery port, secrets.nix permissions review ✓ (2026-03-14)

**Goal:** Fix six deferred security findings from Phase 83 audit: distinct break-glass placeholder key + eval check, gemini proxy-credential CLI flag, Syncthing discovery port cleanup, ssh-canary systemd hardening, and nono profile deny entries for sensitive home subdirectories.
**Depends on:** Phase 83
**Plans:** 2/2 complete

Plans:
- [x] 84-01: Public repo fixes (break-glass key, gemini flag, syncthing port, ssh-canary hardening) + eval checks
- [x] 84-02: Nono profile deny entries for .ssh, .bash_history, .config/syncthing, etc. (live verification pending deploy)

### Phase 85: Service Type Framework

**Goal:** Introduce a lightweight service classification system that encodes neurosys's recurring patterns — networking posture, host assignment, sandboxing, systemd hardening, and dashboard integration — into a small set of named service types. Refactor existing modules to declare their type, so invariants are enforced by construction rather than by convention.

**Depends on:** Phase 84

**Service Types (initial taxonomy):**
1. **`prod-web`** — Public-facing web services (e.g., claw-swap, dangirsh.org). Defaults: nginx reverse proxy + ACME TLS, ports 80/443 allowed, systemd hardening (DynamicUser, ProtectSystem=strict, CapabilityBoundingSet), services host (Contabo). Dashboard category: "Services".
2. **`dev-agent`** — AI coding agents (e.g., Claude Code, Codex in nono sandbox). Defaults: nono sandbox with Landlock, credential proxy, audit logging, dev host (OVH), no open ports, `AGENT_ALLOW_NOSANDBOX` gate. Dashboard category: "Agents".
3. **`internal`** — Tailscale-only services (e.g., dashboard, syncthing GUI, restic-status, home-assistant). Defaults: bind 127.0.0.1, port added to `internalOnlyPorts`, `openFirewall = false`, `trustedInterfaces = ["tailscale0"]`, systemd hardening. Dashboard category: "Internal".
4. **`system`** — Infrastructure plumbing that doesn't serve user traffic (e.g., restic backup, ssh-canary, impermanence, sops-nix). Defaults: no listening port, no dashboard entry (or "System" category), both hosts. Not user-configurable — these are the substrate.

**Properties per type:**
- `defaultHost`: `"services"` | `"dev"` | `"both"` — which host(s) import the module by default
- `networking`: `{ openFirewall, bindAddress, internalOnly, trustedInterfaces }`
- `security`: `{ sandbox, nonoProfile, systemdHardening }` — sandbox mode, hardening preset
- `dashboard`: `{ category, icon, order }` — auto-wired dashboard entry
- `assertions`: type-specific build-time assertions (e.g., prod-web asserts nginx is enabled)

**Success Criteria** (what must be TRUE):
  1. NixOS option `neurosys.serviceType` exists with the 4 types above, each with documented defaults
  2. At least 5 existing modules annotated with their service type (docker, syncthing, restic, dashboard, agent-sandbox)
  3. Type-derived assertions catch misconfigurations at build time (e.g., internal service with openFirewall=true)
  4. README documents the service type taxonomy in a concise table
  5. `nix flake check` passes
  6. No behavior change for existing services — types encode current conventions, not new restrictions

**Plans:** 3/3 complete

Plans:
- [x] 85-01-PLAN.md -- Framework module (`modules/service-types.nix`) with registry schema, dashboard derivation, internal-only port derivation, assertions, and hardening defaults
- [x] 85-02-PLAN.md -- Migrate public service modules to `neurosys.services` declarations and wire networking assertions to registry-derived ports
- [x] 85-03-PLAN.md -- Document service type taxonomy in README/CLAUDE.md and update state tracking files

### Phase 86: Feature Abstraction Layer — core vs swappable capabilities

**Goal:** Research and design (potentially implement) an abstraction layer that separates neurosys's high-level capabilities from their specific implementations, and clearly denotes which features are core (non-swappable) vs which are swappable backends.

**Depends on:** Phase 85 (service types inform which capabilities each type needs)

**Motivation:** neurosys currently tightly couples capabilities to implementations (backup = restic+B2, sync = syncthing, sandbox = nono, secrets = sops-nix). This works well for a single-operator server. The question is whether a thin abstraction layer would provide enough value to justify its complexity — specifically by ensuring that swapping an implementation doesn't silently break invariants (impermanence paths, Tailscale-only networking, sops-nix integration).

**Proposed Capability Categories:**

*Core (non-swappable — defining characteristics of neurosys):*
- Impermanence (BTRFS subvolume rollback) — everything else depends on `/persist`
- Tailscale VPN — the internal networking model
- nftables firewall — default-deny, port assertions
- sops-nix secrets — decryption at activation time
- Declarative NixOS (flakes + home-manager) — the substrate

*Swappable capabilities (with current implementation):*
- **Backup**: restic → B2 (interface: paths, excludes, schedule, retention, impermanence-aware)
- **File Sync**: syncthing (interface: folders, devices, Tailscale-only GUI)
- **Agent Sandbox**: nono/Landlock (interface: filesystem policy, credential injection, audit log)
- **Container Runtime**: Docker (interface: oci-containers, NAT, --iptables=false)
- **Monitoring/Dashboard**: custom Python dashboard (interface: service entries, health status)

**Research Questions:**
1. Does a `neurosys.backup` interface (with `paths`, `exclude`, `schedule`, `retention`) help ensure a non-restic backend still respects `/persist`-only semantics and `--exclude-if-present .nobackup`?
2. Does a `neurosys.sync` interface help ensure a non-syncthing backend still binds GUI to 127.0.0.1 and registers in `internalOnlyPorts`?
3. Does a `neurosys.sandbox` interface help ensure a non-nono backend still injects credentials via proxy and produces audit logs?
4. Is the current module count (~16) small enough that the abstraction adds more cognitive overhead than it saves?
5. Would NixOS module `imports` + `disabledModules` in a private overlay already achieve "swappability" without a formal interface?

**Success Criteria** (what must be TRUE):
  1. Design doc produced with concrete NixOS option schemas for each proposed capability abstraction
  2. Each capability evaluated with explicit go/no-go: "worth abstracting" vs "current module is the abstraction"
  3. Core features explicitly listed and documented as non-swappable in README
  4. For each "go" capability: at least one concrete example of what a second implementation would look like and what invariants the interface enforces
  5. For each "no-go" capability: explicit reasoning why the current module is sufficient
  6. If any abstractions are implemented: `nix flake check` passes and existing behavior is unchanged

**Plans:** 3/3 complete

Plans:
- [x] 86-01-PLAN.md -- Capability interface modules (`backup.nix`, `sandbox.nix`), design doc with go/no-go analysis, eval checks.
- [x] 86-02-PLAN.md -- Migrated implementations: `backup/restic.nix`, `sandbox/nono.nix`. Old modules tombstoned. Host imports updated.
- [x] 86-03-PLAN.md -- README capability-first language, CLAUDE.md structure, core features docs, and state tracking.

### Phase 87: Pi Coding Agent Integration

**Goal:** Package pi-coding-agent (npm: `@mariozechner/pi-coding-agent`, repo: `badlogic/pi-mono`) as a Nix derivation, add nono sandbox wrapper in agent-sandbox.nix, configure OpenAI OAuth for ChatGPT Pro account, and prime with autoresearch skill (`davebcn87/pi-autoresearch`).

**Public overlay:** Nix package derivation for pi-coding-agent, sandbox wrapper in `agent-sandbox.nix`, `agent-compute.nix` entry, dashboard entry.
**Private overlay:** OpenAI OAuth credentials in sops (`secrets/ovh.yaml`), `~/.pi/agent/auth.json` config via home-manager, autoresearch skill installation.

**Depends on:** Phase 84 (sandbox fixes)
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 87 to break down)

### Phase 88: Guix Port Feasibility Study
**Goal**: Produce a definitive go/no-go recommendation on porting neurosys from NixOS to GNU Guix System, with enough detail that the decision is obvious
**Depends on**: None (research-only, can run anytime)
**Success Criteria** (what must be TRUE):
  1. Executive summary with clear recommendation (go / no-go / conditional-go)
  2. Package coverage gap analysis: every neurosys dependency mapped to Guix equivalent or flagged as missing (Docker, Tailscale, deploy-rs, sops-nix, home-manager, nono, pre-built binary packaging)
  3. Security update latency comparison (CVE response time, channel update cadence vs nixpkgs)
  4. Community health assessment (contributor count, commit velocity, corporate backing, bus factor, trajectory)
  5. Hardware compatibility verified for Contabo VPS + OVH VPS (UEFI, proprietary firmware, cloud-init)
  6. Guile Scheme ergonomics evaluated for coding agents (Claude, Codex, Pi) — training data availability, error messages, debugging story
  7. Feature parity matrix: impermanence, flake reproducibility, secret management, container/sandbox tooling, remote deployment with rollback
  8. Migration difficulty estimate (effort in phases, blockers, workarounds needed)
  9. Annoyance/limitation catalog from real-world Guix usage reports
**Plans**: 1 plan (research)

Plans:
- [x] 88-01-PLAN.md -- Guix feasibility report produced. NO-GO (immediate pivot to Guix). Feature parity matrix, migration estimate, agent authoring assessment complete.

### Phase 89: NixOS Agent Infrastructure Research

**Goal**: Survey the ecosystem for NixOS + AI agent infrastructure projects to identify patterns and tools worth adopting or studying.

**Depends on**: Phase 88 (decision to continue with NixOS rather than pivot to Guix)

**Success Criteria** (what must be TRUE):
  1. Literature search completed covering GitHub, GitLab, and relevant community forums
  2. At least 5 projects identified with commits in the last 3 months
  3. Findings report with structured comparison matrix (sandboxing, orchestration, secrets, deployment)
  4. Top 3 adoption recommendations with specific features to integrate

**Plans**: 1 plan (research)

Plans:
- [ ] 89-01-PLAN.md -- Literature search for similar projects. Focus on active repos (commits in last few weeks). Document with: project name, repo URL, last commit date, key features, relevance score (1-10), adoption recommendations.

### Phase 90: README polish — COMPLETE (2026-03-16)

**Goal:** Finish TODO section, add hyperlinks for all tools/projects mentioned, audit for personal info leaks (dangirsh, claw-swap, etc.), diff README claims against actual implementation
**Depends on:** None
**Plans:** 1 plan (1 complete)

Plans:
- [x] 90-01-PLAN.md — Scrub personal identifiers, fix broken links, update assertion counts, add missing modules/hyperlinks, modernize AGENTS.md service template

### Phase 91: Backup Abstraction Proof — borgmatic alternative

**Goal:** Implement `modules/backup/borgmatic.nix` as a second backup backend reading from `neurosys.backup.*` options, proving the capability interface works. Keep restic/B2 as default. Include borgmatic config in the repo (not imported by default — forkers opt in). Add concise README note that backup tool is swappable. Verify `nix flake check` passes with both implementations available.

**Depends on:** Phase 86 (capability interfaces)

**Success Criteria** (what must be TRUE):
  1. `modules/backup/borgmatic.nix` exists, reads `neurosys.backup.*` options, wires to borgmatic NixOS config
  2. borgmatic implementation respects all interface invariants (/persist in paths, .nobackup sentinel, status timestamp, retention)
  3. `nix flake check` passes with borgmatic module present but not imported (available for forkers)
  4. README mentions backup tool is swappable with link to borgmatic example
  5. Eval check validates borgmatic module can be imported alongside the interface without conflict

**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 91 to break down)

### Phase 92: Sandbox Abstraction Proof — bubblewrap alternative

**Goal:** Implement `modules/sandbox/bwrap.nix` as a second sandbox backend reading from `neurosys.sandbox.*` options, proving the capability interface works. Keep nono as default. Include bubblewrap config in the repo (not imported by default — forkers opt in). Add concise README note that sandbox tool is swappable. Verify `nix flake check` passes with both implementations available.

**Depends on:** Phase 86 (capability interfaces)

**Success Criteria** (what must be TRUE):
  1. `modules/sandbox/bwrap.nix` exists, reads `neurosys.sandbox.*` options, generates bubblewrap wrapper scripts
  2. bwrap implementation respects all interface invariants (credential injection, audit logging, sandbox gate, filesystem deny-by-default, project root constraint, no-sandbox opt-in)
  3. `nix flake check` passes with bwrap module present but not imported (available for forkers)
  4. README mentions sandbox tool is swappable with link to bwrap example
  5. Eval check validates bwrap module can be imported alongside the interface without conflict

**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 92 to break down)

### Phase 93: Syncthing Mesh — automatic cross-host sync for all neurosys hosts

**Goal:** Add a `neurosys.syncthing.mesh` option interface to the public repo that makes it trivial to form a syncthing mesh across all neurosys-managed hosts. The public repo provides the mechanism only — no actual device IDs or folder configuration. The private overlay uses these options to configure all real hosts with a shared `Sync` folder.

**Depends on:** None (syncthing already deployed on both hosts)

**Design sketch:**
  - **Mesh option interface** (public `syncthing.nix`): `neurosys.syncthing.mesh` option taking an attrset of `{ hostname = { deviceId, address }; }` entries. When populated, the module automatically adds all peer hosts as syncthing devices and shares configured folders with them. When empty (default), behavior is unchanged from today.
  - **Shared folders option**: `neurosys.syncthing.mesh.folders` for declaring folders shared across all mesh members (path, versioning, type). Additive with any manually configured `services.syncthing.settings.folders`.
  - **Tailscale transport**: Mesh addresses use Tailscale IPs or MagicDNS hostnames — no public discovery ports (SYNC-84-01 preserved).
  - **External device support**: Existing `devices`/`folders` config for external devices (laptops, phones) is preserved alongside mesh — mesh devices are additive.
  - **Private overlay configures**: Private overlay populates `neurosys.syncthing.mesh` with real device IDs, Tailscale addresses, and a `~/Sync` shared folder for all hosts.

**Success Criteria** (what must be TRUE):
  1. `neurosys.syncthing.mesh` option exists in public `syncthing.nix` with device registry and shared folder sub-options
  2. When mesh is populated, peer devices and shared folders are automatically wired into `services.syncthing.settings` — no manual device ID exchange needed
  3. When mesh is empty (default), module behavior is identical to today's placeholder config
  4. `nix flake check` passes
  5. Module comments document how to use the mesh options (generate device ID, add to registry, deploy)

**Plans:** 1 plan

Plans:
- [x] 93-01-PLAN.md -- Syncthing mesh option interface + eval check

### Phase 94: Capability Abstraction Critical Review

**Goal:** Critically evaluate whether the `neurosys.backup` and `neurosys.sandbox` capability abstractions (Phases 86/91/92) justify their overhead, or whether the same goals would be better served by documentation and folder structure alone. Research-only — produce a go/revert recommendation with concrete evidence.

**Depends on:** Phase 92 (both abstractions and alternative implementations must exist to evaluate)

**Bias:** Lean minimalist. The burden of proof is on the abstraction — it must demonstrably earn its keep in a ~20-module system. "It might help someday" is not sufficient.

**Questions to answer:**
1. **Overhead audit:** How many lines of indirection do the interfaces add? What is the cognitive cost for someone reading the codebase for the first time? Compare: reading `restic.nix` (old, self-contained) vs reading `backup.nix` + `backup/restic.nix` (new, split).
2. **What is actually gained?** The assertions enforce /persist and .nobackup for backup, and credential injection for sandbox. Would a forker realistically forget these without the assertions? Are the assertions catching real mistakes or guarding against hypothetical ones?
3. **Interface stability:** Try mentally swapping in a third implementation (e.g., kopia for backup, systemd-run for sandbox). Does the interface need modification, or does it hold? If it needs modification for realistic alternatives, it's not a stable abstraction — it's premature.
4. **Security analysis impact:** Does the abstraction help or hurt security review? Can an auditor understand the sandbox security model by reading sandbox.nix alone, or must they also read sandbox/nono.nix? Compare to the old single-file approach.
5. **Documentation-only alternative:** Would the same forker experience be achieved by: (a) a comment block at the top of restic.nix listing the invariants, (b) the `modules/backup/` folder structure implying swappability, (c) a section in the design doc? If yes, the NixOS option machinery is unnecessary indirection.
6. **Precedent:** Do other NixOS configuration repos (e.g., nix-community templates, hlissner/dotfiles, Mic92/dotfiles, divnix/digga) use capability interfaces, or do they just use modules directly? What does the NixOS ecosystem convention suggest?
7. **Revert cost:** If the recommendation is to revert, how much work is that? (Merge backup.nix + backup/restic.nix back into restic.nix, merge sandbox.nix + sandbox/nono.nix back into the old structure, update imports, remove borgmatic.nix and bwrap.nix or keep as standalone examples.)

**Success Criteria** (what must be TRUE):
  1. Each question above answered with concrete evidence (line counts, code examples, ecosystem survey)
  2. Clear GO (keep abstractions) or REVERT recommendation with rationale
  3. If REVERT: specific plan for what the revert looks like (which files merge, what happens to borgmatic/bwrap examples)
  4. If GO: specific list of what to simplify (unnecessary options, over-engineered assertions, etc.)

**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 94 to break down)

### Phase 95: Agent Instructions for NixOS Infrastructure Development — COMPLETE (2026-03-16)

**Goal:** Enrich agent-facing instructions with NixOS-specific development guidance
**Depends on:** Phase 94
**Plans:** 1/1 complete

Plans:
- [x] 95-01: Enriched AGENTS.md with module patterns, testing workflow, security pre-flight, sandbox awareness; created /nix-module and /nix-test skills; slimmed CLAUDE.md

### Phase 96: Fix dev-agent systemd service AccessDenied error - systematically identify which hardening setting blocks zmx/claude execution, implement proper fix maintaining system service architecture with appropriate security hardening

**Goal:** [To be planned]
**Depends on:** Phase 95
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 96 to break down)

### Phase 97: Service Types Critical Review — COMPLETE (2026-03-16)

**Goal:** Critically evaluate whether the `neurosys.services` / `service-types.nix` framework (Phase 85) justifies its overhead, or whether direct per-module dashboard entries, manual `internalOnlyPorts`, and per-service hardening would be simpler and clearer. Research-only — produce a go/simplify/revert recommendation with concrete evidence.

**Depends on:** Phase 94 (capability abstraction review establishes the evaluation methodology)

**Bias:** Lean minimalist. The burden of proof is on the framework — it must demonstrably earn its keep in a ~20-module system. "It might help someday" is not sufficient.

**Questions to answer:**
1. **Overhead audit:** How many lines does service-types.nix add? What is the cognitive cost for someone reading the codebase? Compare: old per-module `services.dashboard.entries` vs new `neurosys.services` registry.
2. **What is actually gained?** The framework derives dashboard entries, port protection assertions, and systemd hardening defaults. Would a forker realistically forget to add `internalOnlyPorts` or hardening without the auto-derivation? Are the auto-derived values catching real mistakes?
3. **Dashboard derivation value:** Is auto-generating dashboard entries from the registry meaningfully better than declaring them directly in each module? How many modules actually use it?
4. **Port protection value:** Does auto-deriving `internalOnlyPorts` from service types prevent real mistakes, or is the manual list in networking.nix clearer and more auditable?
5. **Hardening defaults value:** Do the `mkDefault` systemd hardening settings from service types actually get used, or do modules override them anyway?
6. **Precedent:** Do other NixOS configuration repos use centralized service registries, or do they declare per-module? What does the ecosystem convention suggest?
7. **Simplification path:** If parts of the framework are valuable but others aren't, what's the minimal useful subset? Could the framework be simplified rather than fully reverted?

**Success Criteria** (what must be TRUE):
  1. Each question above answered with concrete evidence (line counts, code examples, ecosystem survey)
  2. Clear GO (keep as-is) / SIMPLIFY (keep core, remove overhead) / REVERT recommendation with rationale
  3. If REVERT: specific plan for what the revert looks like
  4. If SIMPLIFY: specific list of what to cut
  5. If GO: justification that the complexity is earning its keep

**Plans:** 0 plans

Plans:
- [x] 97-01-PLAN.md — Overhead audit, value audit, ecosystem survey, REVERT recommendation

### Phase 98: Simplicity, Security & Open-Source Freshness Pass — COMPLETE (2026-03-16)

**Goal:** Combined audit pass addressing three concerns that have drifted since the last rounds (Phases 17/37/50/83). Execute the pending REVERT recommendations from Phases 94 and 97, then do a fresh line-by-line audit of all ~18 modules for simplicity, security, and public-repo cleanliness. Minimal README changes — update only what the reverts break (e.g., remove Service Types section).

**Depends on:** Phase 97 (uses its REVERT plan), Phase 94 (uses its REVERT plan)

**Scope — three workstreams:**

1. **Execute pending reverts:**
   - Phase 94 REVERT: Collapse capability abstractions — merge `backup.nix` + `backup/restic.nix` back into concrete `restic.nix`; merge `sandbox.nix` + `sandbox/nono.nix` back into concrete modules; delete alternate implementations (`borgmatic.nix`, `bwrap.nix`); update host imports and eval checks
   - Phase 97 REVERT: Delete `service-types.nix`; replace `neurosys.services` registrations with direct `services.dashboard.entries`; add manual `internalOnlyPorts` to networking.nix; remove framework eval checks; strip Service Types section from README

2. **Fresh simplicity + security audit (all modules):**
   - Line-by-line audit of all ~18 modules post-revert for dead code, over-engineering, YAGNI violations
   - Check all `@decision` annotations are still accurate and present where needed
   - Verify accepted risks in CLAUDE.md — prune stale entries (e.g., references to removed abstractions), add any new ones
   - Check for new security concerns since Phase 83 (new modules: `dev-agent.nix`, `agent-sandbox.nix`, `ssh-canary.nix`, `dashboard.nix`)
   - Verify no personal identifiers leaked back into public repo since Phase 37/90

3. **Documentation alignment:**
   - Update CLAUDE.md project structure table and conventions to match post-revert reality
   - Update AGENTS.md module patterns / service template if they reference `neurosys.services`
   - README: only changes forced by the reverts (remove Service Types section, update module list if needed). Do NOT restructure or rewrite.

**Bias:** Lean minimalist. Every line must earn its place. If the abstraction doesn't have two active users, it doesn't belong.

**Success Criteria** (what must be TRUE):
  1. Phase 94 and 97 reverts fully executed — no capability interface or service-types machinery remains
  2. Every module audited post-revert — no dead code, no stale references to removed abstractions
  3. Accepted risks in CLAUDE.md are current — stale entries removed, new concerns documented
  4. `nix flake check` passes with all eval checks updated
  5. `grep -r "neurosys.services\|neurosys.backup\|neurosys.sandbox"` returns zero hits outside of git history
  6. No personal identifiers in public repo (re-verify Phase 37/90 work)
  7. README changes limited to what the reverts require

**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 98 to break down)


### Phase 99: Documentation Optimization — Honesty, Completeness, Minimalism

**Goal:** Audit all documentation (README.md, CLAUDE.md, SECURITY.md, docs/, module headers, inline comments, code comments, `@decision` annotations) against the actual codebase for three properties: (1) **Honesty** — every claim accurately reflects current code; remove or fix stale/incorrect statements. (2) **Completeness** — all key decisions, design details, security model, and features are documented where they should be; fill gaps. (3) **Minimalism** — docs should concisely point users (primarily coding agents) in the right direction without repeating what the code already says; replace verbose explanations with links to code or external resources where appropriate; cut redundancy across files. Includes a pass over all code comments and `@decision` annotations to consolidate, remove stale/obvious ones, and ensure only non-obvious decisions remain annotated. KISS and concision are gold.
**Depends on:** Phase 98
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 99 to break down)

### Phase 100: Code review remediation (March 23 review)

**Goal:** Address the valid findings from the March 23 external code review (tsurf_code_review_3_23.md). Scope limited to items verified as real issues in the current codebase:

1. **Fix opencode.nix hash** — replace placeholder `sha256-AAAAAAA...` with the real hash so the derivation builds, or document how overlay users should pin it.
2. **Remove stale base.nix comment** — line 30 references `scripts/deploy-post.sh` which doesn't exist.
3. **Clean up clone-repos activation** — `repos=()` is empty; either add example content or remove the activation script from the public dev host.
4. **Decouple dashboard entries from networking.nix** — move Tailscale/SSH dashboard entries out of the core networking module to reduce core-to-extras coupling.
5. **Move deploy.sh to examples/** — 488-line deploy wrapper can't run from the public repo anyway (tsurf.url guard). Move to `examples/` or private overlay docs.

**Note:** dev-agent.nix stays in extras/ as a core optional module. The nested ./tsurf repo, missing flake.lock, egress port configs, allowNixDaemon, egressControl.user, agent-sandbox-e2e wrapper, and shared nono profile mutation were all misidentified by the reviewer (stale snapshot).

**Acceptance criteria:**
- `extras/opencode.nix` builds (real hash) or has clear pin-your-own-hash documentation
- No stale file references in module comments
- Public dev host activation script either does useful example work or is removed
- `modules/networking.nix` has zero dashboard entry registrations
- `deploy.sh` lives in `examples/` or is clearly documented as private-overlay-only

**Depends on:** Phase 99
**Plans:** 3 plans

Plans:
- [x] 100-01-PLAN.md -- Fix opencode placeholder hash workflow, remove stale base.nix deploy-post reference, and remove no-op clone-repos activation from public dev host.
- [x] 100-02-PLAN.md -- Move Tailscale/SSH dashboard entries out of `modules/networking.nix` into `extras/dashboard.nix` to decouple core modules from extras.
- [ ] 100-03-PLAN.md -- Move `deploy.sh` to `examples/scripts/` and update test/documentation references.

### Phase 144: GSD — High-Impact Security + Core Dev-Agent Ops Remediation

**Goal:** Close the remaining High issues from the March 24 fresh-eyes review while keeping `dev-agent` as a first-class public use case. This phase hardens the supported agent paths, turns control-plane separation into enforced behavior, promotes `dev-agent` from demo-like launcher to supported lifecycle module, and makes the docs/examples describe one coherent public model.

**Depends on:** Phase 100

**Success Criteria** (what must be TRUE):
  1. Supported default agent paths (`claude` interactive wrapper and `dev-agent`) have an explicit egress policy instead of blanket host egress
  2. The control-plane repo is no longer the normalized writable sandbox target; code, tests, and docs all reflect a workspace-first enforced model
  3. `dev-agent` is parameterized and operationally manageable on remote hosts rather than hardcoded to a tsurf-specific task with detached-session ambiguity
  4. README, CLAUDE.md, SECURITY.md, and private-overlay examples agree that `dev-agent` is a supported core path and remove stale extension-mechanism references
  5. `nix flake check` passes with updated assertions/documentation

**Plans:** 1 plan

Plans:
- [ ] 144-01-PLAN.md -- Execute egress control, control-plane/workspace separation, dev-agent lifecycle hardening, and public docs/example convergence.

### Phase 145: Ecosystem Review Security Hardening

Implement top findings from the 2026-03-24 ecosystem review of 10 agent sandbox/Nix tooling repos. Tier 1: systemd-run hardening properties (NoNewPrivileges, CapabilityBoundingSet, OOMScoreAdjust, rlimits, RuntimeMaxSec), NPM/Python supply chain env vars, Claude settings deny rules. Tier 2: nftables egress filtering scoped to agent UID, seccomp-bpf syscall blocklist via SystemCallFilter, protected/masked workdir paths (.git/hooks, .envrc, .mcp.json). Tier 3: integrate deadnix/statix/vulnix, evaluate llm-agents.nix and nix-mineral. Research source: .planning/research/ecosystem-review-2026-03-24.md

**Goal:** Harden agent sandbox with ecosystem-sourced security layers: systemd properties, egress filtering, seccomp, protected workdir paths, supply chain env vars, and Nix tooling integration.
**Depends on:** Phase 144
**Plans:** 3 plans in 2 waves

Plans:
- [x] 145-01-PLAN.md -- systemd-run hardening properties (NoNewPrivileges, CapabilityBoundingSet, rlimits, RuntimeMaxSec), seccomp-bpf syscall blocklist, supply chain + telemetry env vars.
- [x] 145-02-PLAN.md -- Protected workdir paths (.git/hooks, .envrc, .mcp.json) + Claude settings deny rules + enableAllProjectMcpServers=false.
- [ ] 145-03-PLAN.md -- nix-mineral hardening integration (flake input, compatibility preset, agent-workload overrides).

### Phase 146: Generate comprehensive technical specification of core features and security model

**Goal:** [To be planned]
**Depends on:** Phase 145
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 146 to break down)

### Phase 147: Bolster test cases to validate implementation meets spec — tie each test to a spec claim ID

**Goal:** [To be planned]
**Depends on:** Phase 146
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 147 to break down)

### Phase 150: Relocate Private Concerns from Public Core

**Goal:** Move Tailscale, dashboard, and restic status server out of the public repo. Runs first because it is independent and reduces the surface area for all subsequent phases.

**Depends on:** Nothing (run first)

**Crosstalk notes:**
- ABSORB syncthing example removal here (do not duplicate in Phase 154).
- MUST clean `services.dashboard.entries.*` from: `extras/restic.nix`, `extras/cost-tracker.nix`, `examples/private-overlay/hosts/example/default.nix`.
- MUST remove `"8082" = "Dashboard"` from internalOnlyPorts in `modules/networking.nix`.
- MUST update `tests/eval/config-checks.nix`: remove ~8 dashboard checks, Tailscale assertion checks, update systemd unit lists.
- MUST update both host default.nix files to remove dashboard import/enable.
- When removing Tailscale, update assertion block in networking.nix (remove `services.tailscale.enable` assertion and `allowedUDPPorts` Tailscale port ref).
- Do NOT do full CLAUDE.md rewrite — only remove dashboard/Tailscale from project structure table. Full doc pass in Phase 156.

**Success Criteria** (what must be TRUE):
  1. Tailscale configuration moved from `modules/networking.nix` to a pattern documentable for the private overlay (or an opt-in extras module with no hard dependency)
  2. `extras/dashboard.nix` and all associated frontend/backend code removed from public repo
  3. Restic status server (HTTP endpoint on port 9200) removed from `extras/restic.nix`; backup functionality preserved
  4. All `services.dashboard.entries` declarations removed from remaining modules
  5. Syncthing example removed from `examples/private-overlay/modules/`
  6. Audit confirms no remaining extras modules serve purely private concerns
  7. `tests/eval/config-checks.nix` updated — all dashboard/Tailscale-specific checks removed or updated
  8. `nix flake check` passes

**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 150 to break down)

### Phase 151: Repo Hygiene — Git History Only

**Goal:** Purge .planning from git history and prevent re-addition. File headers are DEFERRED to Phase 156 (after all structural rewrites complete) to avoid writing headers on files about to be deleted or heavily rewritten.

**Depends on:** Nothing (can run in parallel with Phase 150)

**Crosstalk notes:**
- SKIP file headers. Writing headers now would waste work on files deleted in 150 (dashboard), 152 (pi, opencode), or heavily rewritten (agent-sandbox, users, networking).
- Headers deferred to Phase 156 where they are written once on final file versions.

**Success Criteria** (what must be TRUE):
  1. `.planning/` directory is purged from all git history (BFG or git-filter-repo)
  2. A commit hook or CI check rejects any commit that adds files under `.planning/`
  3. Agent instructions (CLAUDE.md, skills) explicitly note `.planning/` is local-only and must never be committed
  4. `nix flake check` passes

**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 151 to break down)

### Phase 152: User Model + Agent Sandbox Architecture Overhaul

**Goal:** Combined phase (merged from original 151+154) to avoid double-rewriting agent-sandbox.nix, agent-wrapper.sh, and users.nix. Collapse user model to root+agent, then rewrite sandbox as generic launcher in one pass. This is the largest phase — consider splitting into sub-plans but keep them sequential without intervening phases.

**Depends on:** Phase 150 (private concerns removed — dashboard refs gone, Tailscale gone)

**Crosstalk notes:**
- Do NOT remove sudo as a separate step then rewrite the file. Just rewrite agent-sandbox.nix once — the generic launcher inherently removes the sudo broker chain.
- MUST handle `extras/codex.nix` — it has the same sudo/protected-repo/devHome pattern as pi/opencode. Either rewrite to generic launcher pattern or remove.
- MUST fix all dev-user refs when removing dev: `extras/home/default.nix` (hardcodes "dev"), `extras/home/cass.nix` (HOME=/home/dev), `extras/codex.nix` (devHome), host default.nix files (home-manager.users.dev), `modules/users.nix` persistence paths.
- MUST remove `.tsurf-control-plane` marker from repo root.
- MUST update `tests/eval/config-checks.nix`: remove `sandbox-refuses-protected-control-plane-repos`, `control-plane-marker-file`, update user model assertions.
- When removing dev user, decide if home-manager applies to root or agent user.
- Update CLAUDE.md/SECURITY.md ONCE for combined user+sandbox changes — skip intermediate doc updates.

**Success Criteria** (what must be TRUE):
  1. No `dev` user exists; `users.nix` defines only root and agent
  2. `break-glass-ssh.nix` simplified to root SSH key (no break-glass concept, no placeholder — build fails if key absent)
  3. Linger removed unless concrete runtime requirement identified
  4. Protected/control-plane repo concept fully removed (markers, wrapper checks, eval tests, spec refs). Replaced by documentation: "agents must not deploy changes to their own security boundaries"
  5. `nono.nix` profile is fully generic — no claude-specific naming, reusable for any sandboxed binary
  6. A generic agent launcher exists: given binary path, nono profile overrides, secret declarations, and optional args → sandboxed wrapper + systemd service
  7. `agent-sandbox.nix` and `agent-wrapper.sh` rewritten to use generic launcher (sudo removed inherently)
  8. `dev-agent.nix` is a thin wrapper (~30-50 lines) on top of generic launcher — no redundant systemd hardening
  9. `pi.nix` and `opencode.nix` removed entirely
  10. zmx evaluated against simpler alternatives; decision documented
  11. Systemd broker rationale documented (why agents can't bypass sandbox)
  12. CLAUDE.md, SECURITY.md updated for new privilege model + sandbox architecture
  13. `nix flake check` passes

**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 152 to break down)

### Phase 153: Base System & Networking Simplification

**Goal:** With Tailscale removed (Phase 150) and user model settled (Phase 152), simplify networking.nix and base.nix cleanly in one pass.

**Depends on:** Phase 150 (Tailscale gone), Phase 152 (user model settled)

**Crosstalk notes:**
- Agent egress STAYS in networking.nix per existing @decision NET-144-01 ("nftables is the supported outbound allowlist boundary"). Do NOT move to nono — nono is filesystem sandbox only.
- Tailscale block already removed in Phase 150, so simplification scope is cleaner.
- Networking assertions already updated in Phase 150 (Tailscale) and Phase 152 (user model). Review but don't re-derive.

**Success Criteria** (what must be TRUE):
  1. `networking.nix` simplified — SSH hardening + firewall lean on srvos defaults where possible; agent egress (nftables UID rules) reviewed for new user model but stays in networking.nix
  2. `base.nix` system packages reviewed; each package has documented justification or is removed (assume projects declare own deps via flakes)
  3. Coredumps disabled system-wide
  4. IMP-05 (`/etc` permissions for sshd strict mode) has augmented comment explaining why it's needed, confirmed still required
  5. `impermanence.nix` includes brief comment showing how modules add their own persist paths (minimal inline example)
  6. `nix flake check` passes

**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 153 to break down)

### Phase 154: Deploy & Examples Rework

**Goal:** Make deployment a first-class core feature and ensure examples showcase tsurf's value.

**Depends on:** Phase 150 (syncthing already removed), Phase 152 (user model settled — examples reflect final architecture)

**Crosstalk notes:**
- Syncthing already removed in Phase 150. Do NOT attempt again.
- Deploy.sh simplification can assume final user model (root + agent) and no Tailscale in public core.
- Private overlay docs should reference new user model, not old dev/agent split.

**Success Criteria** (what must be TRUE):
  1. `deploy.sh` promoted to core location (e.g., `scripts/deploy.sh`) as usable template — simplified from current 517 lines
  2. Deploy skill contains no private host references (OVH, Contabo, specific hostnames)
  3. Greeter example replaced or reworked to better demonstrate tsurf's agent management utility
  4. Private overlay example documents bootstrap key step and new user model
  5. `nix flake check` passes

**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 154 to break down)

### Phase 155: tsurf CLI & Commit Tooling

**Goal:** Create minimal CLI for initialization and status monitoring, plus a complexity guard.

**Depends on:** Phase 150 (dashboard gone — tsurf status replaces it), Phase 152 (user model — tsurf init targets final model)

**Crosstalk notes:**
- break-glass-ssh.nix already simplified in Phase 152. `tsurf init` generates the real key for that file — don't redesign the file here.

**Success Criteria** (what must be TRUE):
  1. `tsurf init` exists as minimal CLI wizard: generates root SSH key, validates it's in place, optionally fills other setup sections. KISS — assumes standard Linux host
  2. Build-time assertions check root SSH key exists (fail clearly if not run, no placeholders in pub repo)
  3. `tsurf status <deploy-name>` dynamically fetches and presents service status across hosts (minimal first version, replaces dashboard)
  4. Quantitative complexity metric analyzes nix + build/runtime scripts; commit hook appends delta with warning if too large
  5. No break-glass key concept remains — just root key requirement enforced by assertions

**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 155 to break down)

### Phase 156: Final Polish — Guardrails, File Headers, Doc Cleanup

**Goal:** Single final pass combining agent ecosystem work, file documentation headers, and docs/annotation cleanup. Runs LAST so all structural changes are complete — headers are written once on final file versions, docs updated once for the final architecture.

**Depends on:** Phases 150-155 (all prior phases)

**Crosstalk notes:**
- File headers written here, NOT in Phase 151. This eliminates all wasted header work on deleted/rewritten files.
- cass.nix already had `/home/dev` refs fixed in Phase 152 when dev user was removed. Core move should be straightforward.
- @decision audit should be thorough — Phases 150, 152, and 153 removed many annotated decisions. Count remaining and verify each is still relevant.
- CLAUDE.md/SECURITY.md get ONE final comprehensive update reflecting all changes from 150 through 155, rather than accumulating incremental updates.

**Success Criteria** (what must be TRUE):
  1. `cass.nix` moved from `extras/home/` to appropriate core location, included by default for all agent users
  2. CASS process has CPU and memory resource limits
  3. Private overlay sets `~/.claude` to agentic-dev-base pulled from public GitHub
  4. agentic-dev-base includes hooks blocking commits with sensitive info (API keys, tokens, passwords, private IPs)
  5. Guard blocks agents from modifying README.md autonomously — each change requires explicit user approval
  6. Every `.nix`, `.sh`, and `.py` file has a concise 2-3 sentence description header
  7. CLAUDE.md, SECURITY.md, README.md, and spec/ reflect final architecture (agent-only user model, generic sandbox launcher, no dashboard/control-plane, tsurf CLI)
  8. `@decision` annotations audited: only security-critical and non-obvious choices remain, each one sentence max
  9. No stale references to removed concepts (dev user, control-plane repos, dashboard, pi/opencode, break-glass key)
  10. Private overlay example and README describe current setup flow (tsurf init → configure → deploy)
  11. `nix flake check` passes

**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 156 to break down)

### Phase 157: Codebase complexity audit — find and prioritize cleanup targets

**Goal:** [To be planned]
**Depends on:** Phase 156
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 157 to break down)

### Phase 158: Evaluate self-hosted Tailscale alternatives (headscale, wg-easy) — research report only

**Goal:** [To be planned]
**Depends on:** Phase 157
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 158 to break down)

### Phase 159: Cut public repo to minimal core (March 27 review, finding #2)

**Goal:** Address finding #2 from the March 27 code review: the public repo mixes core platform, optional extras, maintainer process, and experimental conveniences. Cut hard so the public story is crisp and minimal. Understand the finding deeply, research optimal resolution, plan, execute, verify with `nix flake check`, and push to main.

Concrete objectives:
1. Default host fixtures (`hosts/services/default.nix`, `hosts/dev/default.nix`) import only minimal core modules — no extras in default imports
2. All optional services/wrappers (CASS, restic, cost-tracker, codex, Home Manager) are truly opt-in — not imported or enabled by default
3. CASS (`extras/cass.nix`) defaults to disabled (`enable = false`), not enabled
4. Home Manager moved out of `commonModules` in `flake.nix` — imported only by roles that need it
5. README newcomer path reduced to 3-5 docs; maintainer-only material (CLAUDE.md, spec/, git hooks, complexity tooling) demoted from the front door
6. Generic launcher reframed as "advanced extension API" in docs, not equal first-class path
7. `nix flake check` passes

**Depends on:** None (independent remediation)
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 159 to break down)

### Phase 160: Harden core dependency trust boundary (March 27 review, finding #3) ✅ Complete (2026-04-03)

**Goal:** Address finding #3 from the March 27 code review: the core trust boundary depends on shaky edges — a prebuilt alpha `nono` binary, `nix-mineral` on stable with a compatibility shim, and `cass` as a prebuilt binary in the default path. Understand the finding deeply, research optimal resolution for each dependency, plan, execute, verify with `nix flake check`, and push to main.

Concrete objectives:
1. ✅ `nono` trust/provenance resolved: built from pinned source via `rustPlatform.buildRustPackage` (@decision SEC-160-05)
2. ✅ `cass` verified fully out of the default trust path — opt-in extra only (Phase 159 work intact)
3. ✅ `nix-mineral` resolved: critical sysctls set explicitly in `modules/base.nix` (@decision SEC-160-03), compat shim annotated (@decision SEC-160-04)
4. ✅ Security-relevant defaults set explicitly: firewall (@decision SEC-160-01), SSH auth/forwarding (@decision SEC-160-02), kernel hardening (@decision SEC-160-03)
5. ✅ `nix flake check` passes with 7 new explicit-* regression guards

**Depends on:** Phase 159 (CASS default-path removal — verified intact)
**Plans:** 3 plans, complete (2026-04-03)

### Phase 161: End-to-end sandbox launch-path testing (March 27 review, finding #1)

**Goal:** Address finding #1 (critical) from the March 27 code review: the most security-critical path — the full privileged launch chain from wrapper through sudo, systemd-run, credential proxy, nono, to setpriv — is not tested end-to-end. The existing "behavioral" tests bypass the real launch chain and run nono directly. Understand the finding deeply, research optimal test architecture, plan, execute, verify with `nix flake check`, and push to main.

Concrete objectives:
1. A deterministic fake agent package (`writeShellScriptBin` or similar) exists that prints env vars, attempts secret/sibling-repo access, calls the loopback proxy, and records effective UID/GID/cwd
2. The fake agent is wired through the real `services.agentLauncher.agents.<name>` module path — same generated wrapper, launcher, nono profile, and sudo rule as real agents
3. At least one VM test (`tests/vm/`) invokes the actual generated wrapper as the agent user and verifies: (a) child runs as agent UID not root, (b) `/run/secrets/*` unreadable, (c) sibling repo access denied, (d) current repo accessible, (e) proxy flow works (child sees session token + loopback URL), (f) transient unit has expected systemd properties (MemoryMax, CPUQuota, NoNewPrivileges, CapabilityBoundingSet, etc.)
4. `spec/testing.md` updated — core sandbox chain no longer listed as uncovered
5. Existing direct-nono probe tests either removed or explicitly demoted to supplementary coverage
6. `nix flake check` passes

**Depends on:** Phase 160 (dependency decisions may affect sandbox primitives)
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 161 to break down)

### Phase 162: Migrate to headscale: deploy self-hosted coordination server, repoint Tailscale clients, ACL policy, embedded DERP, tests

**Goal:** Add opt-in headscale coordination server module with nginx, DERP, eval checks, and doc updates
**Status:** Complete (2026-03-27)
**Depends on:** Phase 161
**Plans:** 1/1 complete

Plans:
- [x] PLAN.md — Core headscale module, networking integration, eval checks, doc updates

### Phase 163: tsurf-status CLI: tree-based host, service, and cost overview

**Goal:** Replace the existing `tsurf-status.sh` with a new `tsurf status` flake app that queries all configured hosts in parallel via SSH and renders a minimal tree view. Top level: hosts (with connectivity indicator). Second level: agents and services, each showing status (active/failed/inactive), uptime, type (agent/timer/service), and sandbox profile where applicable. Below the tree: a system metadata footer per host showing OS version/generation, system uptime, last deploy timestamp (from NixOS profile date), backup status (last restic run + next scheduled), disk usage on /persist, and high-level API cost summary (24h/7d totals per provider, read from `/run/tsurf-cost.json` if cost-tracker is enabled). Support `--host <name>` to query a single host, `--json` for machine output, and `--no-color` for piping. Subsumes the current `tsurf-status.sh` script which only checks a hardcoded list of units.
**Depends on:** None (replaces existing tsurf-status.sh; reads existing cost-tracker output)
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 163 to break down)
