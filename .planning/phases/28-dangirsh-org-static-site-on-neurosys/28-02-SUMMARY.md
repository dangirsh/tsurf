---
phase: 28-dangirsh-org-static-site-on-neurosys
plan: 02
subsystem: infra
tags: [nixos, nginx, acme, docker, sops, impermanence, reverse-proxy]

requires:
  - phase: 28-01
    provides: dangirsh-site flake output (`packages.x86_64-linux.default`) published on GitHub
provides:
  - OVH-only nginx module with ACME TLS for `dangirsh.org`, `www.dangirsh.org`, and `claw-swap.com`
  - `claw-swap` app exposed on host loopback (`127.0.0.1:3000`) with Docker Caddy removed
  - persisted ACME state (`/var/lib/acme`) for cert/account continuity across reboots
  - neurosys flake wiring for `inputs.dangirsh-site` and refreshed `claw-swap` lock
affects: [hosts-ovh, modules-nginx, claw-swap-module, deploy-script, phase-28]

tech-stack:
  added: [nginx, security.acme]
  patterns: [ovh-only host import, nix-store static-site serving, localhost reverse-proxy target]

key-files:
  created:
    - /data/projects/neurosys/tmp/worktrees/phase-28-02/modules/nginx.nix
    - /data/projects/neurosys/tmp/worktrees/phase-28-02/.planning/phases/28-dangirsh-org-static-site-on-neurosys/28-02-SUMMARY.md
  modified:
    - /data/projects/neurosys/tmp/worktrees/phase-28-02/flake.nix
    - /data/projects/neurosys/tmp/worktrees/phase-28-02/flake.lock
    - /data/projects/neurosys/tmp/worktrees/phase-28-02/hosts/ovh/default.nix
    - /data/projects/neurosys/tmp/worktrees/phase-28-02/modules/impermanence.nix
    - /data/projects/neurosys/tmp/worktrees/phase-28-02/modules/homepage.nix
    - /data/projects/neurosys/tmp/worktrees/phase-28-02/modules/repos.nix
    - /data/projects/neurosys/tmp/worktrees/phase-28-02/scripts/deploy.sh
    - /data/projects/claw-swap/nix/module.nix
    - /data/projects/claw-swap/secrets/claw-swap.yaml
    - /data/projects/neurosys/tmp/worktrees/phase-28-02/.planning/STATE.md

key-decisions:
  - "Enable nginx only on OVH via `hosts/ovh/default.nix` import to preserve HOST-01 isolation."
  - "Serve `dangirsh.org` directly from `inputs.dangirsh-site.packages.x86_64-linux.default` (no app runtime/proxy layer)."
  - "Replace Docker Caddy with host nginx + NixOS ACME; remove Cloudflare origin cert/key secrets from claw-swap."
  - "Persist `/var/lib/acme` in impermanence to preserve LE account/cert state and avoid unnecessary re-issuance."

patterns-established:
  - "Public edge services are host-native NixOS modules; app containers bind loopback-only ports for proxying."
  - "Cross-repo service changes land in source repo first, then consumer flake lock is updated in neurosys."

duration: 16min
completed: 2026-02-23
---

# Phase 28 Plan 02: nginx Unified Reverse Proxy

**OVH now uses NixOS-native nginx+ACME as the single internet-facing edge for `dangirsh.org` static content and `claw-swap.com` reverse proxying, with Docker Caddy fully removed from claw-swap.**

## Performance

- **Duration:** 16min
- **Started:** 2026-02-23T20:37:00Z
- **Completed:** 2026-02-23T20:52:43Z
- **Tasks:** 4
- **Files modified:** 10 (8 neurosys, 2 claw-swap)

## Accomplishments

- Added `dangirsh-site` as a neurosys flake input and locked it to `github:dangirsh/dangirsh.org@c309419`.
- Removed Docker Caddy from `claw-swap`, bound app container to `127.0.0.1:3000`, removed dead Cloudflare origin secrets, pushed `claw-swap/main` as `e3289f4`.
- Added new `modules/nginx.nix` with ACME and OVH virtualHosts for `dangirsh.org`, `www.dangirsh.org`, and `claw-swap.com`.
- Imported nginx module from `hosts/ovh/default.nix` only; verified host compliance (`ovh=true`, `neurosys=false`).
- Persisted `/var/lib/acme`, updated homepage entries/icons for nginx + dangirsh.org, and added `dangirsh/dangirsh.org` to repo bootstrap cloning.
- Updated deploy container checks to remove `claw-swap-caddy` and refreshed neurosys `claw-swap` lock to `e3289f4`.
- Passed `nix flake check` for neurosys after resolving a pre-existing OVH SSH firewall option conflict.

