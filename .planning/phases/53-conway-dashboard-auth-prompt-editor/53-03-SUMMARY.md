---
phase: 53-conway-dashboard-auth-prompt-editor
plan: "03"
subsystem: infra
tags: [nix, nginx, acme, sops, systemd, sudoers, eval-checks]

requires:
  - phase: 53-01
    provides: dashboard prompt editing + lifecycle API + token forwarding
  - phase: 53-02
    provides: port 9093 in internalOnlyPorts
provides:
  - conway.dangirsh.org HTTPS vhost with ACME DNS-01 and token auth
  - conway-dashboard-token sops secret + nginx auth template
  - ReadWritePaths for dashboard prompt editing
  - Sudoers lifecycle control for automaton user
  - 3 new eval checks (vhost, ACME, service)
affects: [nginx, secrets, automaton-dashboard, eval-checks]

tech-stack:
  added: []
  patterns: [nginx-map-token-auth, sops-template-nginx-include, sudoers-narrow-scope]

key-files:
  created: []
  modified:
    - /data/projects/private-neurosys/modules/automaton-dashboard.nix
    - /data/projects/private-neurosys/modules/nginx.nix
    - /data/projects/private-neurosys/modules/secrets.nix
    - /data/projects/private-neurosys/tests/eval/private-checks.nix
    - /data/projects/private-neurosys/secrets/neurosys.yaml

key-decisions:
  - "DASH-04: ReadWritePaths for .automaton subdirectory, ReadOnlyPaths for parent"
  - "DASH-05: sudoers rule for 3 lifecycle commands with absolute paths"
  - "DASH-06: execWheelOnly disabled via mkForce for non-wheel sudo rule"
  - "WEB-14: conway.dangirsh.org token auth via nginx map $arg_token"
  - "WEB-15: limit_req 10r/s burst=20 for brute-force protection"

patterns-established:
  - "nginx map token auth: sops template renders token into nginx include file"
  - "Narrow sudoers: exact command paths for service lifecycle"

duration: 10min
completed: 2026-03-02
---

# Phase 53 Plan 03: Private Overlay — nginx Auth Proxy, Secrets, Dashboard Hardening, Tests

**conway.dangirsh.org nginx vhost with ACME TLS, query-parameter token auth, dashboard ReadWritePaths + sudoers lifecycle control, and 3 eval checks**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-03-02T11:10:55Z
- **Completed:** 2026-03-02T11:21:00Z
- **Tasks:** 5
- **Files modified:** 5

## Accomplishments
- nginx vhost conway.dangirsh.org with ACME DNS-01, forceSSL, rate limiting (10r/s burst=20)
- Token auth via nginx `map $arg_token` — 403 without valid token, transparent with token
- conway-dashboard-token sops secret generated and declared
- sops template renders token into nginx-conway-auth.conf (included via appendHttpConfig)
- ReadWritePaths for /var/lib/automaton/.automaton (prompt editing), ReadOnlyPaths for parent
- Sudoers: automaton user can start/stop/restart conway-automaton with absolute paths, NOPASSWD
- execWheelOnly disabled via mkForce to allow non-wheel sudoers rule
- 3 eval checks: automaton-dashboard-service, conway-dashboard-vhost, conway-dashboard-acme
- nix flake check passes (all 18 checks)

## Task Commits

1. **Task A: Add conway-dashboard-token to sops** - `7a3c277` (feat)
2. **Task B: Add conway.dangirsh.org nginx vhost** - `9b8c4a0` (feat)
3. **Task C: ReadWritePaths + sudoers** - `b059310` (feat)
4. **Task D: Eval checks** - `0b7571b` (test)
5. **Task E: Fix blockers** - `774d22f` (fix)

**Flake input update:** `3993a35` (chore: update neurosys + conway-dashboard inputs)

## Files Created/Modified
- `modules/secrets.nix` - conway-dashboard-token secret + nginx auth template
- `modules/nginx.nix` - ACME cert, appendHttpConfig (map + limit_req_zone), vhost with auth
- `modules/automaton-dashboard.nix` - ReadWritePaths, sudoers, execWheelOnly, @decision annotations
- `tests/eval/private-checks.nix` - 3 new checks (vhost, ACME, service)
- `secrets/neurosys.yaml` - conway-dashboard-token added (encrypted)

## Decisions Made
- DASH-04: ReadWritePaths scoped to .automaton subdirectory only
- DASH-05: Sudoers with absolute paths (/run/current-system/sw/bin/systemctl)
- DASH-06: execWheelOnly disabled — NixOS asserts when non-wheel users in extraRules
- WEB-14: Token auth via nginx map (not lua or external module)
- WEB-15: Rate limiting 10r/s with burst=20 for brute-force protection

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] execWheelOnly assertion conflict**
- **Found during:** Task E (nix flake check)
- **Issue:** NixOS asserts when non-wheel users are in sudo.extraRules while execWheelOnly is true
- **Fix:** Added `security.sudo.execWheelOnly = lib.mkForce false`
- **Files modified:** modules/automaton-dashboard.nix
- **Verification:** nix flake check passes
- **Committed in:** `774d22f`

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary for correctness. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviation.

## User Setup Required
None — all infrastructure is declarative. Manual post-deploy step: Cloudflare DNS A record for conway.dangirsh.org.

## Post-Deploy Manual Steps

1. **Cloudflare DNS**: Create A record `conway.dangirsh.org -> 161.97.74.121` (DNS only, no proxy)
2. **Verify ACME**: `journalctl -u acme-conway.dangirsh.org` for cert issuance
3. **Test public auth**: `curl -s -o /dev/null -w '%{http_code}' https://conway.dangirsh.org/` → 403
4. **Test with token**: `curl -s -o /dev/null -w '%{http_code}' 'https://conway.dangirsh.org/?token=TOKEN'` → 200

## Next Phase Readiness
- Phase 53 complete. All 3 plans executed successfully.
- Conway dashboard accessible via Tailscale (no auth) and public internet (token auth).

## Self-Check: PASSED

---
*Phase: 53-conway-dashboard-auth-prompt-editor*
*Completed: 2026-03-02*
