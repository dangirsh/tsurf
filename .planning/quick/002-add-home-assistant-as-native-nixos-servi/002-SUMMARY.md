---
phase: quick-002
plan: 01
subsystem: infra
tags: [home-assistant, nixos, native-service, tailscale]

# Dependency graph
requires:
  - phase: 03-networking
    provides: "Firewall with trustedInterfaces (tailscale0) for tailnet-only access"
provides:
  - "Home Assistant NixOS service on port 8123 (tailnet-only)"
  - "modules/home-assistant.nix module following one-module-per-concern pattern"
affects: [deployment, networking]

# Tech tracking
tech-stack:
  added: [home-assistant]
  patterns: [native-nixos-service-over-docker, tailnet-only-gui-access]

key-files:
  created:
    - modules/home-assistant.nix
  modified:
    - modules/default.nix

key-decisions:
  - "HA-01: Native NixOS service, not Docker container"
  - "HA-02: GUI accessible via Tailscale only (same trustedInterfaces pattern as Syncthing)"

patterns-established:
  - "Tailnet-only service pattern: listen on 0.0.0.0, do not open firewall port, rely on trustedInterfaces"

# Metrics
duration: 2min
completed: 2026-02-17
---

# Quick Task 002: Add Home Assistant as Native NixOS Service Summary

**Home Assistant as native NixOS service on 0.0.0.0:8123, tailnet-only access via trustedInterfaces pattern**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-17T21:56:22Z
- **Completed:** 2026-02-17T21:58:05Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Home Assistant running as native NixOS service (not Docker)
- Declarative config: metric units, Europe/Berlin timezone, default integrations enabled
- Tailnet-only access model: port 8123 not in public firewall, reachable via tailscale0 trustedInterfaces

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Home Assistant NixOS module** - `c1df104` (feat)
2. **Task 2: Register module in default.nix and validate build** - `6a95e07` (feat)

## Files Created/Modified
- `modules/home-assistant.nix` - Home Assistant NixOS service declaration with declarative config
- `modules/default.nix` - Added ./home-assistant.nix to imports list

## Decisions Made
- HA-01: Native NixOS service instead of Docker container -- leverages NixOS module ecosystem for declarative config management
- HA-02: GUI accessible via Tailscale only -- same security model as Syncthing (listen 0.0.0.0, no public firewall port, trustedInterfaces handles access)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## Verification Results
- `nix flake check` passes
- `nix eval .#nixosConfigurations.acfs.config.services.home-assistant.enable` returns `true`
- `nix eval .#nixosConfigurations.acfs.config.services.home-assistant.config` shows correct values (name, timezone, http config, default_config)
- Port 8123 confirmed NOT in `networking.firewall.allowedTCPPorts` (only 22, 80, 443, 22000)

## User Setup Required
None - no external service configuration required. Home Assistant will be available on next deploy via Tailscale at http://<tailnet-ip>:8123.

## Next Steps
- Deploy to acfs server with `scripts/deploy.sh`
- Complete Home Assistant onboarding wizard via Tailscale
- Add integrations and automations as needed

## Self-Check: PASSED

- FOUND: modules/home-assistant.nix
- FOUND: commit c1df104 (Task 1)
- FOUND: commit 6a95e07 (Task 2)
- FOUND: 002-SUMMARY.md

---
*Quick Task: 002*
*Completed: 2026-02-17*