## Task Commits

1. **Task 1: Add dangirsh-site flake input to neurosys** - `24fbb8f` (feat)
2. **Task 2: Remove Docker Caddy, bind app localhost, refresh consumer lock/deploy list** - `e3289f4` in `/data/projects/claw-swap` + `5d8fc6d` in neurosys (refactor/chore)
3. **Task 3: Add OVH-only nginx module and host import** - `1ffe9ea` (feat)
4. **Task 4: Impermanence/homepage/repos updates + validation** - `9f3b962` (feat)

## Files Created/Modified

- `/data/projects/neurosys/tmp/worktrees/phase-28-02/modules/nginx.nix` - unified nginx+ACME edge config.
- `/data/projects/neurosys/tmp/worktrees/phase-28-02/hosts/ovh/default.nix` - OVH-only nginx import and SSH firewall conflict fix.
- `/data/projects/neurosys/tmp/worktrees/phase-28-02/flake.nix` - `dangirsh-site` input declaration.
- `/data/projects/neurosys/tmp/worktrees/phase-28-02/flake.lock` - locked `dangirsh-site` + updated `claw-swap` rev.
- `/data/projects/claw-swap/nix/module.nix` - removed Caddy and bound app port to loopback.
- `/data/projects/claw-swap/secrets/claw-swap.yaml` - removed `claw-swap-cf-origin-cert/key` entries.
- `/data/projects/neurosys/tmp/worktrees/phase-28-02/scripts/deploy.sh` - removed `claw-swap-caddy` health target.
- `/data/projects/neurosys/tmp/worktrees/phase-28-02/modules/impermanence.nix` - persisted `/var/lib/acme`, updated claw-swap data comment.
- `/data/projects/neurosys/tmp/worktrees/phase-28-02/modules/homepage.nix` - added `dangirsh.org` entry and switched claw-swap metadata to nginx.
- `/data/projects/neurosys/tmp/worktrees/phase-28-02/modules/repos.nix` - added clone target `dangirsh/dangirsh.org`.

## Decisions Made

- Keep nginx host-scoped by importing `../../modules/nginx.nix` only in `hosts/ovh/default.nix`.
- Use Let’s Encrypt ACME via NixOS module rather than any container-managed TLS chain.
- Remove stale TLS secret material from the service source repo (`claw-swap`) when the consuming module no longer declares it.
- Use host loopback port binding for app containers behind nginx (`127.0.0.1:3000:3000`) to avoid public exposure.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] OVH eval conflict blocked `nix flake check`**
- **Found during:** Task 4 verification
- **Issue:** `services.openssh.openFirewall` was defined as `false` in shared networking module and `true` in OVH host without priority override.
- **Fix:** Set OVH value to `lib.mkForce true` in `hosts/ovh/default.nix`.
- **Files modified:** `/data/projects/neurosys/tmp/worktrees/phase-28-02/hosts/ovh/default.nix`
- **Verification:** `nix flake check` passed end-to-end.
- **Committed in:** `9f3b962`

---

**Total deviations:** 1 auto-fixed (Rule 3 - Blocking)
**Impact on plan:** Required for plan completion (`nix flake check` done criterion); no scope creep.

## Issues Encountered

- Initial push attempt for `claw-swap` ran in the wrong repo context; reran from `claw-swap` worktree and pushed successfully.
- Fast-forward merge to `claw-swap/main` failed due upstream divergence; re-applied changes on latest `main` and pushed cleanly.

## Next Phase Readiness

- Ready for Plan 28-03 DNS cutover and live ACME issuance for `dangirsh.org` / `www.dangirsh.org`.
- `claw-swap.com` now has a stable localhost upstream target (`127.0.0.1:3000`) for nginx-managed TLS/edge routing.
- No remaining config references to Docker Caddy or Cloudflare origin certs in active claw-swap module/secrets.
