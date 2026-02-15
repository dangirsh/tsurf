# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-15)

**Core value:** One command to deploy a fully working development server with all services running, all tools installed, and all infrastructure repos cloned -- no manual setup steps.
**Current focus:** Phase 9 COMPLETE — security hardening + roadmap revision done. Next: Phase 4

## Current Position

Phase: 9 of 9 (Audit & Simplify) — COMPLETE
Plan: 2 of 2 in current phase — all complete
Status: Phase 9 complete. Security hardening applied, roadmap revised. Next: Phase 4 (Docker Services + Ollama)
Last activity: 2026-02-15 -- Phase 9 complete: 2 plans, security hardening + roadmap revision

Progress: [██████████] 10/10 plans (100%)

## Performance Metrics

**Velocity:**
- Total plans completed: 8
- Average duration: ~16min
- Total execution time: ~108 min

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 | 2/2 | ~13min | ~6.5min |
| 2 | 1/2 | ~5min | ~5min |
| 3 | 2/2 | ~15min | ~7.5min |
| 3.1 | 3/3 | ~75min | ~25min |

**Recent Trend:**
- Last 2 plans: 03-02 (5min), 02-01 (5min)
- Trend: well-defined config plans execute fast

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
- [03-01]: fail2ban multipliers only (formula mutually exclusive in NixOS)
- [03-01]: defaultSopsFile path fixed: ../secrets/acfs.yaml (not ../../)
- [03-01]: .sops.yaml admin key replaced — orphaned key removed
- [03-02]: Docker iptables=false + NixOS NAT for container outbound
- [03-02]: externalInterface = "eth0" — must verify on Contabo (may be ens3)
- [03.1-01]: Used local age key (age1vma7w9...) as admin — Phase 1 admin key orphaned (no private key)
- [03.1-01]: Parts flake exports nixosModules.default + packages (no nixosConfigurations)
- [03.1-02]: npm workspace lockfile-to-root pattern via postPatch for buildNpmPackage
- [03.1-02]: --ignore-scripts + manual npm rebuild for sandbox-hostile postinstall scripts
- [03.1-03]: sops.templates render secrets into container env files via sops.placeholder
- [03.1-03]: Parts module does NOT import sops-nix or set system-level config — agent-neurosys owns that
- [03.1-03]: path: flake input for local dev — must change to github: for production
- [09]: Phase 2.1 absorbed into Phase 9 — settings module unnecessary for single-host config
- [09]: SSH moved to Tailscale-only — port 22 removed from public firewall
- [09]: Docker container hardening deferred to Phase 4 (scope: agent-neurosys base only)

### Roadmap Evolution

- Phase 2.1 inserted after Phase 2: Base System Fixups from Neurosys Review
  - Settings module (`modules/settings.nix`) for centralized user constants
  - Agent-focused system packages baseline (16 packages)
  - SSH hardening (mutableUsers=false, passwordless sudo, execWheelOnly, ssh agent)
- Phase 3.1 inserted after Phase 3: Parts Migration — Flake Module + Declarative Containers (URGENT)
  - Parts exports NixOS module via flake, agent-neurosys imports it
  - Containers via dockerTools, secrets migrated to sops-nix
- Phase 8 completed: Neurosys/doom.d review — 5 candidates approved, 2 rejected, TODOs added to Phases 2.1, 5, 6
- Phase 9 added: Audit & Simplify — deep review of all modules + unexecuted plans, optimize for simplicity/minimalism/security
- **Phase 2.1 absorbed into Phase 9** — settings module dropped, mutableUsers+execWheelOnly applied in 9-01, dev tools moved to Phase 5
- **Phase 4 updated:** container hardening added to success criteria
- **Phase 5 updated:** absorbs dev tools, ssh-agent, SSH client config, direnv from Phase 2.1 and Phase 8

### Completed Phases

- **Phase 1: Flake Scaffolding + Pre-Deploy** (2 plans, completed 2026-02-13)
  - 01-01: NixOS flake skeleton (flake.nix, 12 config files, nix flake check passes)
  - 01-02: sops-nix secrets bootstrap (.sops.yaml, encrypted secrets, host key)

- **Phase 2: Bootable Base System** (2/2 plans, completed 2026-02-15)
  - 02-01: Module config hardening — nftables, SSH lockdown, docker group
  - 02-02: nixos-anywhere deployment — static IP fix, sops key fix, Codex 5.3 audit, full verification
  - Server live at 62.171.134.33: SSH, Docker, Tailscale, sops secrets, fail2ban all operational

- **Phase 2.1: Base System Fixups** — Absorbed into Phase 9 (settings module dropped, mutableUsers+execWheelOnly in 9-01, dev tools to Phase 5)

- **Phase 3: Networking + Secrets + Docker Foundation** (2 plans, completed 2026-02-15)
  - 03-01: Tailscale VPN + sops-nix secrets (4 secrets) + fail2ban + firewall hardening
  - 03-02: Docker engine (iptables=false) + NixOS NAT + bridge trust + full stack validation

- **Phase 3.1: Parts Integration — Flake Module + Declarative Containers** (3 plans, completed 2026-02-15)
  - 03.1-01: Secrets migration (agenix → sops-nix) + parts flake.nix rewrite
  - 03.1-02: Docker image Nix expressions (parts-agent + parts-tools via buildLayeredImage)
  - 03.1-03: NixOS module (containers, networks, secrets) + agent-neurosys flake integration

- **Phase 8: Review Old Neurosys + Doom.d** (1 plan, completed 2026-02-15)
  - 08-01: Review candidates, user cherry-picking decisions captured

- **Phase 9: Audit & Simplify** (2 plans, in progress)
  - 09-01: Security hardening complete (SSH-to-Tailscale-only, mutableUsers, execWheelOnly)
  - 09-02: Roadmap revision in progress

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

- [Research]: CASS binary availability unclear -- may need custom derivation in Phase 6
- [RESOLVED]: Contabo uses BIOS boot (i386-pc GRUB installed successfully), eth0 confirmed
- [RESOLVED]: Secrets deployed and decrypted — 15 secrets in /run/secrets/
- [RESOLVED]: Phase 2.1 scope creep — absorbed into Phase 9 after re-evaluation

## Session Continuity

Last session: 2026-02-15
Stopped at: Phase 9 complete. All plans through Phase 9 executed. Next: Phase 4 (Docker Services + Ollama).
Resume file: None
