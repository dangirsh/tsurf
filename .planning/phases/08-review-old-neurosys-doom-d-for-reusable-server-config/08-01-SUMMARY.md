---
phase: 08-review-old-neurosys-doom-d-for-reusable-server-config
plan: 01
subsystem: infra
tags: [nixos, neurosys, migration, audit]

requires:
  - phase: 08-RESEARCH
    provides: 7 server-relevant candidates from dangirsh/neurosys and dangirsh/.doom.d
provides:
  - TODOs in ROADMAP.md for approved candidates (Phases 2.1, 5, 6)
  - Phase 2.1 inserted for base system fixups
  - Syncthing device IDs captured for Phase 6
  - Direnv requirement added to Phase 5
affects: [phase-2.1, phase-5, phase-6]

tech-stack:
  added: []
  patterns: [centralized-settings-module, declarative-syncthing, immutable-users]

key-files:
  created:
    - .planning/phases/08-review-old-neurosys-doom-d-for-reusable-server-config/08-01-SUMMARY.md
  modified:
    - .planning/ROADMAP.md
    - .planning/STATE.md

key-decisions:
  - "Approve candidates 1,2,3,5,6 — reject candidates 4,7"
  - "Candidate 1 (Syncthing): structural pattern only, fresh params in Phase 6"
  - "System packages: agent-focused filter — keep tools that help AI agents, remove human-only tools"
  - "Phase 2 already done — create Phase 2.1 fixup for settings, packages, SSH hardening"
  - "Direnv: yes with nix-direnv for cached evaluations to minimize cd latency"
  - "SSH hardening verified current for NixOS 25.11 — add security.sudo.execWheelOnly bonus"
  - "Teleport: not needed"

duration: 15min
completed: 2026-02-15
---

# Phase 8 Plan 01: Present Neurosys Candidates for Cherry-Picking Summary

**7 candidates from dangirsh/neurosys reviewed — 5 approved (targeting Phases 2.1, 5, 6), 2 rejected, Phase 2.1 inserted as fixup phase**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-02-15
- **Completed:** 2026-02-15
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- All 7 candidates presented individually with full context and user approved/rejected each
- Phase 2.1 (Base System Fixups) inserted into roadmap for settings module, system packages, SSH hardening
- System packages researched and filtered to 16 agent-focused tools (removed human-only utilities like btop, htop, emacs, mosh)
- SSH hardening options verified current for NixOS 25.11 (no renames needed from 20.03)
- Syncthing device IDs captured (4 devices) for Phase 6 declarative config
- Direnv with nix-direnv added to Phase 5 for latency-minimized per-project envs

## Candidate Decisions

| # | Candidate | Decision | Target |
|---|-----------|----------|--------|
| 1 | Syncthing declarative config | **Approved** (pattern only, fresh params) | Phase 6 |
| 2 | Settings module (config.settings.*) | **Approved** | Phase 2.1 |
| 3 | System packages baseline | **Approved** (agent-focused, 16 packages) | Phase 2.1 |
| 4 | Nix settings (sandbox, max-jobs) | **Rejected** (defaults fine) | - |
| 5 | SSH hardening (mutableUsers, sudo, ssh agent) | **Approved** (all 3 + execWheelOnly) | Phase 2.1 |
| 6 | SSH client config (controlMaster, etc.) | **Approved** | Phase 5 |
| 7 | Tarsnap backup pattern | **Rejected** (decide fresh) | - |

## Open Question Answers

- **Q1 (Syncthing folders):** Single "Sync" folder now, paths deferred to Phase 6
- **Q2 (Device IDs):** 4 current devices:
  - MacBook-Pro.local: `LYQPMIK-QXAB6PL-T64O22N-GRNCANW-JYFZJJX-J5WGGR5-R2MQ5ZO-V23ZLQU`
  - DC-1: `UQFGSX2-MCX6RIN-F52HT5M-ERDKQOG-BRWDGCT-DGZIIFH-J27IREC-426NKAH`
  - Pixel 10 Pro: `YBHZJDE-2XWYQN2-LOONB2Z-UICZJAC-VNHP56V-LU4BPFW-KRCCPWX-AH5BXQY`
  - MacBook-Pro-von-Theda.local: `IBZ5C64-62IQ7U5-FWHCO6X-A6OL45G-JWQUBIW-56AT2AJ-P4GAG65-NIZGPAZ`
- **Q3 (Teleport):** Not needed
- **Q4 (Direnv):** Yes, with nix-direnv for cached evaluations (minimize cd latency)

## System Packages (Agent-Focused Baseline)

Approved 16 packages: curl, wget, zip/unzip, tree, rsync, ripgrep, fd, jq, yq-go, killall, lsof, tmux, git, file, shellcheck, sd

Removed (human-only): btop, htop, iotop, mtr, mosh, nmap, dig, emacs-nox, vim, pciutils, usbutils, sshfs, fzf, bat, eza, zoxide, dust, duf, ncdu, atuin

## Decisions Made
- Phase 2 already complete — fixup candidates go to new Phase 2.1 instead
- Syncthing: structural pattern only, configure fresh params in Phase 6 (don't port old values)
- System packages: agent-utility filter — keep tools AI agents use (ripgrep, fd, jq, shellcheck), remove human-only TUIs (btop, htop, emacs)
- SSH hardening: all 3 options verified current for NixOS 25.11, added `security.sudo.execWheelOnly = true` bonus

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Phase 2 already completed**
- **Found during:** Task 1 (candidate presentation)
- **Issue:** Plan assumed candidates 2,3,5 target Phase 2, but Phase 2 was already implemented
- **Fix:** Created Phase 2.1 as fixup phase for all Phase 2-targeted candidates
- **Files modified:** .planning/ROADMAP.md
- **Verification:** Phase 2.1 appears in roadmap between Phase 2 and Phase 3

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Phase 2.1 insertion was necessary to avoid modifying a completed phase. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 8 is complete (research/audit phase)
- TODOs are captured in ROADMAP.md under their target phases
- Phase 2.1 is ready for planning when needed
- Main execution continues with Phase 3.1 (Parts Integration)

---
*Phase: 08-review-old-neurosys-doom-d-for-reusable-server-config*
*Completed: 2026-02-15*
