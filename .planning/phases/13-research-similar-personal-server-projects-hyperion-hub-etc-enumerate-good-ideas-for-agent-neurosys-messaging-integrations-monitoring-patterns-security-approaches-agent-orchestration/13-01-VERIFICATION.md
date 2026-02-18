---
phase: 13-research-similar-personal-server-projects
plan: 01
verified: 2026-02-18T15:50:43Z
status: gaps_found
score: 4/5 must-haves verified
re_verification: false
gaps:
  - truth: "Approved ideas are captured as new phases or TODOs under existing phases in ROADMAP.md"
    status: partial
    reason: "Phase 14 and Phase 15 are correctly added to ROADMAP.md for the two substantive adopted ideas (ntfy+Prometheus+Grafana, CrowdSec). However, three adopted ideas marked as 'quick tasks' (Claude Code Agent Teams, Tailnet Key Authority, MCP-NixOS evaluate) are tracked only in STATE.md Quick Tasks Pending — not in ROADMAP.md as TODOs under any existing phase. The PLAN explicitly specifies: 'add a TODO line under that phase's Plans section' for ideas that map to existing phases."
    artifacts:
      - path: ".planning/ROADMAP.md"
        issue: "No TODO entries for Agent Teams (Phase 5/6), TKA (Phase 3/11), or MCP-NixOS (could go under Phase 13 or any active phase)"
      - path: ".planning/STATE.md"
        issue: "Quick tasks exist here correctly but ROADMAP.md is the canonical source per PLAN.md requirements"
    missing:
      - "Add TODO(from-research) entry under Phase 5 or Phase 6 in ROADMAP.md for Agent Teams env var"
      - "Add TODO(from-research) entry under Phase 3 or Phase 11 in ROADMAP.md for Tailnet Key Authority"
      - "Add TODO(from-research) entry under Phase 13 or an appropriate phase in ROADMAP.md for MCP-NixOS evaluation"
---

# Phase 13: Research Similar Personal Server Projects — Verification Report

**Phase Goal:** Survey the ecosystem of NixOS homelab and personal server projects, curate a catalog of 11 ideas across 6 categories (monitoring, messaging, security, agent orchestration, backup, reverse proxy), and present findings to the user for cherry-picking — approved ideas become new phases or TODOs in the roadmap
**Verified:** 2026-02-18T15:50:43Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User has seen all 11 research ideas across 6 categories with effort/value ratings and NixOS implementation details | VERIFIED | 13-RESEARCH.md contains all 11 ideas across 6 categories (Monitoring, Messaging, Security, Agent Orchestration, Backup, Reverse Proxy) with effort/value/NixOS patterns. 13-01-SUMMARY.md confirms all 11 were presented with dispositions recorded. |
| 2 | User has approved, deferred, or rejected each idea | VERIFIED | SUMMARY.md: 5 adopted (1,2,4,6,+TKA), 1 evaluated (3), 4 deferred (5,8,9,11), 2 rejected (7,10). All 11 original ideas (#1-11) have explicit dispositions plus an extra TKA idea (#12) that emerged from discussion. All 5 open questions answered. |
| 3 | Approved ideas are captured as new phases or TODOs under existing phases in ROADMAP.md | PARTIAL | Phase 14 (ntfy + Prometheus+Grafana) and Phase 15 (CrowdSec) are fully specified in ROADMAP.md with Goals, Dependencies, and Success Criteria. Three adopted "quick task" items (Agent Teams, Tailnet Key Authority, MCP-NixOS evaluate) appear only in STATE.md Quick Tasks Pending — not as TODO entries in ROADMAP.md as required by PLAN.md Task 2 instructions. |
| 4 | Deferred ideas are documented with conditions for revisiting | VERIFIED | SUMMARY.md Deferred table has explicit revisit conditions for all 4 deferred items: Uptime Kuma (if Grafana insufficient), Caddy (when DNS routing needed), Authelia (when internet-facing), Loki+Alloy (when specific log search needed). |
| 5 | Architecture patterns and pitfalls from research are preserved for future reference | VERIFIED | SUMMARY.md sections "Architecture Patterns Preserved" (layered monitoring, notification hierarchy, vars.nix pattern) and "Pitfalls Preserved" (over-engineering, notification fatigue, orchestration creep, Promtail EOL) are both substantive and match the source content in 13-RESEARCH.md. |

**Score:** 4/5 truths verified (1 partial)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `13-01-SUMMARY.md` | Record of user decisions on all 11 ideas | VERIFIED | File exists (89 lines). Contains all 11 ideas with dispositions, all 5 Q&A pairs, architecture patterns, pitfalls, new phases created, and quick tasks list. |
| `.planning/ROADMAP.md` | Updated with new phases or TODOs for approved ideas | PARTIAL | Phase 14 and Phase 15 entries exist and are substantive (Goals, Dependencies, Success Criteria fully defined). Agent Teams, TKA, MCP-NixOS quick tasks are absent from ROADMAP.md entirely — captured in STATE.md only. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| 13-RESEARCH.md priority ranking (ideas 1+2) | ROADMAP.md Phase 14 | User approval — monitoring/notifications | WIRED | Phase 14 entry at line 287 of ROADMAP.md is fully specified with ntfy + Prometheus + Grafana + Success Criteria |
| 13-RESEARCH.md priority ranking (idea 6) | ROADMAP.md Phase 15 | User approval — CrowdSec | WIRED | Phase 15 entry at line 303 of ROADMAP.md is fully specified with CrowdSec goal and Success Criteria |
| 13-RESEARCH.md priority ranking (ideas 4, 3, +TKA) | ROADMAP.md TODO entries | User approval — quick tasks | NOT_WIRED | Agent Teams (#4), MCP-NixOS (#3), TKA (bonus) approved as quick tasks but appear only in STATE.md Quick Tasks Pending, not in ROADMAP.md |

### Requirements Coverage

No REQUIREMENTS.md entries mapped to Phase 13 (research advisory phase).

### Anti-Patterns Found

No anti-patterns found. This is a planning-only phase — no NixOS config files were modified. STATE.md confirms: "No NixOS configuration files modified (planning phase only)."

### Human Verification Required

None required. All verification performed programmatically against planning documentation.

### Gaps Summary

The phase largely achieved its goal. The research was thorough (13-RESEARCH.md at 455 lines covers 6 categories, 11+ ideas, reference projects, patterns, pitfalls), the user presentation was comprehensive (all 11 ideas with ratings and NixOS details), all decisions were captured (SUMMARY.md), and the two substantive new phases (14 and 15) are properly specified in ROADMAP.md.

The single gap is that three "quick task" adoptions (Claude Code Agent Teams env var, Tailnet Key Authority setup, MCP-NixOS evaluate) were captured in STATE.md Quick Tasks Pending but NOT added as TODO entries in ROADMAP.md. The PLAN.md Task 2 instructions explicitly specify adding TODO lines under existing phases in ROADMAP.md for approved ideas that don't warrant a new phase. These quick tasks map naturally to existing phases:
- Agent Teams env var -> Phase 5 (agent-spawn) or Phase 6 (agent tooling)
- TKA -> Phase 3 (networking/Tailscale) or Phase 11 (agent sandboxing/security)
- MCP-NixOS evaluate -> Phase 13 itself or as a general TODO

This gap is minor — STATE.md faithfully tracks the pending quick tasks and they won't be lost. However, ROADMAP.md is the canonical planning document, and completeness requires these appear there too.

---

_Verified: 2026-02-18T15:50:43Z_
_Verifier: Claude (gsd-verifier)_
