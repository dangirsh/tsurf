# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-13)

**Core value:** One command to deploy a fully working development server with all services running, all tools installed, and all infrastructure repos cloned -- no manual setup steps.
**Current focus:** Phase 3.1 - Parts Integration (Flake Module + Declarative Containers)

## Current Position

Phase: 3.1 of 9 (Parts Integration — Flake Module + Declarative Containers)
Plan: 0 of 3 in current phase
Status: Planned, ready to execute
Last activity: 2026-02-15 -- Consolidated state, merged phase-01-02, Phase 1 complete

Progress: [██........] 2/6 plans (33%)

## Performance Metrics

**Velocity:**
- Total plans completed: 2
- Average duration: ~6.5min
- Total execution time: ~13 min

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 | 2/2 | ~13min | ~6.5min |

**Recent Trend:**
- Last 2 plans: 01-01 (8min), 01-02 (5min)
- Trend: steady

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: 7-phase structure derived from 37 requirements with natural delivery boundaries
- [Roadmap]: Pre-deploy phase separated because sops-nix bootstrap and disko config must be correct before nixos-anywhere runs
- [Roadmap]: Docker/Tailscale/firewall grouped in Phase 3 due to three-way interaction risk
- [01-01]: GRUB hybrid BIOS+UEFI for Contabo VPS boot mode uncertainty
- [01-01]: Module-per-concern pattern (base, boot, users, networking, secrets)
- [01-02]: Dual age keys — admin for local editing + host key for server decryption
- [01-02]: Pre-generated SSH host key in tmp/host-key/ for nixos-anywhere --extra-files

### Roadmap Evolution

- Phase 2.1 inserted after Phase 2: Base System Fixups from Neurosys Review
  - Settings module (`modules/settings.nix`) for centralized user constants
  - Agent-focused system packages baseline (16 packages)
  - SSH hardening (mutableUsers=false, passwordless sudo, execWheelOnly, ssh agent)
- Phase 3.1 inserted after Phase 3: Parts Migration — Flake Module + Declarative Containers (URGENT)
  - Parts exports NixOS module via flake, agent-neurosys imports it
  - Containers via dockerTools, secrets migrated to sops-nix
- Phase 8 completed: Neurosys/doom.d review — 5 candidates approved, 2 rejected, TODOs added to Phases 2.1, 5, 6

### Completed Phases

- **Phase 1: Flake Scaffolding + Pre-Deploy** (2 plans, completed 2026-02-13)
  - 01-01: NixOS flake skeleton (flake.nix, 12 config files, nix flake check passes)
  - 01-02: sops-nix secrets bootstrap (.sops.yaml, encrypted secrets, host key)

### Phase 8 Decisions (Neurosys Review)

**Approved candidates:**
- Candidate 1: Syncthing declarative config → Phase 6 (structural pattern only, fresh params)
- Candidate 2: Settings module → Phase 2.1 (new `modules/settings.nix`)
- Candidate 3: System packages baseline → Phase 2.1 (agent-focused: 16 packages)
- Candidate 5: SSH hardening → Phase 2.1 (mutableUsers, sudo, ssh agent, execWheelOnly)
- Candidate 6: SSH client config → Phase 5 (new `home/ssh.nix`)

**Rejected candidates:**
- Candidate 4: Nix settings (sandbox, max-jobs) — defaults sufficient
- Candidate 7: Tarsnap backup pattern — will decide backup paths fresh in Phase 7

**Open question answers:**
- Q1: Syncthing uses single "Sync" folder now (paths deferred to Phase 6)
- Q2: 4 current devices — MacBook-Pro.local, DC-1, Pixel 10 Pro, MacBook-Pro-von-Theda.local
- Q3: Teleport not needed
- Q4: Direnv yes, with nix-direnv for cached evaluations to minimize cd latency → Phase 5

### Pending Todos

None yet.

### Blockers/Concerns

- [Research]: Contabo boot mode (BIOS vs UEFI) unverified -- use hybrid GRUB config as hedge
- [Research]: CASS binary availability unclear -- may need custom derivation in Phase 6
- [Research]: Docker `--iptables=false` full implications on inter-container networking need testing in Phase 3

## Session Continuity

Last session: 2026-02-15
Stopped at: Phase 8 complete — neurosys review decisions captured, TODOs added to ROADMAP.md
Resume file: None
