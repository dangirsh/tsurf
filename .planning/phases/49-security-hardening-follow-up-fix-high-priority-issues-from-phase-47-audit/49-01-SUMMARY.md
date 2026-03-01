---
phase: 49-security-hardening-follow-up
plan: 01
subsystem: infra
tags: [security, bootstrap, firewall, nftables, sops]

requires:
  - phase: 47
    provides: Security audit findings (HIGH priority issues)
provides:
  - Bootstrap scripts free of hardcoded credentials
  - Complete internalOnlyPorts assertion coverage (23 ports)
  - Accepted risk documentation for git history exposure
affects: [networking, bootstrap, security-conventions]

tech-stack:
  added: []
  patterns: [required-env-var-pattern, random-ephemeral-password]

key-files:
  created: []
  modified:
    - scripts/bootstrap-contabo.sh
    - scripts/bootstrap-ovh.sh
    - modules/networking.nix
    - CLAUDE.md

key-decisions:
  - "SEC49-01: Bootstrap passwords in git history accepted as minimal risk (ephemeral, Ubuntu wiped)"
  - "Contabo password uses bash :? operator (required env var) instead of default value"
  - "OVH password uses openssl rand -base64 16 (runtime generation) instead of hardcoded string"
  - "Matrix/OpenClaw/Spacebot/mautrix ports added to public repo internalOnlyPorts for comprehensive coverage"

patterns-established:
  - "Required env var pattern: ${VAR:?ERROR message} for credentials that must come from operator"
  - "Random ephemeral password: openssl rand for one-time-use credentials"

duration: 2min
completed: 2026-03-01
---

# Phase 49 Plan 01: Fix HIGH Priority Security Issues Summary

**Removed hardcoded passwords from bootstrap scripts, expanded internalOnlyPorts to 23 entries covering all known service ports, documented git history exposure as accepted risk SEC49-01**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-01T12:47:49Z
- **Completed:** 2026-03-01T12:50:00Z
- **Tasks:** 6 (A-F)
- **Files modified:** 4

## Accomplishments
- Bootstrap-contabo.sh: `CONTABO_PASS` changed from `:-` (default) to `:?` (required) operator — no more hardcoded password
- Bootstrap-ovh.sh: `OVH_NEW_PASS` changed from hardcoded string to `openssl rand -base64 16` runtime generation + openssl precondition check
- Networking.nix: 11 new ports added to `internalOnlyPorts` map (6167, 18789-18794, 19898, 29317, 29318, 29328) — total now 23
- CLAUDE.md: SEC49-01 accepted risk documents git history exposure of removed passwords
- `nix flake check` passes for both nixosConfigurations (neurosys + ovh)

## Task Commits

All tasks committed atomically:

1. **Tasks A-D: Remove passwords + expand ports + document risk** - `5146f43` (fix)

## Files Created/Modified
- `scripts/bootstrap-contabo.sh` — Replace hardcoded default with required env var
- `scripts/bootstrap-ovh.sh` — Replace hardcoded password with openssl random generation + add precondition check
- `modules/networking.nix` — Add 11 missing service ports to internalOnlyPorts assertion map
- `CLAUDE.md` — Add SEC49-01 accepted risk for git history password exposure

## Decisions Made
- Bash `:?` operator chosen over `:+` or external validation — cleanest error UX, standard bash idiom
- `openssl rand -base64 16` chosen for OVH — available on all admin machines, truly random, sufficient for ephemeral PAM password
- All 11 missing ports added to public repo (including OVH-only and private-overlay service ports) — comprehensive assertion coverage

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Private Overlay Follow-ups (Task F)

Three follow-up items documented for separate private overlay session:
1. **Matrix Conduit registration verification** — verify `matrix-registration-token` sops secret is real (not placeholder); test registration endpoint; if placeholder, set `allow_registration = false`
2. **Docker image pinning** — pin 6 OpenClaw + 1 Spacebot container images to SHA256 digests using `crane digest`
3. **Spacebot.nix comment** — port 19898 comment is now accurate (was inaccurate before this fix)

## Next Phase Readiness
- Phase 49 complete for public repo scope
- Private overlay follow-ups (Matrix registration, Docker image pinning) ready for separate session

---
*Phase: 49-security-hardening-follow-up*
*Completed: 2026-03-01*
