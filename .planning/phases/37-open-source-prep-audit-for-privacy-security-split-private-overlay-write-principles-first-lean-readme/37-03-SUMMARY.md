---
phase: 37-open-source-prep-audit-for-privacy-security-split-private-overlay-write-principles-first-lean-readme
plan: 03
subsystem: docs
tags: [documentation, open-source, readme]
key-files:
  created: []
  modified: [README.md]
key-decisions:
  - "Agent tooling section is the most detailed — primary differentiator for public audience"
  - "Sandbox policy shown as table derived from actual bwrap args in agent-compute.nix"
  - "Personal deployment specifics (VPS IPs, recovery ops) removed; reference private-overlay.md"
duration: ~5min
completed: 2026-02-27
---

# Phase 37-03: Lean Public README Summary

**Replaced 391-line operator manual with 98-line principle-first public README.**

## Performance
- **Duration:** ~5min
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- README.md rewritten from 391 → 98 lines
- Opens with one-line description (no preamble)
- Design Principles section immediately after one-liner
- Modules table: 13 rows covering all public modules
- Agent Tooling section: CLI list, agent-spawn usage, sandbox policy table derived from actual bwrap args
- Secret Proxy section: 2-sentence explanation
- Networking table: 8 ports with access level
- Quick Start: 4 numbered steps, no hand-holding
- Flake Inputs table: 9 rows
- Zero personal identifiers (dangirsh, IPs, real name)
- Two links to docs/private-overlay.md

## Task Commits
1. **Task 1: Rewrite README.md** - `22197a3` (docs)

## Files Created/Modified
- `README.md` — Lean public-facing README, rewritten from scratch

## Decisions Made
- None — followed plan as specified

## Deviations from Plan
None

## Issues Encountered
None

## Next Phase Readiness
Phase 37 complete (all 3 plans executed). Public repo is open-source ready.

## Self-Check: PASSED
- README.md: 98 lines (target 60-150 ✓)
- agent-spawn mentioned: 4 times ✓
- Sandbox policy table: present, derived from agent-compute.nix ✓
- Links to private-overlay.md: 2 ✓
- Opens with one-liner: ✓
- PII check (dangirsh, 161.97, 135.125, dan@, Dan Girshovich): 0 matches ✓
- Modules table: 13 rows (min 8 ✓)
