# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-15)

**Core value:** One command to deploy a fully working development server with all services running, all tools installed, and all infrastructure repos cloned -- no manual setup steps.
**Current focus:** Phase 16 COMPLETE — Disaster Recovery & Backup Completeness. All 2 plans executed, deployed, and verified with dry-run restore.

## Current Position

Phase: 16 (Disaster Recovery & Backup Completeness)
Plan: 2 of 2 — ALL COMPLETE
Status: Phase 16 fully executed. Backup gaps closed (SSH host key, Docker bind mounts, Tailscale state, pg_dump hook), recovery runbook written, deployed to VPS, backup snapshot verified with dry-run restore (1911 files, 63.6 MiB).
Last activity: 2026-02-19 - Completed Phase 16 Plans 01-02

Progress: Phase 16 complete (2/2 plans).

## Performance Metrics

**Velocity:**
- Total plans completed: 16
- Average duration: ~17.5min
- Total execution time: ~278 min

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 | 2/2 | ~13min | ~6.5min |
| 2 | 1/2 | ~5min | ~5min |
| 3 | 2/2 | ~15min | ~7.5min |
| 3.1 | 3/3 | ~75min | ~25min |
| 4 | 2/2 | ~60min | ~30min |
| 5 | 2/2 | ~37min | ~18.5min |
| 6 | 2/2 | ~40min | ~20min |

| 10 | 2/2 | ~115min | ~57.5min |
| 14 | 2/2 | ~20min | ~10min |

| 16 | 2/2 | ~25min | ~12.5min |
| 17 | 4/4 | ~76min | ~19min |

