---
phase: 17-hardcore-simplicity-security-audit
plan: 03
subsystem: docs
tags: [claude-md, security, conventions]
duration: 10min
completed: 2026-02-19
---

# Phase 17 Plan 03: CLAUDE.md Guardrails — Security + Simplicity Conventions

**Updated CLAUDE.md with accurate project structure, security conventions, simplicity rules, and module change checklist.**

## Accomplishments
- Replaced outdated project structure with accurate layout (14 modules, 7 home configs, 2 packages, deploy script, secrets)
- Updated key decisions to reflect sops-nix, Tailscale-only SSH, kernel hardening, llm-agents overlay
- Updated conventions with openFirewall=false pattern, @decision annotations, clone-only repos
- Added Security Conventions section with 10 "Never"/MUST rules preventing regression of Phase 17 fixes
- Added Accepted Risks subsection documenting SEC3, SEC5, SEC9, SEC11 with mitigations
- Added Simplicity Conventions section with YAGNI, no dead code, one source of truth rules
- Added Module Change Checklist with 6-point verification (port exposure, secrets, services, sandbox, credentials, validation)

## Task Commits
1. **Task 1 + Task 2: Full CLAUDE.md rewrite** — `27bc573`

## Files Modified
- `CLAUDE.md` — Complete rewrite of project structure, key decisions, conventions; three new sections added

## Decisions Made
- Combined Task 1 (project structure update) and Task 2 (guardrails) into a single commit since both modify CLAUDE.md
- Pre-flight check: 17-01-SUMMARY.md and 17-02-SUMMARY.md both exist and were consulted

## Deviations from Plan
None — plan executed exactly as specified.

## Issues Encountered
None

## Next Phase Readiness
Plan 17-03 outputs are complete; repository is ready for Plan 17-04 (Docker audit + sandbox assessment).

## Self-Check: PASSED
