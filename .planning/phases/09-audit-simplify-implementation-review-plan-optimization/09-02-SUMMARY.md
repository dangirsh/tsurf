---
phase: 09
plan: 02
title: Roadmap Revision — Absorb Phase 2.1, Update Phase 4/5 Goals
status: complete
executor: Implementer (worktree phase09-02)
date: 2026-02-15
subsystem: infra
tags: roadmap, planning, docs
---

# Plan 09-02 Summary: Roadmap Revision — Absorb Phase 2.1, Update Phase 4/5 Goals

## One-liner

Roadmap revised: Phase 2.1 absorbed, Phase 4 gets container hardening, Phase 5 absorbs dev tools

## Accomplishments

### Task 1: Update ROADMAP.md

**Phase 2.1 absorption:**
- Phase list entry changed to [x] with note: "Absorbed into Phase 9 (mutableUsers, execWheelOnly applied; settings module dropped as unnecessary; dev tools moved to Phase 5)"
- Phase 2.1 Goal rewritten to reflect dispositions: settings module dropped, mutableUsers+execWheelOnly in 9-01, dev tools/ssh-agent to Phase 5
- Success criteria updated with dispositions: SC1 DROPPED, SC2 MOVED to Phase 5, SC3 SPLIT, SC4 covered by 9-01
- Plans section: "Absorbed into Phase 9 — no separate plans needed"

**Phase 4 updates:**
- Added success criterion 5: container security hardening (read-only rootfs, cap-drop, no-new-privileges, resource limits)
- Added note referencing 09-RESEARCH.md for implementation details (extraOptions pattern)

**Phase 5 updates:**
- Added success criterion 6: programs.ssh.startAgent = true
- Added note about minimal system packages (git, curl, wget, rsync, jq, tmux) going into modules/base.nix
- Added TODOs: ssh-agent, dev tool packages from Phase 2.1 as home-manager packages

**Execution order & Progress table:**
- Execution order updated: 1 -> 2 -> 3 -> 3.1 -> 9 -> 4 -> 5 -> 6 -> 7 (2.1 absorbed, 8 complete)
- All completed phases marked [x] in phase list (1, 2, 2.1, 3, 3.1, 8)
- Progress table: Phase 2 (2/2, complete), Phase 2.1 (N/A, absorbed), Phase 9 (1/2, in progress)

### Task 2: Update STATE.md

**Current Position:**
- Phase 9 of 9, Plan 2 of 2
- Current focus: security hardening complete, roadmap revision in progress
- Status: Plan 01 complete, Plan 02 executing
- Last activity: Phase 9 Plan 01 complete (SSH hardening, mutableUsers/execWheelOnly)

**Roadmap Evolution:**
- Added: Phase 2.1 absorbed into Phase 9 (settings module dropped, mutableUsers+execWheelOnly in 9-01, dev tools to Phase 5)
- Added: Phase 4 updated with container hardening
- Added: Phase 5 updated to absorb dev tools, ssh-agent, SSH client config, direnv

**Completed Phases:**
- Phase 2: updated to 2/2 plans complete, deployment verified
- Added: Phase 2.1 (absorbed into Phase 9)
- Added: Phase 8 (review complete)
- Added: Phase 9 (in progress, 09-01 complete, 09-02 executing)

**Decisions:**
- [09]: Phase 2.1 absorbed — settings module unnecessary for single-host config
- [09]: SSH moved to Tailscale-only — port 22 removed from public firewall
- [09]: Docker container hardening deferred to Phase 4 (scope: neurosys base only)

**Blockers/Concerns:**
- Added: [RESOLVED] Phase 2.1 scope creep — absorbed after re-evaluation

**Session Continuity:**
- Updated to: Phase 9 Plan 02 executing

## Commits

1. **7d44ee1** - `docs(09-02): revise roadmap — absorb Phase 2.1, update Phase 4/5 goals`
   - ROADMAP.md: Phase 2.1 absorption, Phase 4/5 updates, execution order, progress table

2. **7a83f2c** - `docs(09-02): update state — Phase 9 progress, Phase 2.1 absorbed`
   - STATE.md: current position, roadmap evolution, completed phases, decisions, blockers

3. **[pending]** - `docs(09-02): add plan summary`
   - This summary file

## Files Modified

- `.planning/ROADMAP.md` - Phase 2.1 absorption, Phase 4/5 success criteria updates, execution order, progress table
- `.planning/STATE.md` - Current position, roadmap evolution, completed phases, decisions
- `.planning/phases/09-audit-simplify-implementation-review-plan-optimization/09-02-SUMMARY.md` - This file

## Self-Check

- [x] ROADMAP.md: Phase 2.1 marked [x] and absorbed
- [x] ROADMAP.md: Phase 2.1 goal rewritten with dispositions
- [x] ROADMAP.md: Phase 4 success criterion 5 added (container hardening)
- [x] ROADMAP.md: Phase 5 success criterion 6 added (ssh-agent) + TODOs
- [x] ROADMAP.md: Execution order updated (2.1 absorbed, 8 complete)
- [x] ROADMAP.md: Progress table updated (Phase 2 complete, 2.1 absorbed, 9 in progress)
- [x] ROADMAP.md: All completed phases marked [x]
- [x] STATE.md: Current position updated to Phase 9 Plan 2
- [x] STATE.md: Current focus reflects roadmap revision
- [x] STATE.md: Roadmap evolution entries added
- [x] STATE.md: Completed phases updated (Phase 2, 2.1, 8, 9)
- [x] STATE.md: Decisions added ([09] entries)
- [x] STATE.md: Blockers updated (Phase 2.1 resolved)
- [x] STATE.md: Session continuity updated
- [x] SUMMARY.md created with proper frontmatter and structure
- [x] All changes are docs-only (no code changes)
- [x] Ready for merge to main

## Next Steps

1. Commit this summary
2. Merge branch to main via fast-forward
3. Push to remote
4. Phase 9 complete — proceed to Phase 4 (Docker Services + Ollama)