**Recent Trend:**
- Last 4 plans: 17-04 (~20min), 16-01 (~15min), 16-02 (~10min)
- Trend: Parallel agent execution for independent plans continues to be efficient.

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [06-01]: Syncthing GUI binds 0.0.0.0:8384, restricted via trustedInterfaces (not IP binding)
- [06-01]: allowUnfreePredicate for claude-code added to base.nix (pre-existing Phase 5 issue)
- [06-02]: CASS v0.1.64 binary via fetchurl + autoPatchelfHook
- [06-02]: Repo cloning is clone-only (never pull/update) to protect dirty working trees
- [06-02]: mkOutOfStoreSymlink for whole-directory ~/.claude and ~/.codex symlinks
- [Phase quick-001]: Use fetchurl of pre-built zmx static binary instead of flake input (zig2nix bwrap incompatible with apparmor)
- [10-01]: Manual deploy only — no CI/CD, NixOS handles incrementality
- [10-01]: Full nixos-rebuild switch every deploy — no partial/container-only path
- [10-01]: Container health polling (30s) — no app-level health checks
- [10-01]: No auto-commit of flake.lock — print reminder instead
- [10-02]: Port 22 must be in allowedTCPPorts for deploy pipeline
- [10-02]: PermitRootLogin = prohibit-password required for nixos-rebuild --target-host
- [10-02]: Root authorized keys managed in users.nix
- [11-01]: agent-spawn defaults to bubblewrap sandbox; --no-sandbox is explicit bypass
- [11-01]: Podman enabled with dockerCompat=false (conflicts with Docker); sandbox-local docker→podman symlink instead
- [11-01]: Metadata endpoint 169.254.169.254 blocked in nftables output chain
- [11-01]: API keys are read pre-sandbox from sops secret files and injected via env vars
- [11-02]: NIX_REMOTE=daemon required inside sandbox (user namespace blocks direct store access)
- [11-02]: daemon-socket needs rw bind (Unix socket connection requires write permission)
- [11-02]: zmx binary must be extracted from tarball (dontUnpack was installing gzip as binary)
- [11-02]: Audit log dir pre-created via systemd.tmpfiles (dangirsh can't write to root-owned /data/projects)
- [quick-002]: Home Assistant as native NixOS service, not Docker (HA-01)
- [quick-002]: HA GUI accessible via Tailscale only, same trustedInterfaces pattern as Syncthing (HA-02)
- [13-01]: ntfy ADOPTED — foundational notification layer (Android push urgent, email non-urgent)
- [13-01]: Prometheus+Grafana ADOPTED — minimal monitoring stack, Tailscale-only dashboards
- [13-01]: CrowdSec ADOPTED — collaborative sharing enabled, for public-facing services (claw-swap)
- [13-01]: Agent Teams ADOPTED — env var config change, quick task
- [13-01]: MCP-NixOS EVALUATE — local .mcp.json only, test and remove if noisy
- [13-01]: TKA (Tailnet Key Authority) ADOPTED — self-custody Tailscale signing keys, quick task
- [13-01]: Uptime Kuma DEFERRED — Grafana covers status dashboards
- [13-01]: endlessh-go REJECTED — minimal value with Tailscale-primary SSH
- [13-01]: Headscale REJECTED — TKA covers key sovereignty concern
- [13-01]: Caddy, Authelia, Loki+Alloy DEFERRED — not needed until services are internet-facing or specific log search needs arise
- [14-01]: Monitoring baseline implemented with Prometheus 15s scrape + 90d retention and node_exporter collectors (systemd/processes/tcpstat)
- [14-01]: Alert routing standardized as Alertmanager -> alertmanager-ntfy -> local ntfy topic `alerts`
- [14-01]: Grafana credentials sourced from sops secrets via file provider (not hardcoded in Nix store)
- [14-02]: Deploy notifications run from local deploy script via SSH + server-local ntfy POST to `deploys`
- [14-02]: Deploy notification delivery is best-effort (`|| true`) so ntfy outages cannot break deploy pipeline
- [14-02]: Generic server-side `scripts/notify.sh` introduced for reusable notifications (agents, cron, future restic hooks)
- [quick-005]: MON-05: Alertmanager, ntfy, Grafana removed -- agents query Prometheus /api/v1/alerts directly
- [quick-005]: fail2ban reverts to default ban action (no ntfy notification)
- [quick-006]: ESPHome binds 0.0.0.0:6052 with openFirewall=false (Tailscale-only, same pattern as HA and Syncthing)
- [17-01]: zmx removed from base module and kept in agent-compute package set; duplicate package declaration eliminated
- [17-01]: git-lfs and podman-compose removed as unused features/packages
- [17-01]: stale `parts-agent@vm` SSH key removed from `dangirsh` and `root` authorized keys
- [17-01]: deploy local lock moved from `/tmp` to project-local `tmp/` path
- [17-01]: kernel sysctl hardening enabled (dmesg/kptr restrictions, unprivileged bpf off, redirects off, martian logging on)
- [17-01]: homepage Tailscale IP centralized in a single `let` binding for one-line updates
- [17-01]: `llm-agents.inputs.nixpkgs` now follows root `nixpkgs`; lock update and flake checks passed
- [17-02]: Port 22 removed from public firewall; SSH accessible only via Tailscale (trustedInterfaces)
- [17-02]: Build-time assertion prevents port 22 from being re-added to allowedTCPPorts
- [17-02]: Repo cloning uses git credential.helper store (no PAT in URLs, process args, or .git/config)
- [17-02]: .git/config added to restic excludes to prevent backing up leaked tokens
- [17-03]: CLAUDE.md updated with Security Conventions, Simplicity Conventions, Module Change Checklist
- [17-03]: Accepted Risks documented: SEC3, SEC5, SEC9, SEC11
- [17-04]: Docker audit: claw-swap fully hardened, parts containers lack all hardening (tracked for remediation)
- [17-04]: Sandbox escape vectors confirmed and documented (SEC5 settings.json, SEC6 Docker socket, cross-project read, no network sandbox)
- [17-04]: Audit log gets journald dual-logging via systemd-cat for tamper resistance
- [16-01]: RESTIC-04: Back up SSH host key (sops-nix age chain), Docker bind mounts (/var/lib/claw-swap, /var/lib/parts), Tailscale state (/var/lib/tailscale); pg_dumpall pre-hook for PostgreSQL consistency
- [16-01]: Deploy SSH now uses Tailscale MagicDNS (root@acfs) — public IP port 22 closed by Phase 17
- [16-02]: Recovery runbook at docs/recovery-runbook.md — 4-phase flow, RTO < 2hr, RPO 24hr

### Completed Phases

- **Phase 1: Flake Scaffolding + Pre-Deploy** (2 plans, completed 2026-02-13)
- **Phase 2: Bootable Base System** (2/2 plans, completed 2026-02-15)
- **Phase 2.1: Base System Fixups** — Absorbed into Phase 9
- **Phase 3: Networking + Secrets + Docker Foundation** (2 plans, completed 2026-02-15)
- **Phase 3.1: Parts Integration** (3 plans, completed 2026-02-15)
- **Phase 8: Review Old Neurosys + Doom.d** (1 plan, completed 2026-02-15)
- **Phase 9: Audit & Simplify** (2 plans, completed 2026-02-15)
- **Phase 4: Docker Services** (2 plans, completed 2026-02-16)
- **Phase 5: User Environment + Dev Tools** (2 plans, completed 2026-02-16)
- **Phase 6: User Services + Agent Tooling** (2 plans, completed 2026-02-16)
  - 06-01: Syncthing declarative module (4 devices, 1 folder, staggered versioning, Tailscale-only GUI)
  - 06-02: CASS binary + timer, repo cloning activation, agent config symlinks
- **Phase 10: Parts Deployment Pipeline** (2 plans, completed 2026-02-17)
- **Phase 11: Agent Sandboxing** (2 plans, completed 2026-02-17)
- **Phase 13: Research Similar Projects** (1 plan, completed 2026-02-18)
  - 13-01: Presented 11 ideas, user cherry-picked 5 adoptions (ntfy, Prometheus+Grafana, CrowdSec, Agent Teams, TKA), 1 evaluate (MCP-NixOS), 2 rejected, 4 deferred
- **Phase 14: Monitoring + Notifications** (2 plans, completed 2026-02-18)
  - 14-01: Prometheus + Alertmanager + ntfy + Grafana baseline with 6 alert rules and sops-managed Grafana secrets
  - 14-02: Deploy outcome notifications + generic `notify.sh` helper + full `nix flake check` validation
- **Phase 16: Disaster Recovery & Backup Completeness** (2 plans, completed 2026-02-19)
  - 16-01: Backup gap closure — SSH host key, Docker bind mounts, Tailscale state, pg_dumpall pre-hook; deployed and verified with dry-run restore
  - 16-02: Recovery runbook (docs/recovery-runbook.md) — 4-phase recovery flow, RTO < 2hr, RPO 24hr
- **Phase 17: Hardcore Simplicity & Security Audit** (4 plans, completed 2026-02-19)
  - 17-01: Simplicity cleanup + kernel hardening + llm-agents nixpkgs follow
  - 17-02: SSH hardening (Tailscale-only), credential leak fix, restic backup excludes
  - 17-03: CLAUDE.md guardrails — security conventions, simplicity rules, module checklist
  - 17-04: Docker container audit, sandbox escape assessment, audit log journald dual-logging

### Roadmap Evolution

- Phase 10 added: Parts Deployment Pipeline — Research + Implementation (understand current parts deployment, implement agent-neurosys-owned deploy flow)
- Phase 11 added: Agent Sandboxing — Default-on bubblewrap (srt) isolation for all coding agents. Research: evaluated Daytona, E2B, Firecracker, gVisor, nsjail, Docker, systemd-nspawn. bubblewrap selected for zero overhead, NixOS-native, proven by Claude Code's own sandbox. VPS: Contabo Cloud VPS 60 NVMe (18 vCPU, 96GB RAM) — no KVM, rules out microVMs.
- Phase 12 added: Security audit — review all modules for hardening gaps, secret handling, network exposure, sandbox escape vectors, and supply chain risks
- Phase 13 added: Research similar personal server projects — 11 ideas surveyed, 5 adopted, 1 evaluated, 2 rejected, 4 deferred
- Phase 14 added: Monitoring + Notifications — Prometheus + node_exporter + Grafana + ntfy (from Phase 13 research adoptions)
- Phase 15 added: CrowdSec Intrusion Prevention — collaborative threat intelligence with community sharing (from Phase 13 research)
- Phase 16 added: Disaster Recovery & Backup Completeness — audit stateful paths, complete restic coverage, create tested recovery runbook (< 2hr recovery from git + B2)
- Phase 17 added: Hardcore Simplicity & Security Audit — critical line-by-line review of all modules, services, secrets, networking, Docker, firewall, deployment for over-engineering/YAGNI and security gaps. Establish repo guardrails for future agentic development.

### Blockers/Concerns

- [RESOLVED]: CASS binary availability — v0.1.64 fetched and patched successfully
- [RESOLVED]: Contabo uses BIOS boot (i386-pc GRUB installed successfully), eth0 confirmed
- [RESOLVED]: Secrets deployed and decrypted — 15 secrets in /run/secrets/
- [RESOLVED]: Phase 2.1 scope creep — absorbed into Phase 9 after re-evaluation
- [NOTE]: Syncthing device IDs are placeholders — user must replace before deploy
- [NOTE]: home-manager ssh/git options show deprecation warnings (renamed options) — cosmetic, not blocking

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 001 | Replace tmux with zmx (github.com/neurosnap/zmx) | 2026-02-16 | d3e0209 | [001-replace-tmux-with-zmx](./quick/001-replace-tmux-with-zmx/) |
| 002 | Add Home Assistant as native NixOS service | 2026-02-17 | 6a95e07 | [002-add-home-assistant-as-native-nixos-servi](./quick/002-add-home-assistant-as-native-nixos-servi/) |
| 003 | Add homepage dashboard linking all services | 2026-02-18 | 48b0182 | [3-add-a-nixos-native-homepage-dashboard-li](./quick/3-add-a-nixos-native-homepage-dashboard-li/) |
| 004 | Add concurrent deploy lock to deploy.sh | 2026-02-18 | ef1fc65 | [4-add-concurrent-deploy-lock-to-deploy-sh](./quick/4-add-concurrent-deploy-lock-to-deploy-sh/) |
| 005 | Minimize monitoring stack to Prometheus-only | 2026-02-18 | c5fa13b | [5-minimize-monitoring-notification-stack-t](./quick/5-minimize-monitoring-notification-stack-t/) |
| 006 | Add Hue and ESPHome extraComponents to Home Assistant | 2026-02-18 | 8512fa9 | [6-add-hue-and-esphome-extracomponents-to-h](./quick/6-add-hue-and-esphome-extracomponents-to-h/) |
| 007 | Configure restic backups to Backblaze B2 | 2026-02-19 | 1536d80 | [7-configure-restic-backups-to-backblaze-b2](./quick/7-configure-restic-backups-to-backblaze-b2/) |

### Quick Tasks Pending (from Phase 13)

| Task | What | Effort |
|------|------|--------|
| Agent Teams env var | Add `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=true` to agent-spawn | Minutes |
| MCP-NixOS evaluate | Add to `.mcp.json`, test in sessions, remove if context-polluting | Minutes |
| Tailnet Key Authority | Run `tailscale lock init` + sign nodes | Minutes |

## Session Continuity

Last session: 2026-02-19
Stopped at: Phase 16 complete — backup gaps closed, recovery runbook written, deployed, verified with dry-run restore
Resume file: None
