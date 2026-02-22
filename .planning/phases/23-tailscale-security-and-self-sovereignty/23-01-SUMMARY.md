---
phase: 23-tailscale-security-and-self-sovereignty
plan: 01
subsystem: infra
tags: [tailscale, tka, firewall, security, documentation]

requires:
  - phase: 17-hardcore-simplicity-security-audit
    provides: "Port 22 firewall hardening and SSH Tailscale-only policy"
provides:
  - "Port 22 assertion active (build-time prevention of public SSH exposure)"
  - "TKA operational procedures documented in recovery runbook"
  - "Auth key rotation policy documented"
affects: [23-02, disaster-recovery]

tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - docs/recovery-runbook.md

key-decisions:
  - "Port 22 hardening was already in committed state — only local uncommitted changes had the temporary regression"
  - "TKA appendix numbered as Section 13 in recovery runbook, following existing hierarchy"

duration: 5min
completed: 2026-02-22
---

# Phase 23 Plan 01: Restore Port 22 Hardening + TKA Runbook Summary

**Port 22 firewall assertion verified active in committed state; TKA operational appendix (init, signing, disablement secrets, auth key rotation, DR implications) added to recovery runbook**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-22T16:53:00Z
- **Completed:** 2026-02-22T16:58:15Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Verified port 22 is NOT in allowedTCPPorts and build-time assertion is active (committed state was already correct — local uncommitted changes had the temporary regression)
- `nix flake check` passes with port 22 assertion enforced
- Recovery runbook Appendix 13 added: TKA overview, initialization procedure, signing new devices, disablement secret storage, auth key rotation policy, disaster recovery implications

## Task Commits

1. **Task 1: Restore port 22 firewall hardening** — no commit needed (committed state already correct; stashed local uncommitted TEMPORARY changes)
2. **Task 2: TKA operational procedures in recovery runbook** — `c17bb2f` (docs)

## Files Created/Modified
- `docs/recovery-runbook.md` — Added Appendix 13: Tailnet Key Authority (TKA) with 6 subsections

## Decisions Made
- Port 22 hardening was already in the committed git state — the TEMPORARY changes were only in the local working tree (never committed). Stashed and discarded.
- TKA appendix follows existing runbook numbering as Section 13

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Port 22 already hardened in committed state**
- **Found during:** Task 1 (port 22 firewall hardening)
- **Issue:** Plan expected port 22 to be in allowedTCPPorts in the committed code, but the committed state already had port 22 removed and the assertion active. The TEMPORARY changes were only in the local working tree (unstaged).
- **Fix:** Stashed the local uncommitted changes instead of editing the file. Verified committed state passes all checks.
- **Files modified:** None (git stash of local changes)
- **Verification:** `nix flake check` passes, `grep` confirms assertion active and no TEMPORARY comments
- **Committed in:** N/A (no code change needed)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** No scope change. Task 1 was simpler than expected because the committed state was already correct.

## Issues Encountered
None

## Next Phase Readiness
- Port 22 hardening verified — ready for Plan 23-02 operational TKA execution
- Recovery runbook has complete TKA procedures for reference during Plan 23-02

---
*Phase: 23-tailscale-security-and-self-sovereignty*
*Completed: 2026-02-22*
