# Project State

Last updated: 2026-04-03

## Current Position
- Phase: 160 — Harden Core Dependency Trust Boundary (March 27 Review Finding #3) — Plan 02 COMPLETE (2026-04-03)
- Plan: 2/2 plans complete
- Status: Core security trust anchors are now self-backing in tsurf-owned modules and the sandbox enforcer supply chain is hardened: firewall/SSH defaults and critical sysctls are explicit in repo modules, SECURITY.md distinguishes explicit anchors from inherited depth, and `nono` now builds from pinned Rust source in `packages/nono.nix` instead of an unverified prebuilt release binary.

## Phase 160 Status
- Phase 160: Harden Core Dependency Trust Boundary (March 27 review finding #3) — 2 plans, complete (2026-04-03)
  - 160-01: complete — Added explicit `networking.firewall.enable = true`; explicit SSH `PasswordAuthentication = false`, `KbdInteractiveAuthentication = false`, and `X11Forwarding = false` with `SEC-160-01/02` annotations in `modules/networking.nix`. Added explicit critical sysctls for kexec/BPF/io_uring/sysrq/source-route/rp_filter with `SEC-160-03` in `modules/base.nix`. Added `SEC-160-04` annotation on the nix-mineral compat shim in `flake.nix`. Updated `SECURITY.md` to separate self-backing defaults from transitive inheritance. Validated with `nix flake check`.
  - 160-02: complete — Replaced `packages/nono.nix` prebuilt GitHub release tarball with a `rustPlatform.buildRustPackage` source build pinned to `always-further/nono` `v0.22.0`, resolved source and cargo hashes, constrained build to `nono-cli`, added `@decision SEC-160-05`, and validated via `nix` build + `result/bin/nono --help`.

## Phase 159 Status
- Phase 159: Cut Public Repo to Minimal Core — 3 plans, complete (2026-03-27)
  - 159-01: complete — Removed default fixture imports for `cass`, `cost-tracker`, and `headscale`; removed fixture `home-manager.users` wiring; removed HM overrides from `eval-dev-alt-agent`; changed CASS eval check to source-based `cass-default-disabled`; handled missing `tsurf.headscale` option path in opt-in check; validated with `nix flake check`.
  - 159-02: complete — Deleted public `spec/` directory and created root `QUICKSTART.md` covering prerequisites, public template validation, private overlay bootstrap (`tsurf-init`), secrets setup, first deploy, extras opt-in pattern, and links to architecture/security docs.
  - 159-03: complete — Updated public docs and private overlay examples to the minimal-core baseline: README points newcomers to `QUICKSTART.md`, docs consistently frame extras as opt-in, the generic launcher is documented as an advanced extension API, and stale `spec/` references were removed. Final validation passed with `nix flake check`.

## Phase 162 Status
- Phase 162: Migrate to headscale — 1 plan, complete (2026-03-27)
  - PLAN: complete — Created modules/headscale.nix with opt-in toggle, localhost:8080 bind, nginx TLS proxy with WebSocket, embedded DERP with STUN/3478, SQLite persistence, ACL policy via environment.etc, 6 eval checks, doc/comment updates across 10 files.

## Phase 100 Status
- Phase 100: Code review remediation (March 23 review) — 3 plans, in progress
  - 100-01: complete — Fixed opencode placeholder hash workflow (`lib.fakeHash`), removed stale `deploy-post.sh` guidance from `modules/base.nix`, removed no-op `clone-repos` activation from `hosts/dev/default.nix`, and validated with `nix flake check`.
  - 100-02: complete — Removed `services.dashboard.entries` declarations from `modules/networking.nix`, added Tailscale/SSH entries to the unconditional `config` section in `extras/dashboard.nix`, and validated with `nix flake check`.
  - 100-03: pending — Move `deploy.sh` from `extras/scripts/` to `examples/scripts/` and update references.

## Phase 145 Status
- Phase 145: Ecosystem Review Security Hardening — 3 plans, in progress
  - 145-01: complete — Added systemd-run hardening properties (NoNewPrivileges, CapabilityBoundingSet, OOMScoreAdjust, rlimits, RuntimeMaxSec), seccomp-bpf syscall blocklist, supply chain env vars, telemetry suppression.
  - 145-02: complete — Claude-level deny rules for sensitive paths, enableAllProjectMcpServers=false, extended nono deny list with package registry tokens and cloud credentials.
  - 145-03: pending — nix-mineral hardening integration (separate phase, requires new flake input).

## Planned Phase 144
- Phase 144: GSD — High-Impact Security + Core Dev-Agent Ops Remediation — 1 plan, added 2026-03-24
  - 144-01: pending — Address all High fresh-eyes review issues: supported-path egress control, enforced control-plane/workspace separation, dev-agent lifecycle hardening, and doc/example convergence. `dev-agent` remains a first-class public use case.

## Phase 95 Status
- Phase 95: Agent instructions for NixOS infrastructure development — 1 plan, completed 2026-03-16
  - 95-01: complete — Added four AGENTS.md guidance sections, created `.claude/skills/nix-module/SKILL.md` and `.claude/skills/nix-test/SKILL.md`, slimmed CLAUDE.md workflow duplication, validated with `nix flake check`, and updated `.test-status`.

## Phase 90 Status
- Phase 90: README polish — 1 plan, completed 2026-03-16
  - 90-01: complete — Scrubbed personal identifiers (dangirsh, claw-swap, parts) from 5 files, fixed TODO and broken .planning/ link, updated assertion counts from 30+ to 50+, added missing modules (users.nix, service-types.nix, dev-agent.nix) and hyperlinks (llm-agents.nix, zmx, home-manager), modernized AGENTS.md service template to neurosys.services API.

## Phase 94 Status
- Phase 94: Capability abstraction critical review — 1 plan, completed 2026-03-16
  - 94-01: complete — Audited old vs new module overhead from git history, checked real host option usage, stress-tested interface stability (kopia/systemd-run), surveyed 6 ecosystem repos for precedent, and produced a REVERT recommendation with concrete revert scope and effort estimate.

## Next — March 2026 Comprehensive Overhaul (Phases 150-156)
Phases 76 and 144 superseded. Optimized execution order (crosstalk-minimized):

| Order | Phase | Name | Size | Deps |
|-------|-------|------|------|------|
| 1 | 150 | Relocate Private Concerns | S-M | none |
| 1 | 151 | Repo Hygiene (git only, headers deferred) | S | none |
| 2 | 152 | User Model + Sandbox Overhaul (merged 151+154) | **L** | 150 |
| 3 | 153 | Base System & Networking Simplification | M | 150, 152 |
| 3 | 154 | Deploy & Examples Rework | M | 150, 152 |
| 4 | 155 | tsurf CLI & Commit Tooling | M | 150, 152 |
| 5 | 156 | Final Polish — Guardrails, Headers, Docs (merged 157+158) | M | all |

Key merges to avoid thrashing:
- Old 151 (user model) + old 154 (sandbox overhaul) → new 152 (avoid double-rewriting agent-sandbox.nix)
- Old 157 (guardrails) + old 158 (docs) + deferred file headers → new 156 (single final pass)
- Old 150 file headers → deferred to 156 (avoid writing headers on files about to be deleted/rewritten)

## Accumulated Context

### Roadmap Evolution
- Phase 85 completed: Service Type Framework — registry-driven service typing now powers dashboard derivation, internal port protection, and default hardening.
- Phase 86 completed: Feature Abstraction Layer — `neurosys.backup` and `neurosys.sandbox` capability interfaces shipped. Implementations migrated to `modules/backup/` and `modules/sandbox/`.
- Phase 88 completed: Guix Port Feasibility Study — NO-GO (immediate pivot).
- Phase 90 completed: README polish — docs aligned with implementation, personal identifiers removed.
- Phase 91 completed: Backup Abstraction Proof — borgmatic alternative implementation.
- Phase 92 completed: Sandbox Abstraction Proof — bubblewrap alternative implementation.
- Phase 94 completed: Capability Abstraction Critical Review — recommendation is REVERT to concrete modules for current repo scale.
- Phase 95 completed: Agent instructions for NixOS infrastructure development — AGENTS.md enriched, CLAUDE.md slimmed, and `/nix-module` + `/nix-test` skills added.
- Phase 96 added: Fix dev-agent systemd service AccessDenied error - systematically identify which hardening setting blocks zmx/claude execution, implement proper fix maintaining system service architecture with appropriate security hardening.
- Phase 97 completed: Service Types Critical Review — REVERT recommendation. 154-line framework provides near-zero value; direct per-module declarations are simpler.
- Phase 98 completed: Simplicity Pass — service-types.nix framework reverted (Phase 97 REVERT executed). Direct dashboard entries restored, manual internalOnlyPorts, docs updated.
- Phase 99 added: Documentation Optimization — Honesty, Completeness, Minimalism. Full audit of docs, code comments, and @decision annotations against codebase reality.
- Phase 100 in progress: 100-01 and 100-02 completed — trust-fix cleanup shipped and dashboard registrations moved out of core networking into dashboard module ownership.
- Phase 144 added: GSD high-impact remediation queued from the March 24 fresh-eyes review. dev-agent stays in the supported public story; the phase focuses on egress control, control-plane/workspace separation, dev-agent lifecycle hardening, and doc/example convergence.
- Phase 145 added: Ecosystem Review Security Hardening — implement top findings from 2026-03-24 review of 10 agent sandbox/Nix tooling repos (clampdown, tekton, ai-jail, gleisner, nsjail, sandboxec, Trail of Bits devcontainer, awesome-claude-code-security, rigup.nix, best-of-nix). Three tiers: systemd hardening properties + supply chain env vars, egress filtering + seccomp + protected workdir paths, Nix tooling integration.
- Phase 146 completed: Generate comprehensive technical specification of core features and security model — 13 spec files with 366+ uniquely IDed claims (SEC-, SBX-, NET-, SCR-, AGT-, IMP-, BAK-, DEP-, BAS-, USR-, EXT-, TST-) in ./spec/.
- Phase 147 added: Bolster test cases to validate implementation meets spec — tie each test to a spec claim ID in comments.
- Phase 157 added: Codebase complexity audit — find and prioritize cleanup targets
- Phase 158 added: Evaluate self-hosted Tailscale alternatives (headscale, wg-easy) — research report with exec summary, pros/cons, and migration difficulty estimates. No code changes.
- Phase 159 completed: Cut Public Repo to Minimal Core — public fixtures now model minimal core behavior, maintainer-only `spec/` content is removed from the public tree, `QUICKSTART.md` is the newcomer path, and all public docs/examples consistently describe extras as opt-in.
- Phase 160 completed: Harden Core Dependency Trust Boundary (review finding #3) — explicit firewall/SSH and critical sysctl trust anchors now live in tsurf modules, SECURITY.md documents inherited modules (`srvos`, `nix-mineral`) as defense-in-depth, and `nono` now builds from pinned upstream source rather than an unverified prebuilt binary.
- Phase 162 completed: Migrate to headscale — opt-in `modules/headscale.nix` with tsurf.headscale.enable toggle, localhost:8080 with nginx TLS proxy, embedded DERP/STUN, SQLite persisted under impermanence, ACL policy via environment.etc, 6 eval checks, Tailscale doc/comment updates.
- Phase 163 added: tsurf-status CLI — tree-based host/service/cost overview replacing tsurf-status.sh. Parallel SSH queries, agent+service tree with status/uptime/type/sandbox, system metadata footer (version, last deploy, backup status, disk, 24h/7d API costs). Consolidates old phases 163-166 into single unified status command.

### Decisions
- [88-01]: GUIX-88: NO-GO (immediate pivot) -- Guix migration is feasible but strategically inferior now.
- [85-01]: SVC-85-01/02/03 implemented -- central typed registry with additive dashboard derivation, merge-friendly internal-only port registry, and conservative `.service` hardening defaults via `mkDefault`.
- [86]: CAP-86 — Two capability abstractions (backup, sandbox) shipped. Three capabilities (sync, containers, dashboard) NO-GO. Core features confirmed non-swappable.
- [90-01]: DOC-90 — README/AGENTS.md now use neurosys.services API in documentation; assertion counts reflect actual 50+ checks.
- [94-01]: CAP-94 — Critical review recommends REVERT of backup/sandbox capability interfaces; concrete modules plus explicit invariants are lower complexity with equivalent practical value.
- [95-01]: DOC-95 — Workflow guidance moved into AGENTS.md, CLAUDE.md reduced to identity/hard rules, and new `/nix-module` + `/nix-test` skills established for on-demand execution.
- [97-01]: SVC-97 — REVERT neurosys.services framework. Dashboard derivation is a key rename, port auto-derivation saves 3 lines, hardening defaults overridden by most consumers. No ecosystem precedent. Typed taxonomy belongs in docs, not NixOS options.
- [100-01]: CRR-100 — Public template trust fixes prioritize explicit placeholders (`lib.fakeHash`), removal of stale file references, and removing no-op public activation wiring while preserving reusable overlay scripts.
- [100-02]: CRR-100 — Dashboard ownership moved to `extras/dashboard.nix`; `modules/networking.nix` no longer references `services.dashboard.entries`, while `module = "networking.nix"` preserves dashboard grouping labels.
- [144-01]: DEVAGENT-144 — The public repo should keep `dev-agent` as a core supported path. Remediation must harden and operationalize that path rather than hiding or de-scoping it.
- [159-01]: COREMIN-159 — Public default fixtures should demonstrate minimal core modules only; extras and Home Manager user overlays are opt-in, and CASS must default disabled unless explicitly enabled.
- [159-02]: COREMIN-159 — Maintainer-oriented claim-level spec documents should not live in the public newcomer surface; onboarding should begin at `QUICKSTART.md` and route advanced implementation details through architecture/security docs and private overlay docs.
- [159-03]: COREMIN-159 — Documentation and examples must match the shipped minimal-core behavior end-to-end: README newcomer path starts at `QUICKSTART.md`, extras are opt-in everywhere, and the generic launcher is positioned as the advanced extension API.
- [160-01]: SEC-160 — Core security claims must be self-backing in tsurf-owned modules. `srvos` and `nix-mineral` defaults are treated as defense-in-depth and documented transparently, not as unspoken trust anchors.
- [160-02]: SEC-160-05 — The `nono` sandbox enforcer in the launch path is built from pinned Rust source (`buildRustPackage`) instead of consuming a prebuilt release artifact.
