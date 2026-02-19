---
phase: 17-hardcore-simplicity-security-audit
plan: 02
subsystem: infra
tags: [nix, security, ssh, credentials]
duration: 15min
completed: 2026-02-19
---

# Phase 17 Plan 02: SSH Hardening + Credential Leak Fix + Restic Excludes

**Eliminated root SSH from public internet, fixed credential leaks in repo cloning, and prevented token backup exposure.**

## Accomplishments
- Removed port 22 from `allowedTCPPorts` — SSH now accessible only via Tailscale (`trustedInterfaces`)
- Added build-time assertion preventing port 22 from being re-added to the public firewall
- Replaced token-in-URL clone pattern (`https://$TOKEN@github.com/...`) with `git credential.helper store` using a temporary file — PAT no longer appears in process arguments, journal logs, or `.git/config`
- Added `.git/config` to restic backup excludes to prevent old token-bearing configs from reaching B2
- Updated `@decision NET-01` and `NET-04` annotations to reflect Tailscale-only SSH

## Task Commits
1. **Task 1 + Task 2: SSH hardening, credential fix, restic excludes** — `7f489ba`

## Files Modified
- `modules/networking.nix` — Removed port 22 from allowedTCPPorts, added port 22 assertion, updated @decision comments
- `modules/repos.nix` — Replaced token-in-URL with credential.helper store pattern
- `modules/restic.nix` — Added `.git/config` to exclude list

## Decisions Made
- Combined both tasks into a single commit since all changes are security-hardening and tightly related
- Kept `PermitRootLogin = "prohibit-password"` unchanged (deploy pipeline needs root SSH via Tailscale)

## Deviations from Plan
None — plan executed exactly as specified.

## Issues Encountered
None

## Next Phase Readiness
Plan 17-02 outputs are complete and validated; repository is ready to proceed to Plan 17-03.

## Self-Check: PASSED
