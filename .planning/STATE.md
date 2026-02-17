# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-15)

**Core value:** One command to deploy a fully working development server with all services running, all tools installed, and all infrastructure repos cloned -- no manual setup steps.
**Current focus:** Phase 10 COMPLETE — parts deployment pipeline verified end-to-end.

## Current Position

Phase: 10 (Parts Deployment Pipeline) — COMPLETE
Plan: 2 of 2 — COMPLETE (10-01, 10-02)
Status: Deploy pipeline tested end-to-end. VPS migrated to new IP, all critical fixes applied. Parts containers running.
Last activity: 2026-02-17 - Completed Plan 10-02 (end-to-end deploy test + VPS migration)

Progress: Phase 10 complete (2/2 plans). Ready to merge to main.

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

### Roadmap Evolution

- Phase 10 added: Parts Deployment Pipeline — Research + Implementation (understand current parts deployment, implement agent-neurosys-owned deploy flow)
- Phase 11 added: Agent Sandboxing — Default-on bubblewrap (srt) isolation for all coding agents. Research: evaluated Daytona, E2B, Firecracker, gVisor, nsjail, Docker, systemd-nspawn. bubblewrap selected for zero overhead, NixOS-native, proven by Claude Code's own sandbox. VPS: Contabo Cloud VPS 60 NVMe (18 vCPU, 96GB RAM) — no KVM, rules out microVMs.

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

## Session Continuity

Last session: 2026-02-17
Stopped at: Phase 10 complete. Merging to main.
Resume file: None
