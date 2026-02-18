# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-15)

**Core value:** One command to deploy a fully working development server with all services running, all tools installed, and all infrastructure repos cloned -- no manual setup steps.
**Current focus:** Phase 13 COMPLETE — Research findings presented, user cherry-picked adoptions. Next: Phase 14 (Monitoring + Notifications).

## Current Position

Phase: 13 (Research Similar Projects) — COMPLETE
Plan: 1 of 1 — COMPLETE
Status: All 11 ideas presented and dispositioned. 5 adopted, 1 evaluated, 2 rejected, 4 deferred. New phases 14 and 15 created.
Last activity: 2026-02-18 - User cherry-picked research findings, decisions captured.

Progress: Phase 13 complete (1/1 plans). Phases 14-15 created from adopted ideas.

## Performance Metrics

**Velocity:**
- Total plans completed: 15
- Average duration: ~18min
- Total execution time: ~270 min

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

**Recent Trend:**
- Last 2 plans: 10-01 (25min), 10-02 (90min — includes VPS reinstall)
- Trend: Deployment testing requires iterative debugging against live infrastructure

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

### Roadmap Evolution

- Phase 10 added: Parts Deployment Pipeline — Research + Implementation (understand current parts deployment, implement agent-neurosys-owned deploy flow)
- Phase 11 added: Agent Sandboxing — Default-on bubblewrap (srt) isolation for all coding agents. Research: evaluated Daytona, E2B, Firecracker, gVisor, nsjail, Docker, systemd-nspawn. bubblewrap selected for zero overhead, NixOS-native, proven by Claude Code's own sandbox. VPS: Contabo Cloud VPS 60 NVMe (18 vCPU, 96GB RAM) — no KVM, rules out microVMs.
- Phase 12 added: Security audit — review all modules for hardening gaps, secret handling, network exposure, sandbox escape vectors, and supply chain risks
- Phase 13 added: Research similar personal server projects — 11 ideas surveyed, 5 adopted, 1 evaluated, 2 rejected, 4 deferred
- Phase 14 added: Monitoring + Notifications — Prometheus + node_exporter + Grafana + ntfy (from Phase 13 research adoptions)
- Phase 15 added: CrowdSec Intrusion Prevention — collaborative threat intelligence with community sharing (from Phase 13 research)

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

### Quick Tasks Pending (from Phase 13)

| Task | What | Effort |
|------|------|--------|
| Agent Teams env var | Add `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=true` to agent-spawn | Minutes |
| MCP-NixOS evaluate | Add to `.mcp.json`, test in sessions, remove if context-polluting | Minutes |
| Tailnet Key Authority | Run `tailscale lock init` + sign nodes | Minutes |

## Session Continuity

Last session: 2026-02-18
Stopped at: Phase 13 complete. Decisions captured. Next: plan Phase 14 or execute quick tasks.
Resume file: None
